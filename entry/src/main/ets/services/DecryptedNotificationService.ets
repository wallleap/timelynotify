import { notificationManager } from '@kit.NotificationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { DOMAIN } from '../common/Constant';
import { NotifyMessage } from '../model/NotifyMessage';
import { ServerEntry } from '../model/ServerEntry';

const TAG: string = 'DecryptNotify';
const MAX_NOTIFICATION_ID: number = 2147483647;

/**
 * 为不归档的端到端加密消息发布解密后的本地通知。
 * 使用稳定的 id + label，远程删除失败而重试同步时只更新原通知，不重复堆叠。
 */
export class DecryptedNotificationService {
  static async publish(message: NotifyMessage, server: ServerEntry): Promise<boolean> {
    if (!message.needsDecryptedNotification()) {
      return true;
    }

    const title: string = message.title.trim().length > 0 ? message.title.trim() : '[订阅] 通知';
    const body: string = DecryptedNotificationService.resolveBody(message);
    const identity: string = `decrypted-${server.id}-${message.id}`;
    const normalizedId: number = DecryptedNotificationService.normalizeId(message.id);
    const request: notificationManager.NotificationRequest = {
      id: normalizedId,
      label: identity,
      appMessageId: identity,
      notificationSlotType: notificationManager.SlotType.SERVICE_INFORMATION,
      isAlertOnce: true,
      content: {
        notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
        normal: {
          title: title,
          text: body,
          additionalText: message.subtitle,
        },
      },
    };

    try {
      await notificationManager.publish(request);
      hilog.info(DOMAIN, TAG, '解密后本地通知发布成功：server=%{public}s id=%{public}d',
        server.name, message.id);
      return true;
    } catch (err) {
      const reason: string = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, TAG, '解密后本地通知发布失败：server=%{public}s id=%{public}d err=%{public}s',
        server.name, message.id, reason);
      return false;
    }
  }

  private static resolveBody(message: NotifyMessage): string {
    if (message.inboxContent.length > 0) {
      return message.inboxContent.join('\n');
    }
    if (message.body.trim().length > 0) {
      return message.body.trim();
    }
    if (message.subtitle.trim().length > 0) {
      return message.subtitle.trim();
    }
    return '收到一条加密通知';
  }

  private static normalizeId(id: number): number {
    const normalized: number = Math.floor(Math.abs(id)) % MAX_NOTIFICATION_ID;
    return normalized > 0 ? normalized : 1;
  }
}
