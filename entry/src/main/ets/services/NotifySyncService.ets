import { hilog } from '@kit.PerformanceAnalysisKit';
import { DOMAIN, KEY_NOTIFY_SYNC_FEEDBACK, KEY_NOTIFY_SYNC_PROGRESS, KEY_NOTIFY_SYNC_REVISION } from '../common/Constant';
import { NotifyMessage } from '../model/NotifyMessage';
import { ServerEntry } from '../model/ServerEntry';
import { notifySourceKey } from '../utils/NotifyIdentity';
import { AutoCopyService, AutoCopySyncRound } from './AutoCopyService';
import { DecryptedNotificationService } from './DecryptedNotificationService';
import { EncryptedNotificationResendService } from './EncryptedNotificationResendService';
import { MessageCacheStore } from './MessageCacheStore';
import { MessageListResult, NotifyMessageService } from './NotifyMessageService';
import { ServerManager } from './ServerManager';

const TAG: string = 'NotifySync';
const PAGE_SIZE: number = 100;
const SERVER_CONCURRENCY: number = 2;
const DELETE_CONCURRENCY: number = 6;
const NOTIFY_POLL_MS: number = 3000;
const OTHER_POLL_MS: number = 15000;

/** 同步由 Ability 生命周期持有；页面离开、Tab 切换和组件销毁均不取消已启动的前台同步。 */
export class NotifySyncService {
  private static instance: NotifySyncService | null = null;
  private foreground: boolean = false;
  private running: Promise<void> | null = null;
  private queued: boolean = false;
  private pollTimer: number = -1;
  private displayTimer: number = -1;
  private feedbackTimer: number = -1;
  private tabIndex: number = 0;
  private epoch: number = 0;
  private processed: number = 0;
  private errors: Map<string, string> = new Map<string, string>();
  private serverSignature: string = '';
  private serverChangeListener: ((list: ServerEntry[], currentId: string) => void) | null = null;

  static getInstance(): NotifySyncService {
    if (!NotifySyncService.instance) {
      NotifySyncService.instance = new NotifySyncService();
    }
    return NotifySyncService.instance;
  }

  /** 应用进入前台时立即续拉；重复调用不会启动并行轮次。 */
  startForeground(): void {
    if (!this.serverChangeListener) {
      this.serverChangeListener = (list: ServerEntry[], _currentId: string): void => {
        const signature: string = list.map((server: ServerEntry) =>
          `${server.id}\u0000${server.baseURL}\u0000${server.deviceKey}`).join('\u0001');
        if (signature !== this.serverSignature) {
          this.serverSignature = signature;
          this.requestSync();
        }
      };
      ServerManager.getInstance().addChangeListener(this.serverChangeListener);
    }
    if (!this.foreground) {
      this.foreground = true;
      this.epoch++;
    }
    this.requestSync();
  }

  /** 后台只停止后续分页和定时轮询；当前页完成本地安全写入后自然结束。 */
  pause(): void {
    this.foreground = false;
    this.epoch++;
    this.clearPollTimer();
    this.clearDisplayTimer();
    if (this.feedbackTimer >= 0) {
      clearTimeout(this.feedbackTimer);
      this.feedbackTimer = -1;
    }
    AppStorage.setOrCreate(KEY_NOTIFY_SYNC_PROGRESS, '');
    AppStorage.setOrCreate(KEY_NOTIFY_SYNC_FEEDBACK, '');
  }

  /** Tab 只影响下一次轮询间隔，不影响正在同步的批次。 */
  setTabIndex(index: number): void {
    this.tabIndex = index;
    if (this.foreground && !this.running) {
      this.schedulePoll();
    }
  }

  /** UI 手动刷新和 Ability 前台恢复共用同一入口，飞行中合并为一轮补拉。 */
  requestSync(): Promise<void> {
    if (!this.foreground) {
      this.queued = true;
      return Promise.resolve();
    }
    this.clearPollTimer();
    if (this.running) {
      this.queued = true;
      return this.running;
    }
    this.running = this.runRound();
    return this.running;
  }

  /** 详情定位时确保候选服务已完成新一轮同步；仍经统一队列避免同一服务并行迁移。 */
  async syncServerNow(server: ServerEntry): Promise<void> {
    if (!server.deviceKey) {
      return;
    }
    if (this.running) {
      await this.running;
    }
    if (!this.foreground) {
      return;
    }
    await this.requestSync();
  }

  /** 给通知页读取各服务的最后同步错误；失败状态不因切换页面而丢失。 */
  getErrors(): Map<string, string> {
    return new Map<string, string>(this.errors);
  }

  private clearPollTimer(): void {
    if (this.pollTimer >= 0) {
      clearTimeout(this.pollTimer);
      this.pollTimer = -1;
    }
  }

  private clearDisplayTimer(): void {
    if (this.displayTimer >= 0) {
      clearTimeout(this.displayTimer);
      this.displayTimer = -1;
    }
  }

  private schedulePoll(): void {
    this.clearPollTimer();
    if (!this.foreground || this.running) {
      return;
    }
    this.pollTimer = setTimeout(() => {
      this.pollTimer = -1;
      this.requestSync();
    }, this.tabIndex === 0 ? NOTIFY_POLL_MS : OTHER_POLL_MS);
  }

