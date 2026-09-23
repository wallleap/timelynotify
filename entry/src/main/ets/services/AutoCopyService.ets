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
  /** 通知产生后允许自动复制的时效窗口（毫秒）。 */
  private static readonly TIME_WINDOW_MS: number = 5 * 60 * 1000;
  /** 已处理 id 集合上限：超过则整体清空，避免无限增长；过期 id 受时效窗口保护不会被误复制。 */
  private static readonly PROCESSED_IDS_CAP: number = 1000;
  /** Toast 文案最大长度，超出截断显示省略号，避免长文本撑满屏幕。 */
  private static readonly TOAST_TEXT_CAP: number = 20;

  private static processedIds: Set<string> = new Set<string>();
  private static firstSyncDone: boolean = false;
  private static loaded: boolean = false;
  private static loadPromise: Promise<void> | null = null;

  /**
   * 处理一轮同步拉到的新消息。
   *
   * @param messages 本轮同步从服务端拉取并已解密完成的新消息（含跨服务器、跨分页聚合）
   * @param uiContext 用于展示 Toast 的 UIContext；为 null 时仅复制不提示
   */
  static async handleSyncRound(messages: NotifyMessage[], uiContext: UIContext | null): Promise<void> {
    if (messages.length === 0) {
      // 空轮次也要确保首次同步标记被设置，避免后续轮次误判为首次历史同步。
      await AutoCopyService.ensureLoaded();
      if (!AutoCopyService.firstSyncDone) {
        AutoCopyService.firstSyncDone = true;
        await PreferencesUtil.putString(null, AutoCopyService.KEY_FIRST_SYNC_DONE, 'true');
      }
      return;
    }

    await AutoCopyService.ensureLoaded();

    // 首次历史同步：标记完成并把当前所有消息 id 记为已处理，后续刷新不再考虑这批积压。
    if (!AutoCopyService.firstSyncDone) {
      AutoCopyService.firstSyncDone = true;
      AutoCopyService.trimIfNeeded();
      for (let i = 0; i < messages.length; i++) {
        AutoCopyService.processedIds.add(AutoCopyService.identity(messages[i]));
      }
      await AutoCopyService.persist();
      await PreferencesUtil.putString(null, AutoCopyService.KEY_FIRST_SYNC_DONE, 'true');
      hilog.info(DOMAIN, TAG, '首次历史同步完成，标记 %{public}d 条为已处理，不触发自动复制',
        messages.length);
      return;
    }

    const now: number = Date.now();
    AutoCopyService.trimIfNeeded();

    const selection: AutoCopySelection = AutoCopyService.selectCandidate(messages, AutoCopyService.processedIds, now);
    if (selection.identitiesToMark.length > 0) {
      for (let i = 0; i < selection.identitiesToMark.length; i++) {
        AutoCopyService.processedIds.add(selection.identitiesToMark[i]);
      }
      await AutoCopyService.persist();
    }

    if (selection.target === null || selection.text.length === 0) {
      return;
    }

    const ok: boolean = await ClipboardService.copyText(selection.text);
    if (!ok) {
      hilog.warn(DOMAIN, TAG, '自动复制写入剪贴板失败：id=%{public}d', selection.target.id);
      return;
    }
    if (uiContext) {
      const display: string = selection.text.length > AutoCopyService.TOAST_TEXT_CAP
        ? `${selection.text.substring(0, AutoCopyService.TOAST_TEXT_CAP)}…`
        : selection.text;
      showToast(uiContext, `已复制 ${display}`, 1500, TAG);
    }
    hilog.info(DOMAIN, TAG, '自动复制成功：id=%{public}d len=%{public}d', selection.target.id, selection.text.length);
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
    AutoCopyService.firstSyncDone = false;
    AutoCopyService.loaded = false;
    AutoCopyService.loadPromise = null;
  }

  private static identity(message: NotifyMessage): string {
    // 跨服务器场景下 id 空间独立，必须用 deviceKey:id 组合才能精确定位。
    return `${message.deviceKey}:${message.id}`;
  }

  /** 集合超过上限时整体清空；过期 id 受时效窗口保护，即便被重新评估也不会误复制。 */
  private static trimIfNeeded(): void {
    if (AutoCopyService.processedIds.size >= AutoCopyService.PROCESSED_IDS_CAP) {
      hilog.info(DOMAIN, TAG, '已处理 id 集合达到上限 %{public}d，清空重建',
        AutoCopyService.PROCESSED_IDS_CAP);
      AutoCopyService.processedIds = new Set<string>();
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
