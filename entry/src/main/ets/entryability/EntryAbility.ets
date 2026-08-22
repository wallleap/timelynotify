import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { DeviceRegisterService } from '../services/DeviceRegisterService';

const DOMAIN: number = 0x0000;
const TAG: string = 'EntryAbility';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    hilog.info(DOMAIN, TAG, 'Ability onCreate');
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

    // 无感注册：后台静默执行，不阻塞页面加载
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

  private async silentRegister(): Promise<void> {
    try {
      const service = DeviceRegisterService.getInstance();
      // 接入华为 Push Kit 后，取消注释并替换为真实 token 获取逻辑：
      // service.setDeviceTokenProvider(async () => {
      //   // 示例：通过华为 Push Kit 获取 token
      //   // return await push.getToken();
      //   return 'your-real-push-token';
      // });
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
