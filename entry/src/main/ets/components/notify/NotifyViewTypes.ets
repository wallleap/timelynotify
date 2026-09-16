import { NotifyMessage } from '../../model/NotifyMessage';

/** 正文富文本片段类型：普通文本、URL 与验证码。 */
export interface NotifyTextSegment {
  text: string;
  type: number;
}

/** 普通文本片段。 */
export const NOTIFY_SEGMENT_NORMAL: number = 0;
/** 可打开的 HTTP(S) 链接或邮箱地址片段。 */
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

/** 移除消息正文中紧随 URL 的常见句末标点，避免将标点一并带入打开链接。 */
function trimUrlTrailingPunctuation(url: string): string {
  let end: number = url.length;
  while (end > 0) {
    const last: string = url.charAt(end - 1);
    if (last === '.' || last === ',' || last === '!' || last === '?' || last === '。' ||
      last === '，' || last === '！' || last === '？' || last === '；' || last === '：' ||
      last === '、' || last === '（' || last === '）' || last === '【' || last === '】' ||
      last === '《' || last === '》' || last === '「' || last === '」' || last === '『' ||
      last === '』' || last === '“' || last === '”' || last === '‘' || last === '’' ||
      last === '{' || last === '}') {
      end--;
    } else {
      break;
    }
  }
  return url.substring(0, end);
}

/** 无协议域名不能紧跟邮箱用户名或单词字符，避免把 email / 普通标识的一部分误识别为链接。 */
function isEmbeddedDomain(text: string, start: number): boolean {
  if (start <= 0) {
    return false;
  }
  const previous: string = text.charAt(start - 1);
  return /[a-z0-9@._-]/i.test(previous);
}

/** 验证码必须至少含一个数字，避免将“验证码 Apple”这类普通英文文本误识别为验证码。 */
function hasVerificationCodeDigit(code: string): boolean {
  return /\d/.test(code);
}

/**
 * 将正文切为普通文本、链接、邮箱和验证码，供列表与详情复用。
 * 链接支持 HTTP(S)、无协议常见域名和 IPv4；邮箱可拉起邮件应用；验证码仅在明确的验证码语义词后识别，避免误判订单号/日期。
 */
export function parseNotifyTextSegments(text: string): NotifyTextSegment[] {
  if (!text || text.length === 0) {
    return [];
  }
  const matches: NotifyTextMatch[] = [];
  // 无协议域名要求常见顶级域名，避免将普通“名称.版本”文本误识别为链接。
  // 中文文案中常用的顿号、括号和引号同时作为链接边界，避免连续链接或引用文本被合并。
  const urlPattern: RegExp =
    /https?:\/\/[^\s<>"'\])，。！？；：、（）【】《》「」『』“”‘’{}]+|(?:www\.)?(?:[a-z0-9-]+\.)+(?:com|net|org|cn|io|app|dev|ai|xyz|me|cc|tv|info|biz|co|uk|jp|de|edu|gov)(?::\d{2,5})?(?:\/[^\s<>"'\])，。！？；：、（）【】《》「」『』“”‘’{}]+)?|(?:25[0-5]|2[0-4]\d|1?\d?\d)(?:\.(?:25[0-5]|2[0-4]\d|1?\d?\d)){3}(?::\d{2,5})?(?:\/[^\s<>"'\])，。！？；：、（）【】《》「」『』“”‘’{}]+)?/gi;
  // 邮箱单独识别为可打开项；域名部分将被 urlPattern 的嵌入检查排除，避免重复匹配。
  const emailPattern: RegExp =
    /[a-z0-9._%+-]+@(?:[a-z0-9-]+\.)+[a-z]{2,63}/gi;
  // 只识别有明确语义词引导的验证码：支持“验证码为 123456”与“123456 快手验证码”两种常见句式。
  // 捕获组 1/2 均为实际应复制的验证码：支持 4–10 位数字与字母混合，且必须至少含一个数字。
  // 验证码后最多允许 16 个品牌名字符再出现验证码语义词。
  const codePattern: RegExp =
    /(?:验证码|校验码|动态码|动态口令|一次性密码|确认码|安全码|提取码|登录码|授权码|verification\s*code|verify\s*code|otp|pin)(?:\s*(?:为|是|:|：|-))*\s*([a-z0-9]{4,10})(?![a-z0-9])|([a-z0-9]{4,10})(?![a-z0-9])(?:[\u4e00-\u9fa5a-z]{0,16})(?:验证码|校验码|动态码|动态口令|一次性密码|确认码|安全码|提取码|登录码|授权码)/gi;
  let match: RegExpExecArray | null;
  while ((match = emailPattern.exec(text)) !== null) {
    matches.push({ text: match[0], type: NOTIFY_SEGMENT_URL, start: match.index, end: match.index + match[0].length });
  }
  while ((match = urlPattern.exec(text)) !== null) {
    const url: string = trimUrlTrailingPunctuation(match[0]);
    const hasProtocol: boolean = url.toLowerCase().indexOf('http://') === 0 ||
      url.toLowerCase().indexOf('https://') === 0;
    if (!hasProtocol && isEmbeddedDomain(text, match.index)) {
      continue;
    }
    if (url.length > 0) {
      matches.push({ text: url, type: NOTIFY_SEGMENT_URL, start: match.index, end: match.index + url.length });
    }
  }
  while ((match = codePattern.exec(text)) !== null) {
    const code: string = match[1] && match[1].length > 0 ? match[1] : match[2];
    if (!hasVerificationCodeDigit(code)) {
      continue;
    }
    const codeOffset: number = match[0].lastIndexOf(code);
    const codeStart: number = match.index + codeOffset;
    let overlaps: boolean = false;
    for (let i = 0; i < matches.length; i++) {
      if (codeStart < matches[i].end && codeStart + code.length > matches[i].start) {
        overlaps = true;
        break;
      }
    }
    if (!overlaps) {
      matches.push({ text: code, type: NOTIFY_SEGMENT_CODE, start: codeStart, end: codeStart + code.length });
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
  return groupKey.length === 0 ? '默认' : groupKey;
}

/**
 * 依据消息当前顺序生成稳定的列表分组，避免渲染层重复维护排序逻辑。
 * groupEnabled=true（默认）：同 group_key 聚合，无 group（空串）的消息聚合到“默认”虚拟 section。
 * groupEnabled=false：关闭分组，每条消息都是独立的平铺 section（grouped=false）。
 * totals 参数：每个 group_key 的真实总数，用于徽标和"加载更多"按钮。
 * 不传 totals 时回退到内存中 messages 数量（旧逻辑兼容）。
 */
export function buildNotifySections(messages: NotifyMessage[],
  totals?: Map<string, number>, groupEnabled: boolean = true): NotifySection[] {
  // 平铺模式：每条消息独立渲染，不做任何聚合
  if (!groupEnabled) {
    const flat: NotifySection[] = [];
    for (let i = 0; i < messages.length; i++) {
      flat.push({
        key: `flat:${messages[i].id}`,
        groupKey: '',
        messages: [messages[i]],
        grouped: false,
        total: 1
      });
    }
    return flat;
  }
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
  // 第二遍：key 需包含总数和内存条数。ArkUI 在外层 ForEach key 不变时会复用整棵子树，
  // 使内层消息行与数量徽标无法及时刷新；两项任一变化时重建当前分组，保证删除和加载更多可见。
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
