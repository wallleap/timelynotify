import { hilog } from '@kit.PerformanceAnalysisKit';
import { UIContext } from '@kit.ArkUI';
import { DOMAIN } from '../common/Constant';
import { PreferencesUtil } from '../utils/PreferencesUtil';
import { NotifyMessage } from '../model/NotifyMessage';
import { ClipboardService } from './ClipboardService';
import showToast from '../components/showToast';

const TAG: string = 'AutoCopySvc';

/** 自动复制候选选择结果：选中消息 + 本轮应标记为已处理的 id 列表。 */
export class AutoCopySelection {
  /** 选中的最新 autoCopy 消息；无候选时为 null。 */
  target: NotifyMessage | null = null;
  /** 应复制文本（target.copy 非空取 copy，否则回退 body）；无候选时为空串。 */
  text: string = '';
  /** 本轮应记为已处理的 identity 列表，含超窗口的 autoCopy 消息与所有候选。 */
  identitiesToMark: string[] = [];
}

/** 一轮同步的有界状态；不持有整轮通知列表。 */
export class AutoCopySyncRound {
  firstSync: boolean = false;
  latest: NotifyMessage | null = null;
  count: number = 0;
  changed: boolean = false;
  // 首次历史可能远超已处理标识上限；按来源记录最大旧 ID，避免删除重试误触发自动复制。
  firstSyncMaxIds: Map<string, number> = new Map<string, number>();
}

/**
 * 自动复制服务：客户端同步到 autoCopy=1 的新通知时，自动复制最新一条到剪贴板并 Toast 提示。
 *
 * 触发约束（满足全部才复制）：
 * 1. 非首次历史同步——首次打开 App 时积压的旧通知不触发，避免覆盖剪贴板；
 * 2. 通知产生时间在 5 分钟内——超过时效窗口视为过期验证码，不再自动复制；
 * 3. 本轮最新一条 autoCopy 消息——同一轮多条验证码只复制时间最新的一条，
 *    时间相同时按 id 降序固定排序，避免结果随机；
 * 4. 未处理过——已记录 id 的通知后续刷新不重复复制。
 *
 * 复制内容：message.copy 非空时复制 copy，否则回退复制 body。
 */
export class AutoCopyService {
  /** Preferences 键：首次历史同步是否已完成（'true'/'false'）。 */
  private static readonly KEY_FIRST_SYNC_DONE: string = 'autocopy_first_sync_done';
  /** Preferences 键：已处理通知 id 列表（JSON 数组，元素为 `${deviceKey}:${id}`）。 */
  private static readonly KEY_PROCESSED_IDS: string = 'autocopy_processed_ids';
  private static readonly KEY_FIRST_SYNC_MAX_IDS: string = 'autocopy_first_sync_max_ids';
  /** 通知产生后允许自动复制的时效窗口（毫秒）。 */
  private static readonly TIME_WINDOW_MS: number = 5 * 60 * 1000;
  /** 已处理 id 集合上限：超过则整体清空，避免无限增长；过期 id 受时效窗口保护不会被误复制。 */
  private static readonly PROCESSED_IDS_CAP: number = 1000;
  /** Toast 文案最大长度，超出截断显示省略号，避免长文本撑满屏幕。 */
  private static readonly TOAST_TEXT_CAP: number = 20;

  private static processedIds: Set<string> = new Set<string>();
  private static firstSyncMaxIds: Map<string, number> = new Map<string, number>();
  private static firstSyncDone: boolean = false;
  private static loaded: boolean = false;
  private static loadPromise: Promise<void> | null = null;

  /** 开始一轮同步，固定首次同步语义；跨服务器分页可共用同一轮状态。 */
  static async beginSyncRound(): Promise<AutoCopySyncRound> {
    await AutoCopyService.ensureLoaded();
    const round: AutoCopySyncRound = new AutoCopySyncRound();
    round.firstSync = !AutoCopyService.firstSyncDone;
    return round;
  }