  private publishRevision(): void {
    AppStorage.setOrCreate(KEY_NOTIFY_SYNC_REVISION,
      (AppStorage.get<number>(KEY_NOTIFY_SYNC_REVISION) ?? 0) + 1);
  }

  private recordPage(count: number): void {
    this.processed += count;
    this.clearDisplayTimer();
    if (this.foreground) {
      AppStorage.setOrCreate(KEY_NOTIFY_SYNC_PROGRESS, `正在同步 · 已处理 ${this.processed} 条`);
    }
    this.publishRevision();
  }

  private async runRound(): Promise<void> {
    const epoch: number = this.epoch;
    this.processed = 0;
    this.errors = new Map<string, string>();
    AppStorage.setOrCreate(KEY_NOTIFY_SYNC_FEEDBACK, '');
    this.clearDisplayTimer();
    this.displayTimer = setTimeout(() => {
      this.displayTimer = -1;
      if (this.foreground && epoch === this.epoch) {
        AppStorage.setOrCreate(KEY_NOTIFY_SYNC_PROGRESS, '正在同步…');
      }
    }, 600);
    let round: AutoCopySyncRound | null = null;
    try {
      await ServerManager.getInstance().ensureLoaded();
      const expired: number = await MessageCacheStore.purgeExpired();
      if (expired > 0) {
        this.publishRevision();
      }
      const servers: ServerEntry[] = ServerManager.getInstance().getList().filter(
        (server: ServerEntry) => server.deviceKey.length > 0);
      if (servers.length === 0 || !this.foreground || epoch !== this.epoch) {
        return;
      }
      round = await AutoCopyService.beginSyncRound();
      let next: number = 0;
      const workers: Promise<void>[] = [];
      for (let worker: number = 0; worker < Math.min(SERVER_CONCURRENCY, servers.length); worker++) {
        workers.push((async (): Promise<void> => {
          while (this.foreground && epoch === this.epoch && next < servers.length) {
            const server: ServerEntry = servers[next++];
            try {
              await this.syncServer(server, epoch, round!);
            } catch (err) {
              this.errors.set(server.id, '同步异常；未完成的通知会在下次进入前台时重试');
              hilog.warn(DOMAIN, TAG, '服务器同步异常：%{public}s',
                err instanceof Error ? err.message : String(err));
            }
          }
        })());
      }
      await Promise.all(workers);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, '同步轮次异常：%{public}s', err instanceof Error ? err.message : String(err));
    } finally {
      this.clearDisplayTimer();
      AppStorage.setOrCreate(KEY_NOTIFY_SYNC_PROGRESS, '');
      // 首次历史播种只有完整扫完且无错误才算结束；空服务或后台中断不能提前开启自动复制。
      if (round && (!round.firstSync || (this.foreground && epoch === this.epoch && this.errors.size === 0))) {
        try {
          await AutoCopyService.finishSyncRound(round, null);
        } catch (err) {
          hilog.warn(DOMAIN, TAG, '自动复制收尾失败：%{public}s',
            err instanceof Error ? err.message : String(err));
        }
      }
      this.publishRevision();
      if (this.feedbackTimer >= 0) {
        clearTimeout(this.feedbackTimer);
      }
      if (this.foreground && epoch === this.epoch && this.processed > 0) {
        const feedback: string = this.errors.size > 0
          ? `已处理 ${this.processed} 条，部分待重试` : `本轮已处理 ${this.processed} 条`;
        AppStorage.setOrCreate(KEY_NOTIFY_SYNC_FEEDBACK, feedback);
        this.feedbackTimer = setTimeout(() => {
          this.feedbackTimer = -1;
          AppStorage.setOrCreate(KEY_NOTIFY_SYNC_FEEDBACK, '');
        }, 2000);
      }
      this.running = null;
      if (this.foreground) {
        if (this.queued) {
          this.queued = false;
          this.requestSync();
        } else {
          this.schedulePoll();
        }
      }
    }
  }

  private async syncServer(server: ServerEntry, epoch: number, round: AutoCopySyncRound): Promise<void> {
    const svc: NotifyMessageService = NotifyMessageService.getInstance();
    const deviceKey: string = server.deviceKey;
    let after: number = 0;
    let sourceKey: string = notifySourceKey(server.instanceId, server.id, deviceKey);
    let meta = await MessageCacheStore.getMeta(sourceKey);
    let maxId: number = meta.maxId;
    let delCursor: number = meta.delCursor;
    let instanceRestarted: boolean = false;
    let pendingEncrypted: boolean = false;
    let remoteDeleteFailed: boolean = false;
    let delHasMore: boolean = false;

    while (this.foreground && epoch === this.epoch) {
      const result: MessageListResult = await svc.getMessages(null, 0, PAGE_SIZE, after, delCursor, server, true);
      if (!result.ok) {
        this.errors.set(server.id, result.errorMsg);
        return;
      }
      const responseSource: string = notifySourceKey(result.instanceId, server.id, deviceKey);
      if (responseSource !== sourceKey) {
        if (instanceRestarted) {
          this.errors.set(server.id, '服务器历史实例在同步中变化');
          return;
        }
        instanceRestarted = true;
        sourceKey = responseSource;
        after = 0;
        meta = await MessageCacheStore.getMeta(sourceKey);
        maxId = meta.maxId;
        delCursor = meta.delCursor;
        continue;
      }
      if (server.instanceId !== result.instanceId || server.historyKeys.indexOf(sourceKey) < 0) {
        if (!(await ServerManager.getInstance().rememberHistory(server.id, result.instanceId, sourceKey))) {
          this.errors.set(server.id, '无法保存服务器历史身份');
          return;
        }
      }
      if (await this.applyDeletionExtraIds(sourceKey, result)) {
        this.publishRevision();
      }
      if (result.hasDeletions) {
        delCursor = result.delCursor;
      }
      let nextAfter: number = after;
      if (result.messages.length > 0) {
        if (!(await MessageCacheStore.upsertMessages(sourceKey, result.messages))) {
          this.errors.set(server.id, '本地保存失败；远端通知已保留，稍后可重试');
          return;
        }
        // 每页处理前读取最新偏好：设置页开启后，后续同步页立即按新规则发布。
        const resendArchived: boolean = await EncryptedNotificationResendService.isEnabled();
        for (let i: number = 0; i < result.messages.length; i++) {
          const message: NotifyMessage = result.messages[i];
          message.deviceKey = sourceKey;
          if (message.needsDecryptedNotification(Date.now(), resendArchived) &&
            !(await DecryptedNotificationService.publish(message, server, resendArchived))) {
            message.migrationReady = false;
          }
          if (message.encrypted && !message.migrationReady) {
            pendingEncrypted = true;
          }
          maxId = Math.max(maxId, message.id);
          nextAfter = Math.max(nextAfter, message.id);
        }
        AutoCopyService.collectPage(round, result.messages);
        this.recordPage(result.messages.length);
        if (await this.deleteMigratedRemoteMessages(server, result.messages) > 0) {
          remoteDeleteFailed = true;
        }
      }
      if (result.hasMore && nextAfter <= after) {
        this.errors.set(server.id, '服务器分页游标未推进，稍后可重试');
        return;
      }
      if (!(await MessageCacheStore.saveMeta(sourceKey, maxId, delCursor, 0, true))) {
        this.errors.set(server.id, '同步进度保存失败；远端未完成清理的通知会重试');
        return;
      }
      if (!result.hasMore) {
        delHasMore = result.delHasMore;
        break;
      }
      after = nextAfter;
    }

    while (this.foreground && epoch === this.epoch && delHasMore) {
      const result: MessageListResult = await svc.getMessages(null, 0, 0, 0, delCursor, server, false);
      if (!result.ok || notifySourceKey(result.instanceId, server.id, deviceKey) !== sourceKey) {
        this.errors.set(server.id, result.ok ? '服务器历史实例在同步中变化' : result.errorMsg);
        return;
      }
      if (await this.applyDeletionExtraIds(sourceKey, result)) {
        this.publishRevision();
      }
      if (result.hasDeletions) {
        delCursor = result.delCursor;
      }
      if (!(await MessageCacheStore.saveMeta(sourceKey, maxId, delCursor, 0, true))) {
        this.errors.set(server.id, '删除同步进度保存失败；稍后会重试');
        return;
      }
      delHasMore = result.delHasMore;
    }
    if (!this.foreground || epoch !== this.epoch) {
      return;
    }
    if (pendingEncrypted) {
      this.errors.set(server.id, '有加密通知尚未解密或发布；请检查加密 Key 与通知权限，远端密文已保留');
    } else if (remoteDeleteFailed) {
      this.errors.set(server.id, '通知已保存到本地，但部分远端副本清理失败；稍后会重试');
    }
  }

  private async applyDeletionExtraIds(sourceKey: string, result: MessageListResult): Promise<boolean> {
    if (result.reset) {
      hilog.warn(DOMAIN, TAG, '删除流水游标过旧被压缩：%{public}s', sourceKey);
    }
    if (result.deletionExtraIds.length === 0) {
      return false;
    }
    return (await MessageCacheStore.deleteByExtraIds(sourceKey, result.deletionExtraIds)).length > 0;
  }

  private async deleteMigratedRemoteMessages(server: ServerEntry, messages: NotifyMessage[]): Promise<number> {
    const ready: NotifyMessage[] = messages.filter((message: NotifyMessage) => message.migrationReady);
    let failed: number = 0;
    for (let offset: number = 0; offset < ready.length; offset += DELETE_CONCURRENCY) {
      const tasks: Promise<string>[] = [];
      for (let i: number = offset; i < Math.min(offset + DELETE_CONCURRENCY, ready.length); i++) {
        tasks.push(NotifyMessageService.getInstance().deleteMessage(ready[i].id, null, server));
      }
      const results: string[] = await Promise.all(tasks);
      for (let i: number = 0; i < results.length; i++) {
        if (results[i].length > 0) {
          failed++;
        }
      }
    }
    return failed;
  }
}
