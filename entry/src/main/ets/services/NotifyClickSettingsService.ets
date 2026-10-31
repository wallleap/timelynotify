import { PreferencesUtil } from '../utils/PreferencesUtil';

/** 系统通知点击跳转偏好；默认开启，普通推送与解密后本地通知共用。 */
export class NotifyClickSettingsService {
  // 未加载使用 null，避免冷启动先按默认值跳转而忽略已保存的关闭偏好。
  private static urlEnabled: boolean | null = null;
  private static loading: Promise<boolean> | null = null;

  /** 首次等待持久化值，后续读取同一内存状态，不影响详情内主动访问链接。 */
  static async isUrlEnabled(): Promise<boolean> {
    if (NotifyClickSettingsService.urlEnabled !== null) {
      return NotifyClickSettingsService.urlEnabled;
    }
    if (!NotifyClickSettingsService.loading) {
      NotifyClickSettingsService.loading = PreferencesUtil.getString(null,
        PreferencesUtil.KEY_NOTIFY_CLICK_OPEN_URL, 'true').then((value: string): boolean => {
        NotifyClickSettingsService.urlEnabled = value !== 'false';
        return NotifyClickSettingsService.urlEnabled;
      });
    }
    return NotifyClickSettingsService.loading;
  }

  /** 写盘成功才更新运行时值；先等初始读取，防止晚到的旧值覆盖新设置。 */
  static async setUrlEnabled(enabled: boolean): Promise<boolean> {
    await NotifyClickSettingsService.isUrlEnabled();
    const saved: boolean = await PreferencesUtil.putString(null,
      PreferencesUtil.KEY_NOTIFY_CLICK_OPEN_URL, enabled ? 'true' : 'false');
    if (saved) {
      NotifyClickSettingsService.urlEnabled = enabled;
    }
    return saved;
  }
}