  /** 逐页归并：仅保留最新候选；已处理标识按上限淘汰，不累积消息对象。 */
  static collectPage(round: AutoCopySyncRound, messages: NotifyMessage[]): void {
    const now: number = Date.now();
    round.count += messages.length;
    for (let i = 0; i < messages.length; i++) {
      const message: NotifyMessage = messages[i];
      if (round.firstSync && message.id > (round.firstSyncMaxIds.get(message.deviceKey) ?? 0)) {
        round.firstSyncMaxIds.set(message.deviceKey, message.id);
      }
      if (!message.autoCopy) {
        continue;
      }
      if (!round.firstSync && message.id <= (AutoCopyService.firstSyncMaxIds.get(message.deviceKey) ?? 0)) {
        continue;
      }
      const identity: string = AutoCopyService.identity(message);
      if (AutoCopyService.processedIds.has(identity)) {
        continue;
      }
      const age: number = now - message.timestamp;
      if (!round.firstSync && age >= 0 && age <= AutoCopyService.TIME_WINDOW_MS &&
        (!round.latest || message.timestamp > round.latest.timestamp ||
          (message.timestamp === round.latest.timestamp && message.id > round.latest.id))) {
        round.latest = message;
      }
      AutoCopyService.processedIds.add(identity);
      round.changed = true;
      AutoCopyService.trimIfNeeded();
    }
  }

  /** 完成一轮：首次历史同步只标记，不写剪贴板；后续只复制最新一条。 */
  static async finishSyncRound(round: AutoCopySyncRound, uiContext: UIContext | null): Promise<void> {
    if (round.changed) {
      await AutoCopyService.persist();
    }
    if (round.firstSync) {
      round.firstSyncMaxIds.forEach((id: number, source: string) => {
        const old: number = AutoCopyService.firstSyncMaxIds.get(source) ?? 0;
        if (id > old) {
          AutoCopyService.firstSyncMaxIds.set(source, id);
        }
      });
      const watermark: Record<string, number> = {};
      AutoCopyService.firstSyncMaxIds.forEach((id: number, source: string) => {
        watermark[source] = id;
      });
      await PreferencesUtil.putString(null, AutoCopyService.KEY_FIRST_SYNC_MAX_IDS, JSON.stringify(watermark));
      AutoCopyService.firstSyncDone = true;
      await PreferencesUtil.putString(null, AutoCopyService.KEY_FIRST_SYNC_DONE, 'true');
      hilog.info(DOMAIN, TAG, '首次历史同步完成，处理 %{public}d 条，不触发自动复制', round.count);
      return;
    }
    if (!round.latest) {
      return;
    }
    const selected: NotifyMessage = round.latest;
    const selectedText: string = selected.copy.length > 0 ? selected.copy : selected.body;
    if (selectedText.length === 0) {
      return;
    }
    const ok: boolean = await ClipboardService.copyText(selectedText);
    if (!ok) {
      hilog.warn(DOMAIN, TAG, '自动复制写入剪贴板失败：id=%{public}d', selected.id);
      return;
    }
    if (uiContext) {
      const display: string = selectedText.length > AutoCopyService.TOAST_TEXT_CAP
        ? `${selectedText.substring(0, AutoCopyService.TOAST_TEXT_CAP)}…`
        : selectedText;
      showToast(uiContext, `已复制 ${display}`, 1500, TAG);
    }
    hilog.info(DOMAIN, TAG, '自动复制成功：id=%{public}d len=%{public}d', selected.id, selectedText.length);
  }

  /**
   * 纯逻辑：从本轮消息中选最新一条 autoCopy 候选。
   *
   * 规则：
   * - 仅考虑 autoCopy=true 且未在 processedIds 中的消息；
   * - 通知产生时间 now - timestamp 超过 5 分钟视为过期，不选，但其 identity 计入 identitiesToMark；
   * - 候选按 timestamp 降序、id 降序稳定排序，取首项；
   * - 选中消息的复制文本为 copy 非空取 copy，否则回退 body；
   * - 所有候选（含选中项）的 identity 计入 identitiesToMark，避免后续轮次重复评估。
   *
   * 无副作用，可独立单元测试。
   */
  static selectCandidate(messages: NotifyMessage[], processedIds: Set<string>,
    now: number): AutoCopySelection {
    const result: AutoCopySelection = new AutoCopySelection();
    const candidates: NotifyMessage[] = [];
    for (let i = 0; i < messages.length; i++) {
      const message: NotifyMessage = messages[i];
      if (!message.autoCopy) {
        continue;
      }
      const identity: string = AutoCopyService.identity(message);
      if (processedIds.has(identity)) {
        continue;
      }
      const age: number = now - message.timestamp;
      if (age < 0 || age > AutoCopyService.TIME_WINDOW_MS) {
        result.identitiesToMark.push(identity);
        continue;
      }
      candidates.push(message);
    }

    if (candidates.length === 0) {
      return result;
    }

    candidates.sort((a: NotifyMessage, b: NotifyMessage) => {
      if (b.timestamp !== a.timestamp) {
        return b.timestamp - a.timestamp;
      }
      return b.id - a.id;
    });

    const target: NotifyMessage = candidates[0];
    result.target = target;
    result.text = target.copy.length > 0 ? target.copy : target.body;
    for (let i = 0; i < candidates.length; i++) {
      result.identitiesToMark.push(AutoCopyService.identity(candidates[i]));
    }
    return result;
  }

