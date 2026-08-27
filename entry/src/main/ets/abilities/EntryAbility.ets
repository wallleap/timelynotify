import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { pushService } from '@kit.PushKit';
import { notificationManager } from '@kit.NotificationKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppContextStore } from '../common/AppContextStore';
import { DeviceRegisterService } from '../services/DeviceRegisterService';
import { ServerManager } from '../services/ServerManager';

const DOMAIN: number = 0x0000;
const TAG: string = 'EntryAbility';

export default class EntryAbility extends UIAbility {
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
      // 启动时请求通知权限（首次会弹系统授权窗；已授权/拒绝过则不弹）
      this.requestNotificationPermission();
    });
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
