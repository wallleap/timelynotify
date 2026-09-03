// 推送消息条目（GET /:device_key/message 返回列表的单项）
// 兼容 gotify 标准字段与 timelynotify 可能的字段命名差异
export class NotifyMessage extends Object {
  id: number = 0;
  appid: number = 0;
  title: string = '';
  // 消息正文：gotify 用 message，timelynotify 可能用 body
  body: string = '';
  // 副标题（来自 extras.subtitle）
  subtitle: string = '';
  priority: number = 0;
  // 原始时间字段（ISO 字符串或时间戳），解析后填充 timestamp
  date: string = '';
  // 服务端统一响应可能用 created_at
  createdAt: string = '';
  // 解析后的毫秒时间戳，便于排序与展示
  timestamp: number = 0;
  // 图片 URL（来自 extras.icon），非空时列表右侧显示圆角缩略图
  image: string = '';
  // 收件箱式多行摘要（来自 extras.inboxcontent）：非空时正文优先按行展示，每条一行/一段
  inboxContent: string[] = [];

  // 从服务端 JSON 对象解析（容错多种字段命名）
  static fromRaw(raw: Record<string, Object>): NotifyMessage {
    const m = new NotifyMessage();
    const idVal: Object | undefined = raw['id'];
    m.id = typeof idVal === 'number' ? idVal : (typeof idVal === 'string' ? Number(idVal) || 0 : 0);

    const appidVal: Object | undefined = raw['appid'];
    m.appid = typeof appidVal === 'number' ? appidVal : 0;

    const titleVal: Object | undefined = raw['title'];
    m.title = typeof titleVal === 'string' ? titleVal : '';

    const bodyVal: Object | undefined = raw['body'];
    const msgVal: Object | undefined = raw['message'];
    m.body = typeof bodyVal === 'string' ? bodyVal : (typeof msgVal === 'string' ? msgVal : '');

    const prioVal: Object | undefined = raw['priority'];
    m.priority = typeof prioVal === 'number' ? prioVal : 0;

    // 副标题从 extras.subtitle 取
    const extrasVal: Object | undefined = raw['extras'];
    if (extrasVal && typeof extrasVal === 'object') {
      const extras = extrasVal as Record<string, Object>;
      const subtitleVal: Object | undefined = extras['subtitle'];
      m.subtitle = typeof subtitleVal === 'string' ? subtitleVal : '';
      // 图片 URL 从 extras.icon 取
      const iconVal: Object | undefined = extras['icon'];
      m.image = typeof iconVal === 'string' ? iconVal : '';
      // 多行摘要：服务端 extras 键名统一小写为 inboxcontent，兼容驼峰 inboxContent；仅收集字符串项
      const inboxVal: Object | undefined =
        extras['inboxcontent'] !== undefined ? extras['inboxcontent'] : extras['inboxContent'];
      if (inboxVal instanceof Array) {
        const lines: string[] = [];
        const arr: Object[] = inboxVal as Object[];
        for (let i = 0; i < arr.length; i++) {
          if (typeof arr[i] === 'string') {
            lines.push(arr[i] as string);
          }
        }
        m.inboxContent = lines;
      }
    }

    const dateVal: Object | undefined = raw['date'];
    m.date = typeof dateVal === 'string' ? dateVal : '';
    const createdAtVal: Object | undefined = raw['created_at'];
    m.createdAt = typeof createdAtVal === 'string' ? createdAtVal : '';

    m.timestamp = NotifyMessage.parseTimestamp(m.date.length > 0 ? m.date : m.createdAt);
    return m;
  }

  // 解析时间字符串/数字为毫秒时间戳；失败返回 0
  // 容错：ISO 字符串含纳秒精度（如 .601935171）会被截断到毫秒
  static parseTimestamp(input: string): number {
    if (!input || input.length === 0) {
      return 0;
    }
    // 纯数字 → 当作秒级或毫秒级时间戳
    if (/^\d+$/.test(input)) {
      const n: number = Number(input);
      // 10 位按秒处理
      return input.length <= 10 ? n * 1000 : n;
    }
    // ISO 字符串：先尝试直接解析
    let t: number = Date.parse(input);
    // 直接解析失败时，把秒以下超过 3 位的纳秒部分截断到毫秒再试
    if (isNaN(t)) {
      const dotIdx: number = input.indexOf('.');
      if (dotIdx >= 0) {
        const head: string = input.substring(0, dotIdx + 1);
        const tail: string = input.substring(dotIdx + 1);
        const tzIdx: number = tail.search(/[Z+\-]/);
        const frac: string = tzIdx > 0 ? tail.substring(0, tzIdx) : tail;
        const tz: string = tzIdx > 0 ? tail.substring(tzIdx) : '';
        const milliFrac: string = frac.length > 3 ? frac.substring(0, 3) : frac;
        const normalized: string = `${head}${milliFrac}${tz}`;
        t = Date.parse(normalized);
      }
    }
    return isNaN(t) ? 0 : t;
  }
}

