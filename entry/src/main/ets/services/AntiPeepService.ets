import { ApplicationStateChangeCallback, common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { dlpAntiPeep } from '@kit.DeviceSecurityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { AppContextStore } from '../common/AppContextStore';
import { DOMAIN } from '../common/Constant';
import { PreferencesUtil } from '../utils/PreferencesUtil';

/** 通知与服务组件只读取保护状态，不接触系统感知接口或持久化偏好。 */
export const KEY_ANTI_PEEP_BLUR: string = 'antiPeepBlur';
export const KEY_ANTI_PEEP_ERROR: string = 'antiPeepError';
export const KEY_ANTI_PEEP_PREVIEW_VISIBLE: string = 'antiPeepPreviewVisible';
export const ANTI_PEEP_MODE_BLUR: string = 'blur';
export const ANTI_PEEP_MODE_FULLSCREEN: string = 'fullscreen';
const TAG: string = 'AntiPeepService';

/** 开关与模式原子保存；无历史偏好时关闭，模式默认模糊通知。 */
export class AntiPeepSettings {
  enabled: boolean = false;
  mode: string = ANTI_PEEP_MODE_BLUR;
}

/** 防窥服务：仅在应用前台的指定页面监听 HIDE/PASS，并按所选模式保护当前窗口。 */
export class AntiPeepService {
  private static settings: AntiPeepSettings = new AntiPeepSettings();
  private static loading: Promise<void> | null = null;
  private static supported: boolean | null = null;
  private static running: boolean = false;
  private static foreground: boolean = true;
  // 默认不保护任何页面，由主页按当前可见路由及 Tab 明确启用。
  private static pageActive: boolean = false;
  private static subscribed: boolean = false;
  private static application: common.ApplicationContext | null = null;
  private static generation: number = 0;
  private static hide: boolean = false;
  // 同一前台检测轮的 HIDE 只触发一次系统蒙层，重新检测或 PASS 后允许下一次触发。
  private static maskRequested: boolean = false;
  // PASS 后再次 HIDE 属于新风险轮，旧窗口查询不得借新状态重新触发蒙层。
  private static maskRequestSequence: number = 0;
  private static error: string = '';
  private static callback = (status: dlpAntiPeep.DlpAntiPeepStatus): void => {
    if (!AntiPeepService.shouldProtect()) return;
    AntiPeepService.applyStatus(status);
  };
  private static applicationCallback: ApplicationStateChangeCallback = {
    onApplicationForeground: (): void => {
      AntiPeepService.foreground = true;
      AntiPeepService.refresh();
    },
    onApplicationBackground: (): void => {
      AntiPeepService.foreground = false;
      AntiPeepService.generation++;
      AntiPeepService.unsubscribe();
      AntiPeepService.publishBlur(false);
    }
  };

  /** 查询系统开关同时验证实际能力；开关为 false 仍代表支持，201 不当成硬件不支持。 */
  static async checkSupport(): Promise<boolean> {
    try {
      if (!canIUse('SystemCapability.Security.DlpAntiPeep')) {
        AntiPeepService.supported = false;
        return false;
      }
      if (AntiPeepService.supported === false) return false;
      await dlpAntiPeep.isDlpAntiPeepSwitchOn();
      AntiPeepService.supported = true;
      return true;
    } catch (err) {
      AntiPeepService.recordFailure(err as BusinessError);
      return false;
    }
  }

  /** 返回副本，设置组件不能直接修改服务的运行态。 */
  static async getSettings(): Promise<AntiPeepSettings> {
    await AntiPeepService.load();
    const result: AntiPeepSettings = new AntiPeepSettings();
    result.enabled = AntiPeepService.settings.enabled;
    result.mode = AntiPeepService.settings.mode;
    return result;
  }

  /** 只有用户主动开启时才请求系统防窥开关；取消或 ACL 不可用不保存开启态。 */
  static async setEnabled(enabled: boolean): Promise<boolean> {
    await AntiPeepService.load();
    AntiPeepService.setError('');
    if (enabled) {
      if (!(await AntiPeepService.checkSupport())) return false;
      try {
        if (!(await dlpAntiPeep.isDlpAntiPeepSwitchOn())) {
          const context = AppContextStore.getInstance().getContext();
          if (context === null) return false;
          const result = await dlpAntiPeep.requestAntiPeepOptions(context);
          if (result === dlpAntiPeep.AntiPeepOptionsResult.FAIL ||
            !(await dlpAntiPeep.isDlpAntiPeepSwitchOn())) {
            AntiPeepService.setError('系统防窥未开启');
            return false;
          }
        }
      } catch (err) {
        AntiPeepService.recordFailure(err as BusinessError);
        return false;
      }
    }
    const next: AntiPeepSettings = await AntiPeepService.getSettings();
    next.enabled = enabled;
    return AntiPeepService.save(next);
  }

  /** 模式独立于开关保留，但只接受两个已实现的模式标识。 */
  static async setMode(mode: string): Promise<boolean> {
    if (mode !== ANTI_PEEP_MODE_BLUR && mode !== ANTI_PEEP_MODE_FULLSCREEN) return false;
    const next: AntiPeepSettings = await AntiPeepService.getSettings();
    next.mode = mode;
    return AntiPeepService.save(next);
  }

  static getError(): string {
    return AntiPeepService.error;
  }

  /** 主页显隐及 Tab 切换调用；离开范围立即清除模糊并废弃迟到的系统请求。 */
  static setPageActive(active: boolean): void {
    if (AntiPeepService.pageActive === active) return;
    AntiPeepService.pageActive = active;
    AntiPeepService.generation++;
    AntiPeepService.maskRequestSequence++;
    AntiPeepService.maskRequested = false;
    AntiPeepService.hide = false;
    if (!active) {
      AntiPeepService.unsubscribe();
      AntiPeepService.publishBlur(false);
    } else if (AntiPeepService.running && AntiPeepService.foreground) {
      // 返回保护页必须重新读取系统初值，不能沿用离开前的 PASS/HIDE。
      AntiPeepService.refresh();
    }
  }

  /** 初始化应用前后台协调；是否监听和请求蒙层仍受当前页面范围限制。 */
  static start(): void {
    if (!AntiPeepService.running) AntiPeepService.foreground = true;
    AntiPeepService.running = true;
    const context = AppContextStore.getInstance().getContext();
    if (context !== null && AntiPeepService.application === null) {
      try {
        const application = context.getApplicationContext();
        application.on('applicationStateChange', AntiPeepService.applicationCallback);
        AntiPeepService.application = application;
      } catch (err) {
        AntiPeepService.recordFailure(err as BusinessError);
      }
    }
    AntiPeepService.refresh();
  }

  /** 主页实例销毁才整体释放，切 Tab 或路由隐藏不调用此方法。 */
  static stop(): void {
    AntiPeepService.running = false;
    AntiPeepService.pageActive = false;
    AntiPeepService.generation++;
    AntiPeepService.unsubscribe();
    AntiPeepService.publishBlur(false);
    if (AntiPeepService.application !== null) {
      try {
        AntiPeepService.application.off('applicationStateChange', AntiPeepService.applicationCallback);
        AntiPeepService.application = null;
      } catch (err) {
        AntiPeepService.recordFailure(err as BusinessError);
      }
    }
  }

  /** 异步读取统一配置；解析异常回到默认关闭，不保存或外传任何感知数据。 */
  private static async load(): Promise<void> {
    if (AntiPeepService.loading === null) {
      AntiPeepService.loading = PreferencesUtil.getString(null,
        PreferencesUtil.KEY_ANTI_PEEP_SETTINGS, '').then((value: string): void => {
        if (!value) return;
        try {
          const raw = JSON.parse(value) as Record<string, Object>;
          AntiPeepService.settings.enabled = raw['enabled'] === true;
          AntiPeepService.settings.mode = raw['mode'] === ANTI_PEEP_MODE_FULLSCREEN ?
            ANTI_PEEP_MODE_FULLSCREEN : ANTI_PEEP_MODE_BLUR;
        } catch (_err) {
          AntiPeepService.settings = new AntiPeepSettings();
        }
      });
    }
    await AntiPeepService.loading;
  }

  /** 写盘成功再发布，模式和开关不会出现部分保存；刷新失败保留偏好并明确反馈运行错误。 */
  private static async save(next: AntiPeepSettings): Promise<boolean> {
    if (!(await PreferencesUtil.putString(null, PreferencesUtil.KEY_ANTI_PEEP_SETTINGS, JSON.stringify(next)))) {
      AntiPeepService.setError('保存失败，设置未生效');
      return false;
    }
    AntiPeepService.settings = next;
    AntiPeepService.maskRequested = false;
    await AntiPeepService.refresh();
    return true;
  }

  /** 仅保护页恢复时查询开关和初值；代次拦截后台、路由离开或旧配置结果。 */
  private static async refresh(): Promise<void> {
    const generation: number = ++AntiPeepService.generation;
    AntiPeepService.maskRequested = false;
    await AntiPeepService.load();
    if (generation !== AntiPeepService.generation) return;
    if (!AntiPeepService.shouldProtect()) {
      AntiPeepService.unsubscribe();
      AntiPeepService.publishBlur(false);
      return;
    }
    // 等待系统结果期间暂时隐藏通知内容，避免前台恢复时出现明文闪现。
    AntiPeepService.publishBlur(true);
    try {
      if (!(await AntiPeepService.checkSupport())) {
        if (generation === AntiPeepService.generation) {
          AntiPeepService.unsubscribe();
          // 不可用设备或签名权限缺失时停止功能，不能让迁移来的开启偏好造成永久模糊。
          AntiPeepService.publishBlur(false);
        }
        return;
      }
      if (generation !== AntiPeepService.generation) return;
      if (!(await dlpAntiPeep.isDlpAntiPeepSwitchOn())) {
        if (generation !== AntiPeepService.generation) return;
        AntiPeepService.unsubscribe();
        AntiPeepService.publishBlur(false);
        AntiPeepService.setError('系统防窥未开启');
        return;
      }
      if (generation !== AntiPeepService.generation) return;
      if (!AntiPeepService.subscribed) {
        dlpAntiPeep.on('dlpAntiPeep', AntiPeepService.callback);
        AntiPeepService.subscribed = true;
      }
      // 订阅后读取初值，避免只等待事件而错过已经存在的窥视状态。
      AntiPeepService.setError('');
      AntiPeepService.applyStatus(dlpAntiPeep.getDlpAntiPeepInfo());
    } catch (err) {
      if (generation !== AntiPeepService.generation) return;
      AntiPeepService.unsubscribe();
      AntiPeepService.recordFailure(err as BusinessError);
    }
  }

  /** PASS 解除应用内容模糊；HIDE 全屏模式在系统蒙层完成前同样先保护通知。 */
  private static applyStatus(status: dlpAntiPeep.DlpAntiPeepStatus): void {
    if (!AntiPeepService.shouldProtect()) return;
    AntiPeepService.hide = status === dlpAntiPeep.DlpAntiPeepStatus.HIDE;
    AntiPeepService.publishBlur(AntiPeepService.hide);
    if (!AntiPeepService.hide) {
      AntiPeepService.maskRequested = false;
      AntiPeepService.maskRequestSequence++;
    } else if (AntiPeepService.settings.mode === ANTI_PEEP_MODE_FULLSCREEN && !AntiPeepService.maskRequested) {
      AntiPeepService.maskRequested = true;
      AntiPeepService.showSystemMask(AntiPeepService.generation, ++AntiPeepService.maskRequestSequence);
    }
  }

  /** 系统蒙层覆盖整个窗口（包含 Sheet）；窗口查找完成前再次核对代次和模式。 */
  private static async showSystemMask(generation: number, requestSequence: number): Promise<void> {
    const context = AppContextStore.getInstance().getContext();
    if (context === null) {
      AntiPeepService.setError('防窥暂不可用');
      return;
    }
    try {
      const currentWindow = await window.getLastWindow(context);
      if (generation !== AntiPeepService.generation || requestSequence !== AntiPeepService.maskRequestSequence ||
        !AntiPeepService.shouldProtect() || !AntiPeepService.hide ||
        AntiPeepService.settings.mode !== ANTI_PEEP_MODE_FULLSCREEN) return;
      await dlpAntiPeep.setAntiPeepMaskLayer(currentWindow.getWindowProperties().id);
    } catch (err) {
      if (generation === AntiPeepService.generation && requestSequence === AntiPeepService.maskRequestSequence) {
        AntiPeepService.recordFailure(err as BusinessError);
      }
    }
  }

  /** 设置页仍可保存偏好和播放预览，但不会因此激活真实监听或系统蒙层。 */
  private static shouldProtect(): boolean {
    return AntiPeepService.running && AntiPeepService.foreground &&
      AntiPeepService.pageActive && AntiPeepService.settings.enabled;
  }

  /** 取消只指定本服务回调；失败保留标记，避免前台恢复时重复订阅。 */
  private static unsubscribe(): void {
    if (!AntiPeepService.subscribed) return;
    try {
      dlpAntiPeep.off('dlpAntiPeep', AntiPeepService.callback);
      AntiPeepService.subscribed = false;
    } catch (err) {
      AntiPeepService.recordFailure(err as BusinessError);
    }
  }

  private static publishBlur(hidden: boolean): void {
    AppStorage.setOrCreate(KEY_ANTI_PEEP_BLUR, hidden);
  }

  private static setError(message: string): void {
    AntiPeepService.error = message;
    AppStorage.setOrCreate(KEY_ANTI_PEEP_ERROR, message);
  }

  /** 日志只记录系统码；权限、临时错误不缓存为设备不支持。 */
  private static recordFailure(error: BusinessError): void {
    if (error.code === 801) AntiPeepService.supported = false;
    AntiPeepService.setError(error.code === 201 ? '防窥权限暂不可用' : '防窥暂不可用');
    hilog.warn(DOMAIN, TAG, '防窥接口失败 code=%{public}d', error.code);
  }
}
