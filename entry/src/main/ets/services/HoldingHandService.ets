import { ApplicationStateChangeCallback, common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { motion } from '@kit.MultimodalAwarenessKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppContextStore } from '../common/AppContextStore';
import { DOMAIN } from '../common/Constant';
import { PreferencesUtil } from '../utils/PreferencesUtil';

const TAG: string = 'HoldingHandService';

/** 主页共用的握姿订阅边界：按页面注册、前台监听，不持久化传感器状态。 */
export class HoldingHandService {
  // 页面独立持有回调，Tab 切换时旧页停止不能取消新页已注册的消费者。
  private static listeners: Map<string, (left: boolean) => void> = new Map<string, (left: boolean) => void>();
  private static application: common.ApplicationContext | null = null;
  private static subscribed: boolean = false;
  private static foreground: boolean = true;
  private static left: boolean = false;
  // 未读完偏好前不订阅传感器，避免已关闭的用户冷启动时短暂启用。
  private static enabled: boolean | null = null;
  private static loading: Promise<boolean> | null = null;
  // 与用户偏好分离：仅系统能力缺失或 801 认定不支持，其它错误允许下次重试。
  private static supported: boolean | null = null;
  // on/off 使用相同回调，避免误取消其它模块的握姿监听。
  private static holdingCallback = (status: motion.HoldingHandStatus): void => {
    if (HoldingHandService.supported !== true || HoldingHandService.enabled !== true ||
      HoldingHandService.listeners.size === 0 ||
      !HoldingHandService.foreground) {
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

  /** 设置页确认实际握姿能力；已有订阅结果可复用，开关关闭时也能检测是否应显示入口。 */
  static checkSupport(): boolean {
    if (!HoldingHandService.hasMotionCapability()) {
      return false;
    }
    if (HoldingHandService.supported !== null) {
      return HoldingHandService.supported;
    }
    try {
      // 共用回调与订阅标记；检测不改变用户偏好，也不会创建额外的长期监听。
      motion.on('holdingHandChanged', HoldingHandService.holdingCallback);
      HoldingHandService.subscribed = true;
      HoldingHandService.supported = true;
      if (HoldingHandService.listeners.size === 0 || HoldingHandService.enabled !== true ||
        !HoldingHandService.foreground) {
        HoldingHandService.unsubscribeMotion();
      }
      return true;
    } catch (err) {
      HoldingHandService.handleSubscriptionFailure(err as BusinessError);
      return false;
    }
  }

  /** 系统能力检查只是前置门禁；具体握姿事件仍以订阅结果为准。 */
  private static hasMotionCapability(): boolean {
    try {
      if (canIUse('SystemCapability.MultimodalAwareness.Motion')) {
        return HoldingHandService.supported !== false;
      }
      HoldingHandService.supported = false;
    } catch (err) {
      HoldingHandService.logFailure('检查握姿系统能力失败', err as BusinessError);
    }
    return false;
  }

  /** 首次读取后复用内存偏好；新安装和升级未配置开关时默认开启。 */
  static async isEnabled(): Promise<boolean> {
    if (HoldingHandService.enabled !== null) {
      return HoldingHandService.enabled;
    }
    // Context 尚未注入时不缓存默认值，让后续页面仍能读取已保存偏好。
    if (AppContextStore.getInstance().getContext() === null) {
      return true;
    }
    if (HoldingHandService.loading === null) {
      HoldingHandService.loading = PreferencesUtil.getString(null,
        PreferencesUtil.KEY_HOLDING_HAND_ENABLED, 'true').then((value: string): boolean => {
        HoldingHandService.enabled = value !== 'false';
        if (!HoldingHandService.enabled) {
          HoldingHandService.useDefaultSide();
        }
        return HoldingHandService.enabled;
      });
    }
    return HoldingHandService.loading;
  }

  /** 写盘成功才应用开关；关闭后拦截迟到回调并通知全部页面恢复右侧。 */
  static async setEnabled(enabled: boolean): Promise<boolean> {
    // 不支持或暂时无法确认能力时，不允许写入新的开启状态；已有偏好保持不变。
    if (enabled && !HoldingHandService.checkSupport()) {
      return false;
    }
    await HoldingHandService.isEnabled();
    const saved: boolean = await PreferencesUtil.putString(null,
      PreferencesUtil.KEY_HOLDING_HAND_ENABLED, enabled ? 'true' : 'false');
    if (!saved) {
      return false;
    }
    HoldingHandService.enabled = enabled;
    if (enabled) {
      HoldingHandService.subscribeMotion();
    } else {
      HoldingHandService.unsubscribeMotion();
      HoldingHandService.useDefaultSide();
    }
    return true;
  }

  /** 页面可见时注册；默认 owner 保留原通知页接口，同页重复启动只替换自身回调。 */
  static start(listener: (left: boolean) => void, owner: string = 'notify'): void {
    if (!HoldingHandService.hasMotionCapability()) {
      HoldingHandService.stop(owner);
      listener(false);
      return;
    }
    HoldingHandService.listeners.set(owner, listener);
    listener(HoldingHandService.enabled === true && HoldingHandService.left);
    // 异步读盘完成后再次经过消费者与前后台门禁，离页不会补订阅。
    HoldingHandService.isEnabled().then(() => HoldingHandService.subscribeMotion());
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
    if (HoldingHandService.enabled !== true || HoldingHandService.listeners.size === 0 ||
      !HoldingHandService.foreground || HoldingHandService.subscribed) {
      return;
    }
    if (!HoldingHandService.hasMotionCapability()) {
      HoldingHandService.useDefaultSide();
      return;
    }
    try {
      motion.on('holdingHandChanged', HoldingHandService.holdingCallback);
      HoldingHandService.subscribed = true;
      HoldingHandService.supported = true;
    } catch (err) {
      HoldingHandService.handleSubscriptionFailure(err as BusinessError);
    }
  }

  /** 801 是设备不支持，权限与临时服务错误不能永久判定为硬件不支持。 */
  private static handleSubscriptionFailure(error: BusinessError): void {
    if (error.code === 801) {
      HoldingHandService.supported = false;
    }
    HoldingHandService.logFailure('设备握姿能力不可用', error);
    HoldingHandService.useDefaultSide();
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
