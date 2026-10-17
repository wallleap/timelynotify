import { Want, WantAgent, wantAgent } from '@kit.AbilityKit';
import { notificationManager } from '@kit.NotificationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppContextStore } from '../common/AppContextStore';
import { DOMAIN } from '../common/Constant';
import { NotifyMessage } from '../model/NotifyMessage';
import { ServerEntry } from '../model/ServerEntry';
import { notifyIdentity } from '../utils/NotifyIdentity';

const TAG: string = 'DecryptNotify';
const MAX_NOTIFICATION_ID: number = 2147483647;

/**
 * 为端到端加密消息发布解密后的本地通知；归档消息由用户偏好决定是否补发。
 * 使用稳定的 id + label，远程删除失败而重试同步时只更新原通知，不重复堆叠。
 */
export class DecryptedNotificationService {
  static async publish(message: NotifyMessage, server: ServerEntry, resendArchived: boolean = false): Promise<boolean> {
    if (!message.needsDecryptedNotification(Date.now(), resendArchived)) {
      return true;
    }

    const title: string = message.title.trim().length > 0 ? message.title.trim() : '[订阅] 通知';
    const body: string = DecryptedNotificationService.resolveBody(message);
    const identity: string = `decrypted-${notifyIdentity(message)}`;
    const normalizedId: number = DecryptedNotificationService.normalizeId(message.id);
    try {
      const context = AppContextStore.getInstance().getContext();
      if (!context) {
        throw new Error('应用 Context 尚未就绪');
      }
      // 非归档通知不落本地历史，只回通知首页；归档通知复用远程推送的精确详情路由。
      const canOpenDetail: boolean = message.archive && server.instanceId.length > 0 && message.id > 0;
      const target: Want = canOpenDetail ? {
        bundleName: context.applicationInfo.name,
        abilityName: 'EntryAbility',
        uri: `timelynotify://decrypted/${encodeURIComponent(identity)}`,
        parameters: {
          tn_action: 'alert',
          tn_instance_id: server.instanceId,
          tn_message_id: String(message.id),
        },
      } : {
        bundleName: context.applicationInfo.name,
        abilityName: 'EntryAbility',
        uri: `timelynotify://decrypted/${encodeURIComponent(identity)}`,
        parameters: { tn_action: 'none' },
      };
      // requestCode 与 uri 均按消息身份区分，避免多条通知复用同一个点击目标。
      const clickAgent: WantAgent = await wantAgent.getWantAgent({
        wants: [target],
        actionType: wantAgent.OperationType.START_ABILITY,
        requestCode: DecryptedNotificationService.requestCodeFor(identity),
        actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG],
      });
      const request: notificationManager.NotificationRequest = {
        id: normalizedId,
        label: identity,
        appMessageId: identity,
        notificationSlotType: notificationManager.SlotType.SERVICE_INFORMATION,
        isAlertOnce: true,
        wantAgent: clickAgent,
        content: {
          notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: {
            title: title,
            text: body,
            additionalText: message.subtitle,
          },
        },
      };
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

  /** 使用完整消息身份生成稳定点击请求码，避免不同服务器的相同消息 ID 共用点击参数。 */
  private static requestCodeFor(identity: string): number {
    let code: number = 0;
    for (let i: number = 0; i < identity.length; i++) {
      code = (code * 31 + identity.charCodeAt(i)) % MAX_NOTIFICATION_ID;
    }
    return code > 0 ? code : 1;
  }
}
