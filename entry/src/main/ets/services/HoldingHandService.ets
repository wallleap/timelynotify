import { ApplicationStateChangeCallback, common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { motion } from '@kit.MultimodalAwarenessKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppContextStore } from '../common/AppContextStore';
import { DOMAIN } from '../common/Constant';

const TAG: string = 'HoldingHandService';

/** 主页共用的握姿订阅边界：按页面注册、前台监听，不持久化传感器状态。 */
export class HoldingHandService {
  // 页面独立持有回调，Tab 切换时旧页停止不能取消新页已注册的消费者。
  private static listeners: Map<string, (left: boolean) => void> = new Map<string, (left: boolean) => void>();
  private static application: common.ApplicationContext | null = null;
  private static subscribed: boolean = false;
  private static foreground: boolean = true;
  private static left: boolean = false;
  // on/off 使用相同回调，避免误取消其它模块的握姿监听。
  private static holdingCallback = (status: motion.HoldingHandStatus): void => {
    if (HoldingHandService.listeners.size === 0 || !HoldingHandService.foreground) {
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
    HoldingHandService.notifyListeners();
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

  /** 页面可见时注册；默认 owner 保留原通知页接口，同页重复启动只替换自身回调。 */
  static start(listener: (left: boolean) => void, owner: string = 'notify'): void {
    HoldingHandService.listeners.set(owner, listener);
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

  /** 仅移除指定页面；最后一个消费者离开后才释放系统订阅与生命周期监听。 */
  static stop(owner: string = 'notify'): void {
    HoldingHandService.listeners.delete(owner);
    if (HoldingHandService.listeners.size > 0) {
      return;
    }
    HoldingHandService.unsubscribeMotion();
    if (HoldingHandService.application !== null) {
      try {
        HoldingHandService.application.off('applicationStateChange', HoldingHandService.applicationCallback);
        HoldingHandService.application = null;
      } catch (err) {
        // 保留引用，后续 start 不会重复注册；迟到的前台事件由消费者数量门禁拦截。
        HoldingHandService.logFailure('取消前后台监听失败', err as BusinessError);
      }
    }
  }

  /** 不支持设备或权限错误均降级为默认右侧，不打断通知操作。 */
  private static subscribeMotion(): void {
    if (HoldingHandService.listeners.size === 0 || !HoldingHandService.foreground || HoldingHandService.subscribed) {
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
    HoldingHandService.notifyListeners();
  }

  /** 广播同一握姿；Map 删除的页面不会再接收迟到的系统回调。 */
  private static notifyListeners(): void {
    HoldingHandService.listeners.forEach((listener: (left: boolean) => void): void => {
      listener(HoldingHandService.left);
    });
  }

  /** 只记录错误码，不记录传感器数据。 */
  private static logFailure(action: string, error: BusinessError): void {
    hilog.warn(DOMAIN, TAG, '%{public}s，code=%{public}d', action, error.code);
  }
}
