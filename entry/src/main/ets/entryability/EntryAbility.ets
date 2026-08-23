import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { pushService } from '@kit.PushKit';
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
    });

    // 无感注册：后台静默执行，不阻塞页面加载。内部会先 await ServerManager.ensureLoaded()
    this.silentRegister();
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
      const deviceKey = await service.ensureRegistered(this.context);
      if (deviceKey) {
        hilog.info(DOMAIN, TAG, '无感注册完成，device_key=%{public}s', deviceKey);
      } else {
        hilog.warn(DOMAIN, TAG, '无感注册未返回 device_key，后续启动会重试');
      }
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.error(DOMAIN, TAG, '无感注册异常：%{public}s', msg);
    }
  }
}
