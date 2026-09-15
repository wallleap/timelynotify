import { BusinessError } from '@kit.BasicServicesKit';
import { ConfigurationConstant, common, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { UIContext } from '@kit.ArkUI';
import { PreferencesUtil } from '../utils/PreferencesUtil';
import { AppContextStore } from '../common/AppContextStore';
import showToast from '../components/showToast';
import { DOMAIN } from '../common/Constant';

const TAG: string = 'ThemeSvc';

/**
 * 主题与沉浸光感服务：
 *  - 主题颜色模式持久化 + 应用级即时切换（应用级 setColorMode，全页面即时换肤）
 *  - 沉浸光感开关持久化（不原地写 AppStorage：Index.build 依赖该值选 HdsTabs/Tabs 分支，
 *    原地切换会导致 Tabs 整体重建、Tab 落回通知页 bug；重启后由 EntryAbility.onCreate 读盘写入）
 *  - 应用重启（restartApp，API 22+，最低兼容 API 23 全设备）
 */
export class ThemeService {
  /**
   * 应用主题颜色模式：持久化用户选择 + 应用级即时切换。
   * @param key 主题键值：'dark' | 'light' | 'system'
   * @param uiCtx 调用方 UIContext（仅用于失败时的 Toast 提示，可为 null）
   * @returns true=持久化成功（应用级切换失败仅 Toast 提示，不影响持久化结果）
   */
  static async applyColorMode(key: string, uiCtx: UIContext | null): Promise<boolean> {
    PreferencesUtil.putString(null, PreferencesUtil.KEY_COLOR_MODE, key);
    const mode: ConfigurationConstant.ColorMode = key === 'light'
      ? ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT
      : key === 'dark' ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK
        : ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
    const ctx = AppContextStore.getInstance().getContext();
    if (ctx) {
      try {
        // 应用级切换：全部页面即时换肤；深浅色变化会触发 EntryAbility.onConfigurationUpdate 同步状态栏样式
        ctx.getApplicationContext().setColorMode(mode);
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        hilog.warn(DOMAIN, TAG, 'setColorMode 失败：%{public}s', msg);
        if (uiCtx) {
          showToast(uiCtx, '主题切换失败');
        }
      }
    }
    return true;
  }

  /**
   * 沉浸光感开关持久化（仅写盘，不写 AppStorage）。
   * 调用方在确认后应当再调用 restartApp 让新实例 EntryAbility.onCreate 读盘生效。
   * @param enable true=开启沉浸光感；false=关闭（回退 blur）
   * @returns true=持久化成功
   */
  static async setImmersiveLightEnabled(enable: boolean): Promise<boolean> {
    const ok: boolean = await PreferencesUtil.putString(
      null, PreferencesUtil.KEY_IMMERSIVE_LIGHT_ENABLED, enable ? 'true' : 'false'
    );
    if (ok) {
      hilog.info(DOMAIN, TAG, '沉浸光感开关已保存：%{public}s', String(enable));
    }
    return ok;
  }

  /**
   * 重启应用（官方应用重启 API：UIAbilityContext.restartApp，自 API 22 起，最低兼容 API 23）。
   * 重启进程并拉起 EntryAbility，窗口保留（用户视野不回桌面）；
   * 不触发 onDestroy，偏好已在重启前持久化，新实例 EntryAbility.onCreate 读盘写入 AppStorage。
   * @param uiCtx 调用方 UIContext（仅用于失败 Toast 提示）
   * @returns true=已触发；false=失败（context 获取失败或调用异常）
   */
  static async restartApp(uiCtx: UIContext): Promise<boolean> {
    const ctx: common.UIAbilityContext | null = ThemeService.getAbilityContext(uiCtx);
    if (!ctx) {
      showToast(uiCtx, '重启失败，请手动重启应用', 3000);
      return false;
    }
    const want: Want = {
      deviceId: '',
      bundleName: ctx.abilityInfo.bundleName,
      abilityName: ctx.abilityInfo.name,
    };
    try {
      await ctx.restartApp(want);
      hilog.info(DOMAIN, TAG, '应用重启已触发');
      return true;
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      hilog.warn(DOMAIN, TAG, '应用重启失败：code=%{public}d msg=%{public}s', e.code, e.message);
      showToast(uiCtx, '重启失败，请手动重启应用', 3000);
      return false;
    }
  }

  /**
   * 从 UIContext 获取 UIAbilityContext（notificationManager / restartApp 等需要）。
   * 失败返回 null（异常已记录日志）。
   */
  static getAbilityContext(uiCtx: UIContext): common.UIAbilityContext | null {
    try {
      const ctx = uiCtx.getHostContext();
      return ctx as common.UIAbilityContext;
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, TAG, 'getHostContext 失败：%{public}s', msg);
      return null;
    }
  }
}
