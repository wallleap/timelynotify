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
const RETRY_DELAYS_MS: number[] = [15000, 30000, 60000, 120000, 300000];

interface ServerRetryState {
  failures: number;
  nextRetryAt: number;
  version: number;
  completedVersion: number;
}

/** 失败服务器独立退避；达到上限后保持五分钟低频自动重试。 */
export function retryDelayMs(failures: number): number {
  return RETRY_DELAYS_MS[Math.min(Math.max(failures - 1, 0), RETRY_DELAYS_MS.length - 1)];
}

/** 同步由 Ability 生命周期持有；页面离开、Tab 切换和组件销毁均不取消已启动的前台同步。 */
export class NotifySyncService {
  private static instance: NotifySyncService | null = null;
  private foreground: boolean = false;
  private running: Promise<void> | null = null;
  private queued: boolean = false;
  private manualDeletions: number = 0;
  private pollTimer: number = -1;
  private feedbackTimer: number = -1;
  private tabIndex: number = 0;
  private epoch: number = 0;
  private processed: number = 0;
  private errors: Map<string, string> = new Map<string, string>();
  private retryStates: Map<string, ServerRetryState> = new Map<string, ServerRetryState>();
  private serverFingerprints: Map<string, string> = new Map<string, string>();
  private forceAllQueued: boolean = false;
  private serverChangeListener: ((list: ServerEntry[], currentId: string) => void) | null = null;

  private stateFor(id: string): ServerRetryState {
    let state: ServerRetryState | undefined = this.retryStates.get(id);
    if (!state) {
      state = { failures: 0, nextRetryAt: 0, version: 0, completedVersion: -1 };
      this.retryStates.set(id, state);
    }
    return state;
  }

  private serverFingerprint(server: ServerEntry): string {
    return JSON.stringify([server.baseURL, server.deviceKey, server.clientToken]);
  }

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
        const present: Set<string> = new Set<string>();
        for (let i: number = 0; i < list.length; i++) {
          const server: ServerEntry = list[i];
          present.add(server.id);
          const fingerprint: string = this.serverFingerprint(server);
          if (this.serverFingerprints.get(server.id) !== fingerprint) {
            this.serverFingerprints.set(server.id, fingerprint);
            this.retryServer(server.id);
          }
        }
        let errorsChanged: boolean = false;
        this.serverFingerprints.forEach((_fingerprint: string, id: string) => {
          if (!present.has(id)) {
            this.retryStates.delete(id);
            this.serverFingerprints.delete(id);
            errorsChanged = this.errors.delete(id) || errorsChanged;
          }
        });
        if (errorsChanged) {
          this.publishRevision();
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
    const nextNormal: number = Date.now() + (index === 0 ? NOTIFY_POLL_MS : OTHER_POLL_MS);
    this.retryStates.forEach((state: ServerRetryState) => {
      if (state.failures === 0) {
        state.nextRetryAt = Math.min(state.nextRetryAt, nextNormal);
      }
    });
    if (this.foreground && !this.running) {
      this.schedulePoll();
    }
  }

  /** UI 手动刷新和 Ability 前台恢复共用同一入口，飞行中合并为一轮补拉。 */
  requestSync(forceAll: boolean = false): Promise<void> {
    if (forceAll) {
      this.forceAllQueued = true;
    }
    if (!this.foreground || this.manualDeletions > 0) {
      this.queued = true;
      return Promise.resolve();
    }
    this.clearPollTimer();
    if (this.running) {
      this.queued = true;
      const inFlight: Promise<void> = this.running;
      // 手动下拉刷新必须等排队的强制轮次完成，不能只等当前正在飞行的旧轮次。
      return forceAll ? inFlight.then((): Promise<void> => this.running ?? Promise.resolve()) : inFlight;
    }
    const runForced: boolean = this.forceAllQueued;
    this.forceAllQueued = false;
    this.queued = false;
    this.running = this.runRound(runForced);
    return this.running;
  }

