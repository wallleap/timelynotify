import { NotifyMessage } from '../../model/NotifyMessage';

/** 正文富文本片段类型：普通文本、URL 与验证码。 */
export interface NotifyTextSegment {
  text: string;
  type: number;
}

/** 普通文本片段。 */
export const NOTIFY_SEGMENT_NORMAL: number = 0;
/** 可打开的 HTTP(S) 链接片段。 */
export const NOTIFY_SEGMENT_URL: number = 1;
/** 可复制的 4 至 8 位验证码片段。 */
export const NOTIFY_SEGMENT_CODE: number = 2;

/** 通知列表的渲染分段：单条消息或一个可折叠分组。 */
export interface NotifySection {
  key: string;
  groupKey: string;
  messages: NotifyMessage[];
  grouped: boolean;
  // 该 group_key 在数据库中的真实总数（含未加载到内存的部分）。
  // 用于徽标显示和"加载更多"按钮是否展示。无 group 的单条消息 total = messages.length。
  total: number;
}

/** buildNotifySections 内部聚合用的中间结构（ArkTS 禁止匿名对象类型）。 */
interface GroupAggregation {
  groupKey: string;
  messages: NotifyMessage[];
}

/** 文本匹配阶段的内部位置信息。 */
interface NotifyTextMatch extends NotifyTextSegment {
  start: number;
  end: number;
}

/** 将正文切为普通文本、链接和验证码，供列表与详情复用。 */
export function parseNotifyTextSegments(text: string): NotifyTextSegment[] {
  if (!text || text.length === 0) {
    return [];
  }
  const matches: NotifyTextMatch[] = [];
  const urlPattern: RegExp = /https?:\/\/[^\s<>"'\])]+/g;
  const codePattern: RegExp = /\b\d{4,8}\b/g;
  let match: RegExpExecArray | null;
  while ((match = urlPattern.exec(text)) !== null) {
    matches.push({ text: match[0], type: NOTIFY_SEGMENT_URL, start: match.index, end: match.index + match[0].length });
  }
  while ((match = codePattern.exec(text)) !== null) {
    let overlaps: boolean = false;
    for (let i = 0; i < matches.length; i++) {
      if (match.index < matches[i].end && match.index + match[0].length > matches[i].start) {
        overlaps = true;
        break;
      }
    }
    if (!overlaps) {
      matches.push({ text: match[0], type: NOTIFY_SEGMENT_CODE, start: match.index, end: match.index + match[0].length });
    }
  }
  matches.sort((a, b) => a.start - b.start);
  const segments: NotifyTextSegment[] = [];
  let lastEnd: number = 0;
  for (let i = 0; i < matches.length; i++) {
    if (matches[i].start > lastEnd) {
      segments.push({ text: text.substring(lastEnd, matches[i].start), type: NOTIFY_SEGMENT_NORMAL });
    }
    segments.push({ text: matches[i].text, type: matches[i].type });
    lastEnd = matches[i].end;
  }
  if (lastEnd < text.length) {
    segments.push({ text: text.substring(lastEnd), type: NOTIFY_SEGMENT_NORMAL });
  }
  return segments;
}

/** 无 group 消息聚合后的虚拟 groupKey（空串在 RDB 中作为 group_key 存储） */
export const UNGROUPED_GROUP_KEY: string = '';

/** 虚拟 groupKey 对应的展示名称（展开态顶栏标题 + 折叠态卡片标题） */
export function displayGroupTitle(groupKey: string): string {
  return groupKey.length === 0 ? '未分组' : groupKey;
}

/**
 * 依据消息当前顺序生成稳定的列表分组，避免渲染层重复维护排序逻辑。
 * 无 group（空串）的消息也会聚合到"未分组"虚拟 section。
 * totals 参数：每个 group_key 的真实总数，用于徽标和"加载更多"按钮。
 * 不传 totals 时回退到内存中 messages 数量（旧逻辑兼容）。
 */
export function buildNotifySections(messages: NotifyMessage[],
  totals?: Map<string, number>): NotifySection[] {
  // 第一遍：聚合消息到各 group（保持首次出现顺序）
  const raw: GroupAggregation[] = [];
  const positions: Map<string, number> = new Map<string, number>();
  for (let i = 0; i < messages.length; i++) {
    const message: NotifyMessage = messages[i];
    const position: number | undefined = positions.get(message.group);
    if (position === undefined) {
      positions.set(message.group, raw.length);
      const agg: GroupAggregation = { groupKey: message.group, messages: [message] };
      raw.push(agg);
    } else {
      raw[position].messages.push(message);
    }
  }
  // 第二遍：生成 section，key 同时含 total（删除/同步时变）和内存 size（组内加载更多 append 时变），
  // 两者任一变化都强制 ForEach 重建子树，否则新增子项不会渲染
  const sections: NotifySection[] = [];
  for (let i = 0; i < raw.length; i++) {
    const groupKey: string = raw[i].groupKey;
    const groupMessages: NotifyMessage[] = raw[i].messages;
    const total: number = totals ? (totals.get(groupKey) ?? groupMessages.length) : groupMessages.length;
    sections.push({
      key: `group:${groupKey}:${total}:${groupMessages.length}`,
      groupKey,
      messages: groupMessages,
      grouped: groupMessages.length > 1,
      total
    });
  }
  return sections;
}

/** 格式化通知时间，供列表和详情使用。 */
export function formatNotifyTime(timestamp: number): string {
  if (!timestamp) {
    return '';
  }
  const date: Date = new Date(timestamp);
  const pad = (value: number): string => String(value).padStart(2, '0');
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())} ${pad(date.getHours())}:${pad(date.getMinutes())}`;
}
