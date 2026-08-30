import { AbilityConstant, Configuration, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { display, window } from '@kit.ArkUI';
import { pushService } from '@kit.PushKit';
import { notificationManager } from '@kit.NotificationKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppContextStore } from '../common/AppContextStore';
import { DeviceRegisterService } from '../services/DeviceRegisterService';
import { ServerManager } from '../services/ServerManager';
import { KEY_NAV_BAR_HEIGHT, KEY_STATUS_BAR_HEIGHT } from '../utils/ImmersiveUtil';
import { DOMAIN } from '../common/Constant';

const TAG: string = 'EntryAbility';

export default class EntryAbility extends UIAbility {
  // 主窗口引用：沉浸式配置与深浅色切换时复用，避免重复查询
  private mainWindow: window.Window | null = null;
  // 沉浸式布局是否开启成功；失败（如自由窗口场景）时保持默认布局，页面不做额外避让
  private immersiveEnabled: boolean = false;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    // 最早拿到 UIAbilityContext 的时机，注入全局存储，之后组件/dialog/持久化都可以用
    AppContextStore.getInstance().setContext(this.context);
    hilog.info(DOMAIN, TAG, 'Ability onCreate');
    // 立刻触发 ServerManager 异步加载（与页面渲染/窗口创建并行），
    // 但任何消费 currentId/baseURL 的路径都必须先 await ensureLoaded()
    this.bootstrapServerManager();
    // 在 onCreate 中触发无感注册（Push Kit 文档推荐时机），内部会 await ServerManager.ensureLoaded()
    // 然后调用 pushService.getToken() 拿 token 并写入服务端
    this.silentRegister();
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, TAG, 'Ability onWindowStageCreate');

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, TAG, 'Succeeded in loading the content.');
      // 方式一：开启沉浸式布局（内容延伸到状态栏/导航条区域）
      this.setupImmersiveWindow(windowStage);
      // 启动时请求通知权限（首次会弹系统授权窗；已授权/拒绝过则不弹）
      this.requestNotificationPermission();
    });
  }

  // 系统配置变化（深浅色切换/旋转/折叠等）：仅沉浸式布局生效时同步状态栏样式与安全区高度
  onConfigurationUpdate(newConfig: Configuration): void {
    if (!this.immersiveEnabled) {
      return;
    }
    this.refreshSystemBarStyle();
    this.refreshSafeAreaStorage();
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, TAG, 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(DOMAIN, TAG, 'Ability onForeground');
  }

  onBackground(): void {
    hilog.info(DOMAIN, TAG, 'Ability onBackground');
  }

  /**
   * 开启窗口沉浸式布局（方式一），并完成状态栏样式与安全区高度初始化。
   * 页面层通过 @StorageProp 读取安全区高度做避让（方式二辅助：背景延伸由布局本身完成）。
   * 失败场景（自由窗口等不支持全屏布局的形态）回退默认布局，安全区高度写 0。
   */
  private setupImmersiveWindow(windowStage: window.WindowStage): void {
    let win: window.Window;
    try {
      win = windowStage.getMainWindowSync();
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.error(DOMAIN, TAG, '获取主窗口失败：%{public}s', msg);
      return;
    }
    this.mainWindow = win;
    win.setWindowLayoutFullScreen(true).then(() => {
      this.immersiveEnabled = true;
      hilog.info(DOMAIN, TAG, '沉浸式布局已开启');
      // 状态栏透明背景 + 文字颜色跟随当前深浅色
      this.refreshSystemBarStyle();
      // 计算状态栏/导航条高度写入 AppStorage，供页面 @StorageProp 读取避让
      this.refreshSafeAreaStorage();
    }).catch((err: BusinessError) => {
      hilog.warn(DOMAIN, TAG, '沉浸式布局开启失败 code=%{public}d msg=%{public}s，回退默认布局',
        err.code, err.message);
      // 回退默认布局：系统自动避让，页面侧避让量归零
      AppStorage.setOrCreate(KEY_STATUS_BAR_HEIGHT, 0);
      AppStorage.setOrCreate(KEY_NAV_BAR_HEIGHT, 0);
    });
  }

  /** 按当前深浅色模式设置状态栏样式：背景透明，文字颜色黑/白自适应 */
  private refreshSystemBarStyle(): void {
    if (!this.mainWindow) {
      return;
    }
    try {
      // 从 ResourceManager 读取当前系统实际深浅色（应用自身为 COLOR_MODE_NOT_SET 跟随系统）
      // 两个模块的 ColorMode 枚举类型不同但数值一致，统一转 number 比较
      const config = this.context.resourceManager.getConfigurationSync();
      const isDark: boolean =
        (config.colorMode as number) === (ConfigurationConstant.ColorMode.COLOR_MODE_DARK as number);
      this.mainWindow.setWindowSystemBarProperties({
        statusBarColor: '#00000000',
        statusBarContentColor: isDark ? '#FFFFFF' : '#000000',
      });
      hilog.info(DOMAIN, TAG, '状态栏样式已刷新：isDark=%{public}s', String(isDark));
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, TAG, '设置状态栏样式失败：%{public}s', msg);
    }
  }

  /** 计算状态栏/导航条避让高度（px → vp）写入 AppStorage，页面通过 @StorageProp 读取 */
  private refreshSafeAreaStorage(): void {
    if (!this.mainWindow) {
      return;
    }
    try {
      const d: display.Display = display.getDefaultDisplaySync();
      const density: number = d.densityPixels;
      // 顶部：状态栏避让区
      const sysArea: window.AvoidArea =
        this.mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      // 底部：手势指示条避让区
      const indicator: window.AvoidArea =
        this.mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      const topVp: number = sysArea.topRect.height / density;
      const bottomVp: number = indicator.bottomRect.height / density;
      AppStorage.setOrCreate(KEY_STATUS_BAR_HEIGHT, topVp);
      AppStorage.setOrCreate(KEY_NAV_BAR_HEIGHT, bottomVp);
      hilog.info(DOMAIN, TAG, '安全区高度：状态栏=%{public}fvp 导航条=%{public}fvp', topVp, bottomVp);
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, TAG, '获取避让区高度失败：%{public}s', msg);
    }
  }

  private async bootstrapServerManager(): Promise<void> {
    try {
      await ServerManager.getInstance().load(this.context);
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.error(DOMAIN, TAG, 'ServerManager 加载异常：%{public}s', msg);
    }
  }

  private async silentRegister(): Promise<void> {
    try {
      const service = DeviceRegisterService.getInstance();
      // 注入华为 Push Kit 真实 token 获取逻辑
      service.setDeviceTokenProvider(async (): Promise<string> => {
        try {
          const token: string = await pushService.getToken();
          hilog.info(DOMAIN, TAG, 'Succeeded in getting push token.');
          return token;
        } catch (err) {
          const e: BusinessError = err as BusinessError;
          hilog.error(DOMAIN, TAG, 'Failed to get push token: %{public}d %{public}s', e.code, e.message);
          // 失败返回空，DeviceRegisterService 会因 token 为空中止注册并下次重试
          return '';
        }
      });
      // 启动时检测 Push token 是否变更；变更则重绑所有已注册 server
      const tokenChanged: boolean = await service.refreshTokenIfNeeded(this.context);
      if (tokenChanged) {
        hilog.info(DOMAIN, TAG, 'device_token 已更新并触发各 server 重绑');
      }
      const deviceKey = await service.ensureRegistered(this.context);
      if (deviceKey) {
        hilog.info(DOMAIN, TAG, '无感注册完成，device_key=%{public}s', deviceKey);
      } else {
        hilog.warn(DOMAIN, TAG, '无感注册未返回 device_key，后续启动会重试');
      }
      // 启动后异步验证/还原当前 server 的 per-server device_key
      this.syncCurrentServerKey();
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.error(DOMAIN, TAG, '无感注册异常：%{public}s', msg);
    }
  }

  private async syncCurrentServerKey(): Promise<void> {
    const mgr: ServerManager = ServerManager.getInstance();
    // 必须先等加载完成，否则冷启动时 servers 为空，getCurrentServer 返回 null 会跳过 sync
    await mgr.ensureLoaded();
    const cur = mgr.getCurrentServer();
    if (!cur) {
      return;
    }
    const baseURL: string = mgr.getCurrentBaseURL();
    DeviceRegisterService.getInstance().syncKeyForServer(
      this.context, cur.id, baseURL, cur.deviceKey
    ).then((key: string | null) => {
      hilog.info(DOMAIN, TAG, '启动 syncKeyForServer 完成：key=%{public}s', key ?? 'null');
    }).catch((err: Error) => {
      hilog.warn(DOMAIN, TAG, '启动 syncKeyForServer 异常：%{public}s', err.message);
    });
  }

  // 启动时请求通知权限：首次安装会弹系统授权窗，之后不再弹
  private requestNotificationPermission(): void {
    notificationManager.requestEnableNotification(this.context).then(() => {
      hilog.info(DOMAIN, TAG, '通知权限已授权');
    }).catch((err: BusinessError) => {
      hilog.warn(DOMAIN, TAG, '通知权限未授权：code=%{public}d msg=%{public}s', err.code, err.message);
    });
  }
}
