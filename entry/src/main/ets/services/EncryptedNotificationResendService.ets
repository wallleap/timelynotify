import { PreferencesUtil } from '../utils/PreferencesUtil';

/** 管理加密通知重发偏好；默认关闭，并在同步期间提供最新的内存值。 */
export class EncryptedNotificationResendService {
  private static enabled: boolean | null = null;
  private static loading: Promise<boolean> | null = null;

  /** 首次从 Preferences 加载，此后复用同一结果，避免批量同步时反复读盘。 */
  static async isEnabled(): Promise<boolean> {
    if (EncryptedNotificationResendService.enabled !== null) {
      return EncryptedNotificationResendService.enabled;
    }
    if (!EncryptedNotificationResendService.loading) {
      EncryptedNotificationResendService.loading = PreferencesUtil.getString(null,
        PreferencesUtil.KEY_ENCRYPTED_NOTIFICATION_RESEND, 'false').then((value: string): boolean => {
        EncryptedNotificationResendService.enabled = value === 'true';
        return EncryptedNotificationResendService.enabled;
      });
    }
    return EncryptedNotificationResendService.loading;
  }

  /** 只有持久化成功才更新运行时开关，避免界面与同步行为不一致。 */
  static async setEnabled(enabled: boolean): Promise<boolean> {
    await EncryptedNotificationResendService.isEnabled();
    const saved: boolean = await PreferencesUtil.putString(null,
      PreferencesUtil.KEY_ENCRYPTED_NOTIFICATION_RESEND, enabled ? 'true' : 'false');
    if (saved) {
      EncryptedNotificationResendService.enabled = enabled;
    }
    return saved;
  }
}