  /** 地址、Token、Key 或加密设置变化后，只让目标服务器立即验证；旧请求结果不再更新其错误状态。 */
  retryServer(serverId: string): Promise<void> {
    const state: ServerRetryState = this.stateFor(serverId);
    state.version++;
    state.nextRetryAt = 0;
    return this.requestSync();
  }

  /** 手动删除前等当前同步页安全完成，避免远端删除后被飞行中的同步结果重新写回本地。 */
  async beginManualDeletion(): Promise<void> {
    this.manualDeletions++;
    this.clearPollTimer();
    if (this.running) {
      await this.running;
    }
  }

  endManualDeletion(): void {
    if (this.manualDeletions > 0) {
      this.manualDeletions--;
    }
    if (this.manualDeletions === 0 && this.foreground) {
      this.requestSync();
    }
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
    const attempt: Promise<void> = this.retryServer(server.id);
    const version: number = this.stateFor(server.id).version;
    await attempt;
    if (this.foreground && this.stateFor(server.id).completedVersion < version) {
      await this.requestSync();
    }
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

  private schedulePoll(): void {
    this.clearPollTimer();
    if (!this.foreground || this.running || this.manualDeletions > 0) {
      return;
    }
    const now: number = Date.now();
    let delay: number = Number.MAX_SAFE_INTEGER;
    const servers: ServerEntry[] = ServerManager.getInstance().getList();
    for (let i: number = 0; i < servers.length; i++) {
      if (!servers[i].deviceKey) {
        continue;
      }
      const nextRetryAt: number = this.stateFor(servers[i].id).nextRetryAt;
      delay = Math.min(delay, Math.max(0, nextRetryAt - now));
    }
    if (delay === Number.MAX_SAFE_INTEGER) {
      return;
    }
    this.pollTimer = setTimeout(() => {
      this.pollTimer = -1;
      this.requestSync();
    }, delay);
  }

  private publishRevision(): void {
    AppStorage.setOrCreate(KEY_NOTIFY_SYNC_REVISION,
      (AppStorage.get<number>(KEY_NOTIFY_SYNC_REVISION) ?? 0) + 1);
  }

  private recordPage(count: number): void {
    this.processed += count;
    if (this.foreground) {
      AppStorage.setOrCreate(KEY_NOTIFY_SYNC_PROGRESS, `正在同步 · 已处理 ${this.processed} 条`);
    }
    this.publishRevision();
  }

  private recordServerResult(serverId: string, error: string): void {
    const state: ServerRetryState = this.stateFor(serverId);
    const previous: string | undefined = this.errors.get(serverId);
    if (error.length > 0) {
      state.failures++;
      state.nextRetryAt = Date.now() + retryDelayMs(state.failures);
      this.errors.set(serverId, error);
    } else {
      state.failures = 0;
      state.nextRetryAt = Date.now() + (this.tabIndex === 0 ? NOTIFY_POLL_MS : OTHER_POLL_MS);
      this.errors.delete(serverId);
    }
    if ((previous ?? '') !== error) {
      this.publishRevision();
    }
  }

  private attemptCurrent(serverId: string, version: number, epoch: number): boolean {
    return this.foreground && epoch === this.epoch && this.manualDeletions === 0 &&
      this.stateFor(serverId).version === version;
  }

  private async runRound(forceAll: boolean): Promise<void> {
    const epoch: number = this.epoch;
    this.processed = 0;
    AppStorage.setOrCreate(KEY_NOTIFY_SYNC_FEEDBACK, '');
    let round: AutoCopySyncRound | null = null;
    try {
      await ServerManager.getInstance().ensureLoaded();
      const configured: ServerEntry[] = ServerManager.getInstance().getList();
      for (let i: number = 0; i < configured.length; i++) {
        if (!this.serverFingerprints.has(configured[i].id)) {
          this.serverFingerprints.set(configured[i].id, this.serverFingerprint(configured[i]));
        }
      }
      const expired: number = await MessageCacheStore.purgeExpired();
      if (expired > 0) {
        this.publishRevision();
      }
      const now: number = Date.now();
      const servers: ServerEntry[] = configured.filter(
        (server: ServerEntry) => server.deviceKey.length > 0 &&
          (forceAll || this.stateFor(server.id).nextRetryAt <= now));
      if (servers.length === 0 || !this.foreground || epoch !== this.epoch) {
        return;
      }
      round = await AutoCopyService.beginSyncRound();
      let next: number = 0;
      const workers: Promise<void>[] = [];
      for (let worker: number = 0; worker < Math.min(SERVER_CONCURRENCY, servers.length); worker++) {
        workers.push((async (): Promise<void> => {
          while (this.foreground && epoch === this.epoch && this.manualDeletions === 0 && next < servers.length) {
            const current: ServerEntry = servers[next++];
            const state: ServerRetryState = this.stateFor(current.id);
            const version: number = state.version;
            const server: ServerEntry = new ServerEntry(current.id, current.name, current.baseURL,
              current.isBuiltIn, current.deviceKey, current.clientToken);
            server.instanceId = current.instanceId;
            server.historyKeys = [...current.historyKeys];
            try {
              const error: string = await this.syncServer(server, epoch, round!, version);
              if (state.version !== version || !this.foreground || epoch !== this.epoch) {
                continue;
              }
              this.recordServerResult(server.id, error);
              state.completedVersion = version;
            } catch (err) {
              if (state.version === version) {
                this.recordServerResult(server.id, '同步异常；未完成的通知会在下次进入前台时重试');
                state.completedVersion = version;
              }
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

  private async syncServer(server: ServerEntry, epoch: number, round: AutoCopySyncRound,
    version: number): Promise<string> {
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

    while (this.attemptCurrent(server.id, version, epoch)) {
      const result: MessageListResult = await svc.getMessages(null, 0, PAGE_SIZE, after, delCursor, server, true);
      if (!this.attemptCurrent(server.id, version, epoch)) {
        return '';
      }
      if (!result.ok) {
        return result.errorMsg;
      }
      const responseSource: string = notifySourceKey(result.instanceId, server.id, deviceKey);
      if (responseSource !== sourceKey) {
        if (instanceRestarted) {
          return '服务器历史实例在同步中变化';
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
          return '无法保存服务器历史身份';
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
          return '本地保存失败；远端通知已保留，稍后可重试';
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
        if (!this.attemptCurrent(server.id, version, epoch)) {
          return '';
        }
        if (await this.deleteMigratedRemoteMessages(server, result.messages) > 0) {
          remoteDeleteFailed = true;
        }
      }
      if (result.hasMore && nextAfter <= after) {
        return '服务器分页游标未推进，稍后可重试';
      }
      if (!(await MessageCacheStore.saveMeta(sourceKey, maxId, delCursor, 0, true))) {
        return '同步进度保存失败；远端未完成清理的通知会重试';
      }
      if (!result.hasMore) {
        delHasMore = result.delHasMore;
        break;
      }
      after = nextAfter;
    }

    while (this.attemptCurrent(server.id, version, epoch) && delHasMore) {
      const result: MessageListResult = await svc.getMessages(null, 0, 0, 0, delCursor, server, false);
      if (!this.attemptCurrent(server.id, version, epoch)) {
        return '';
      }
      if (!result.ok || notifySourceKey(result.instanceId, server.id, deviceKey) !== sourceKey) {
        return result.ok ? '服务器历史实例在同步中变化' : result.errorMsg;
      }
      if (await this.applyDeletionExtraIds(sourceKey, result)) {
        this.publishRevision();
      }
      if (result.hasDeletions) {
        delCursor = result.delCursor;
      }
      if (!(await MessageCacheStore.saveMeta(sourceKey, maxId, delCursor, 0, true))) {
        return '删除同步进度保存失败；稍后会重试';
      }
      delHasMore = result.delHasMore;
    }
    if (!this.attemptCurrent(server.id, version, epoch)) {
      return '';
    }
    if (pendingEncrypted) {
      return '有加密通知尚未解密或发布；请检查加密 Key 与通知权限，远端密文已保留';
    } else if (remoteDeleteFailed) {
      return '通知已保存到本地，但部分远端副本清理失败；稍后会重试';
    }
    return '';
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
