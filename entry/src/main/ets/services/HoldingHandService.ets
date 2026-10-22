import { ApplicationStateChangeCallback, common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { motion } from '@kit.MultimodalAwarenessKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppContextStore } from '../common/AppContextStore';
import { DOMAIN } from '../common/Constant';

const TAG: string = 'HoldingHandService';

/** 通知页专用的握姿订阅边界：前台监听，后台释放，不持久化传感器状态。 */
export class HoldingHandService {
  // 只有通知页可见时才持有回调；停止后的迟到事件不能再写页面状态。
  private static listener: ((left: boolean) => void) | null = null;
  private static application: common.ApplicationContext | null = null;
  private static subscribed: boolean = false;
  private static foreground: boolean = true;
  private static left: boolean = false;
  // on/off 使用相同回调，避免误取消其它模块的握姿监听。
  private static holdingCallback = (status: motion.HoldingHandStatus): void => {
    if (HoldingHandService.listener === null || !HoldingHandService.foreground) {
      return;
    }
    if (status === motion.HoldingHandStatus.LEFT_HAND_HELD) {
      HoldingHandService.left = true;
    } else if (status === motion.HoldingHandStatus.RIGHT_HAND_HELD) {
      HoldingHandService.left = false;
    } else {
      // 双手、放下和未知状态不引起左右反复跳动。
      return;
    }
    HoldingHandService.listener(HoldingHandService.left);
  };
  private static applicationCallback: ApplicationStateChangeCallback = {
    onApplicationForeground: (): void => {
      HoldingHandService.foreground = true;
      HoldingHandService.subscribeMotion();
    },
    onApplicationBackground: (): void => {
      HoldingHandService.foreground = false;
      HoldingHandService.unsubscribeMotion();
    }
  };

  /** 页面可见时调用；重复启动只替换消费者，不重复订阅。 */
  static start(listener: (left: boolean) => void): void {
    HoldingHandService.listener = listener;
    listener(HoldingHandService.left);
    if (HoldingHandService.application !== null) {
      HoldingHandService.subscribeMotion();
      return;
    }
    const context = AppContextStore.getInstance().getContext();
    if (context === null) {
      HoldingHandService.useDefaultSide();
      return;
    }
    try {
      const application = context.getApplicationContext();
      application.on('applicationStateChange', HoldingHandService.applicationCallback);
      HoldingHandService.application = application;
      HoldingHandService.foreground = true;
      HoldingHandService.subscribeMotion();
    } catch (err) {
      HoldingHandService.logFailure('启动握姿监听失败', err as BusinessError);
      HoldingHandService.useDefaultSide();
    }
  }

  /** 切走通知页或组件销毁时释放；不删除其它消费者的生命周期监听。 */
  static stop(): void {
    HoldingHandService.listener = null;
    HoldingHandService.unsubscribeMotion();
    if (HoldingHandService.application !== null) {
      try {
        HoldingHandService.application.off('applicationStateChange', HoldingHandService.applicationCallback);
        HoldingHandService.application = null;
      } catch (err) {
        // 保留引用，后续 start 不会重复注册；迟到的前台事件由 listener 门禁拦截。
        HoldingHandService.logFailure('取消前后台监听失败', err as BusinessError);
      }
    }
  }

  /** 不支持设备或权限错误均降级为默认右侧，不打断通知操作。 */
  private static subscribeMotion(): void {
    if (HoldingHandService.listener === null || !HoldingHandService.foreground || HoldingHandService.subscribed) {
      return;
    }
    try {
      motion.on('holdingHandChanged', HoldingHandService.holdingCallback);
      HoldingHandService.subscribed = true;
    } catch (err) {
      HoldingHandService.logFailure('设备握姿能力不可用', err as BusinessError);
      HoldingHandService.useDefaultSide();
    }
  }

  /** 只对成功订阅调用 off；失败时保留订阅标记，避免重入时重复注册。 */
  private static unsubscribeMotion(): void {
    if (!HoldingHandService.subscribed) {
      return;
    }
    try {
      motion.off('holdingHandChanged', HoldingHandService.holdingCallback);
      HoldingHandService.subscribed = false;
    } catch (err) {
      HoldingHandService.logFailure('取消握姿监听失败', err as BusinessError);
    }
  }

  /** 降级通知沿用相同回调路径，确保标题栏和悬浮按钮总在同一侧。 */
  private static useDefaultSide(): void {
    HoldingHandService.left = false;
    if (HoldingHandService.listener !== null) {
      HoldingHandService.listener(false);
    }
  }

  /** 只记录错误码，不记录传感器数据。 */
  private static logFailure(action: string, error: BusinessError): void {
    hilog.warn(DOMAIN, TAG, '%{public}s，code=%{public}d', action, error.code);
  }
}