  /** 重置内存状态（仅用于测试或重置场景；不影响已持久化的数据）。 */
  static resetState(): void {
    AutoCopyService.processedIds = new Set<string>();
    AutoCopyService.firstSyncMaxIds = new Map<string, number>();
    AutoCopyService.firstSyncDone = false;
    AutoCopyService.loaded = false;
    AutoCopyService.loadPromise = null;
  }

  private static identity(message: NotifyMessage): string {
    // 跨服务器场景下 id 空间独立，必须用 deviceKey:id 组合才能精确定位。
    return `${message.deviceKey}:${message.id}`;
  }

  /** 只淘汰最早标识，避免大批量同步时 Preferences 和内存无限增长。 */
  private static trimIfNeeded(): void {
    while (AutoCopyService.processedIds.size > AutoCopyService.PROCESSED_IDS_CAP) {
      const first: IteratorResult<string> = AutoCopyService.processedIds.values().next();
      if (first.done) {
        break;
      }
      AutoCopyService.processedIds.delete(first.value);
    }
  }

  private static async ensureLoaded(): Promise<void> {
    if (AutoCopyService.loaded) {
      return;
    }
    if (AutoCopyService.loadPromise) {
      await AutoCopyService.loadPromise;
      return;
    }
    AutoCopyService.loadPromise = AutoCopyService.loadFromDisk();
    try {
      await AutoCopyService.loadPromise;
    } finally {
      AutoCopyService.loadPromise = null;
    }
  }

  private static async loadFromDisk(): Promise<void> {
    const doneStr: string = await PreferencesUtil.getString(null,
      AutoCopyService.KEY_FIRST_SYNC_DONE, 'false');
    AutoCopyService.firstSyncDone = doneStr === 'true';

    const idsStr: string = await PreferencesUtil.getString(null,
      AutoCopyService.KEY_PROCESSED_IDS, '[]');
    const set: Set<string> = new Set<string>();
    try {
      const parsed: Object = JSON.parse(idsStr);
      if (parsed instanceof Array) {
        const arr: Object[] = parsed as Object[];
        for (let i = 0; i < arr.length; i++) {
          if (typeof arr[i] === 'string') {
            set.add(arr[i] as string);
          }
        }
      }
    } catch (err) {
      // 旧格式或损坏数据：忽略，下一次 persist 会用正确格式覆盖。
      const msg: string = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, TAG, '已处理 id 列表解析失败，重置为空：%{public}s', msg);
    }
    AutoCopyService.processedIds = set;
    const watermarkJson: string = await PreferencesUtil.getString(null,
      AutoCopyService.KEY_FIRST_SYNC_MAX_IDS, '{}');
    try {
      const parsed: Record<string, number> = JSON.parse(watermarkJson) as Record<string, number>;
      const watermark: Map<string, number> = new Map<string, number>();
      Object.keys(parsed).forEach((source: string) => {
        const id: number = parsed[source];
        if (Number.isSafeInteger(id) && id > 0) {
          watermark.set(source, id);
        }
      });
      AutoCopyService.firstSyncMaxIds = watermark;
    } catch (err) {
      hilog.warn(DOMAIN, TAG, '首次同步水位解析失败：%{public}s',
        err instanceof Error ? err.message : String(err));
    }
    AutoCopyService.loaded = true;
  }

  private static async persist(): Promise<void> {
    const arr: string[] = [];
    AutoCopyService.processedIds.forEach((value: string) => {
      arr.push(value);
    });
    await PreferencesUtil.putString(null, AutoCopyService.KEY_PROCESSED_IDS, JSON.stringify(arr));
  }
}
