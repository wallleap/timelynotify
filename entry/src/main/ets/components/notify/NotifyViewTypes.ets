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

/** 依据消息当前顺序生成稳定的列表分组，避免渲染层重复维护排序逻辑。 */
export function buildNotifySections(messages: NotifyMessage[]): NotifySection[] {
  const counts: Map<string, number> = new Map<string, number>();
  for (let i = 0; i < messages.length; i++) {
    if (messages[i].group.length > 0) {
      counts.set(messages[i].group, (counts.get(messages[i].group) ?? 0) + 1);
    }
  }
  const sections: NotifySection[] = [];
  const positions: Map<string, number> = new Map<string, number>();
  for (let i = 0; i < messages.length; i++) {
    const message: NotifyMessage = messages[i];
    if (message.group.length === 0) {
      sections.push({ key: `single:${message.id}`, groupKey: '', messages: [message], grouped: false });
      continue;
    }
    const position: number | undefined = positions.get(message.group);
    if (position === undefined) {
      positions.set(message.group, sections.length);
      sections.push({ key: `group:${message.group}:${counts.get(message.group) ?? 0}`, groupKey: message.group,
        messages: [message], grouped: false });
    } else {
      sections[position].messages.push(message);
      sections[position].grouped = true;
    }
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
