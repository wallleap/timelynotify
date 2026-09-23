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
  // 通知来源图标（来自 extras.icon），列表和详情标题区左侧显示。
  icon: string = '';
  // 正文图片（来自 extras.image），列表右侧显示缩略图，详情正文下方显示大图。
  image: string = '';
  // 收件箱式多行摘要（来自 extras.inboxcontent）：非空时正文优先按行展示，每条一行/一段
  inboxContent: string[] = [];
  // 通知分组标识（来自 extras.group）：非空且相同的消息在列表中折叠为一组
  group: string = '';
  // 点击跳转 URL（来自 extras.url，Bark 语义：点击通知跳转）：非空时点击卡片/系统通知直接打开
  url: string = '';
  // 运行时字段：消息所属服务器的 device_key（从本地缓存读出时赋值，不参与服务端 JSON 解析）。
  // 用于跨服务器场景下精确定位删除目标（不同服务器 id 空间独立，仅靠 id 会误删）
  deviceKey: string = '';
  // 端到端加密字段仅用于客户端解密，不写入展示内容。
  ciphertext: string = '';
  iv: string = '';
  // 原始消息是否携带 ciphertext；持久化到本地缓存，供解密后的列表展示状态标签。
  encrypted: boolean = false;
  // 仅用于本次远程迁移：普通消息默认可清理；加密消息必须成功解密后才允许删除远程副本。
  migrationReady: boolean = true;
  // Bark isArchive 语义：缺省保留历史，显式非 1 时仅展示系统通知、不写本地历史。
  archive: boolean = true;
  // ttl 换算后的绝对过期时间（毫秒）；0 表示永不过期。
  expiresAt: number = 0;

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
      // icon 与 image 保持 Bark 原始语义，不能复用同一个本地字段。
      const iconVal: Object | undefined = extras['icon'];
      m.icon = typeof iconVal === 'string' ? iconVal.trim() : '';
      const imageVal: Object | undefined = extras['image'];
      m.image = typeof imageVal === 'string' ? imageVal.trim() : '';
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
  // 分组标识从 extras.group 取，纯空白视为“默认”分组
      const groupVal: Object | undefined = extras['group'];
      m.group = typeof groupVal === 'string' ? groupVal.trim() : '';
      // 跳转 URL 从 extras.url 取，纯空白视为无链接
      const urlVal: Object | undefined = extras['url'];
      m.url = typeof urlVal === 'string' ? urlVal.trim() : '';
      const ciphertextVal: Object | undefined = extras['ciphertext'];
      m.ciphertext = typeof ciphertextVal === 'string' ? ciphertextVal.trim() : '';
      const ivVal: Object | undefined = extras['iv'];
      m.iv = typeof ivVal === 'string' ? ivVal : '';
    }
    // 兼容部分推送通道把 group 放在消息顶层的情况
    if (m.group.length === 0) {
      const topGroupVal: Object | undefined = raw['group'];
      m.group = typeof topGroupVal === 'string' ? topGroupVal.trim() : '';
    }
    // 兼容部分推送通道把 url 放在消息顶层的情况
    if (m.url.length === 0) {
      const topUrlVal: Object | undefined = raw['url'];
      m.url = typeof topUrlVal === 'string' ? topUrlVal.trim() : '';
    }
    // 兼容部分通道把 icon/image 放在消息顶层的透传格式。
    if (m.icon.length === 0) {
      const topIconVal: Object | undefined = raw['icon'];
      m.icon = typeof topIconVal === 'string' ? topIconVal.trim() : '';
    }
    if (m.image.length === 0) {
      const topImageVal: Object | undefined = raw['image'];
      m.image = typeof topImageVal === 'string' ? topImageVal.trim() : '';
    }
    // 兼容 ciphertext/iv 位于消息顶层的透传格式。
    if (m.ciphertext.length === 0) {
      const topCiphertextVal: Object | undefined = raw['ciphertext'];
      m.ciphertext = typeof topCiphertextVal === 'string' ? topCiphertextVal.trim() : '';
    }
    if (m.iv.length === 0) {
      const topIvVal: Object | undefined = raw['iv'];
      m.iv = typeof topIvVal === 'string' ? topIvVal : '';
    }
    m.encrypted = m.ciphertext.length > 0;
    m.migrationReady = !m.encrypted;

    const dateVal: Object | undefined = raw['date'];
    m.date = typeof dateVal === 'string' ? dateVal : '';
    const createdAtVal: Object | undefined = raw['created_at'];
    m.createdAt = typeof createdAtVal === 'string' ? createdAtVal : '';

    m.timestamp = NotifyMessage.parseTimestamp(m.date.length > 0 ? m.date : m.createdAt);
    const extras: Record<string, Object> | null = extrasVal && typeof extrasVal === 'object' ?
      extrasVal as Record<string, Object> : null;
    m.applyRetentionValues(extras, raw);
    return m;
  }

  // 将解密后的 Bark 风格 JSON 内容覆盖到消息展示字段，服务端元数据（id/时间）保持不变。
  applyDecrypted(raw: Record<string, Object>): void {
    const titleVal: Object | undefined = raw['title'];
    this.title = typeof titleVal === 'string' ? titleVal : '';
    const bodyVal: Object | undefined = raw['body'];
    const messageVal: Object | undefined = raw['message'];
    this.body = typeof bodyVal === 'string' ? bodyVal :
      (typeof messageVal === 'string' ? messageVal : '');
    const subtitleVal: Object | undefined = raw['subtitle'];
    this.subtitle = typeof subtitleVal === 'string' ? subtitleVal : '';
    const iconVal: Object | undefined = raw['icon'];
    this.icon = typeof iconVal === 'string' ? iconVal.trim() : '';
    const imageVal: Object | undefined = raw['image'];
    this.image = typeof imageVal === 'string' ? imageVal.trim() : '';
    const groupVal: Object | undefined = raw['group'];
    this.group = typeof groupVal === 'string' ? groupVal.trim() : '';
    const urlVal: Object | undefined = raw['url'];
    this.url = typeof urlVal === 'string' ? urlVal.trim() : '';
    const inboxVal: Object | undefined = raw['inboxContent'] !== undefined ?
      raw['inboxContent'] : raw['inboxcontent'];
    this.inboxContent = [];
    if (inboxVal instanceof Array) {
      const values: Object[] = inboxVal as Object[];
      for (let i: number = 0; i < values.length; i++) {
        if (typeof values[i] === 'string') {
          this.inboxContent.push(values[i] as string);
        }
      }
    }
    this.applyRetentionValues(raw, null);
    this.migrationReady = true;
  }

  // 判断本地历史是否已经达到 ttl 的绝对过期时间。
  isExpired(now: number = Date.now()): boolean {
    return this.expiresAt > 0 && this.expiresAt <= now;
  }

  // 非归档加密消息在成功解密后不会进入列表，需要通过本地通知向用户展示真实内容。
  needsDecryptedNotification(now: number = Date.now()): boolean {
    return this.encrypted && !this.archive && this.migrationReady && !this.isExpired(now);
  }

  // 从 Bark 参数读取归档与 ttl；primary 优先，兼容服务端小写键与加密内容驼峰键。
  private applyRetentionValues(primary: Record<string, Object> | null,
    fallback: Record<string, Object> | null): void {
    const archiveVal: Object | undefined = NotifyMessage.firstDefined(
      primary, fallback, ['isArchive', 'isarchive']);
    if (archiveVal !== undefined) {
      this.archive = archiveVal === true || archiveVal === 1 || archiveVal === '1';
    }
    const ttlVal: Object | undefined = NotifyMessage.firstDefined(primary, fallback, ['ttl']);
    if (ttlVal !== undefined) {
      const ttlSeconds: number = typeof ttlVal === 'number' ? ttlVal :
        (typeof ttlVal === 'string' ? Number(ttlVal) : 0);
      if (isFinite(ttlSeconds) && ttlSeconds > 0) {
        const baseTime: number = this.timestamp > 0 ? this.timestamp : Date.now();
        this.expiresAt = baseTime + Math.floor(ttlSeconds) * 1000;
      } else {
        this.expiresAt = 0;
      }
    }
  }

  private static firstDefined(primary: Record<string, Object> | null,
    fallback: Record<string, Object> | null, keys: string[]): Object | undefined {
    const sources: Array<Record<string, Object> | null> = [primary, fallback];
    for (let sourceIndex: number = 0; sourceIndex < sources.length; sourceIndex++) {
      const source: Record<string, Object> | null = sources[sourceIndex];
      if (!source) {
        continue;
      }
      for (let keyIndex: number = 0; keyIndex < keys.length; keyIndex++) {
        const value: Object | undefined = source[keys[keyIndex]];
        if (value !== undefined) {
          return value;
        }
      }
    }
    return undefined;
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
