import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { util } from '@kit.ArkTS';
import { ServerManager } from './ServerManager';
import { ServerEntry } from '../model/ServerEntry';
import { HttpResponse, HttpUtil } from '../utils/HttpUtil';
import { AppContextStore } from '../common/AppContextStore';
import { NotifyMessage } from '../model/NotifyMessage';
import { DOMAIN } from '../common/Constant';

const TAG: string = 'NotifyMsgSvc';

// 内置默认客户端 Token（BASE64，运行时 decode 后使用）
// 用户未自定义时自动使用该 token 拉取消息
const DEFAULT_CLIENT_TOKEN_BASE64: string = 'OTkwMDgzODA0';

/** 解码默认 client token（失败返回空串） */
function decodeDefaultClientToken(): string {
  try {
    const bytes: Uint8Array = new util.Base64Helper().decodeSync(DEFAULT_CLIENT_TOKEN_BASE64);
    // 默认 token 为纯 ASCII 数字，逐字节转字符避免调用已弃用的 decodeWithStream
    let s: string = '';
    for (let i: number = 0; i < bytes.length; i++) {
      s += String.fromCharCode(bytes[i]);
    }
    return s;
  } catch (err) {
    hilog.error(DOMAIN, TAG, '默认 client token 解码失败：%{public}s',
      err instanceof Error ? err.message : String(err));
    return '';
  }
}

// POST /push 请求体（V2 单设备推送，见 SERVER_API.md）
class PushRequest extends Object {
  device_key: string = '';
  title: string = '';
  body: string = '';
  action?: string;
  id?: number;
  icon?: string;
  badge?: number;
  sound?: string;
  soundDuration?: number;
  foregroundShow?: number;
  inboxContent?: string[];
}

// POST /push 响应信封：{ code, message, timestamp }
class PushEnvelope extends Object {
  code: number = 0;
  message: string = '';
  timestamp: number = 0;
}

// 服务端响应格式（gotify 兼容）：{ paging, messages: [...] }
// 注意：message 接口不走服务端统一 envelope，顶层直接是 {paging, messages}
// 增量同步协议下额外返回 deletions（仅请求带 deletedSince 时出现）
class GotifyMessageResponse extends Object {
  paging: Object | null = null;
  messages: Object | null = null;
  deletions: Object | null = null;
}

// 调用结果
export class MessageListResult {
  ok: boolean = false;
  messages: NotifyMessage[] = [];
  errorMsg: string = '';
  // 服务端流式导出是否被截断（paging.error 非空，数据可能不完整）
  truncated: boolean = false;
  // 服务端原始消息数组（保留全部字段，无损导出用；仅全量导出时填充）
  rawMessages: Object[] = [];
  // ====== 增量同步协议字段（after + deletedSince）======
  // after 翻页是否还有更新的消息
  hasMore: boolean = false;
  // 本次响应的删除事件：被删消息 id 列表
  deletionIds: number[] = [];
  // 本次响应的清空事件：ceiling 列表（本地删除 id <= ceiling 的所有消息）
  purges: number[] = [];
  // 删除流水当前游标（下次请求作为 deletedSince）
  delCursor: number = 0;
  // 删除事件是否还有下一页
  delHasMore: boolean = false;
  // 游标已落在流水保留期缺口内：客户端应清空本地缓存并重新播种
  reset: boolean = false;
}

function resolveContext(ctx: common.Context | null): common.Context | null {
  if (ctx) {
    return ctx;
  }
  return AppContextStore.getInstance().getContext();
}

export class NotifyMessageService {
  private static instance: NotifyMessageService | null = null;

  static getInstance(): NotifyMessageService {
    if (!NotifyMessageService.instance) {
      NotifyMessageService.instance = new NotifyMessageService();
    }
    return NotifyMessageService.instance;
  }

  // 3) 顶层是单条对象（有 id/message 等字段）→ 当作单条解析
  private static extractMessages(data: Object | null): NotifyMessage[] {
    const list: NotifyMessage[] = [];
    if (!data) {
      return list;
    }

    // 情况 1：顶层是数组
    if (data instanceof Array) {
      const arr: Object[] = data as Object[];
      for (let i = 0; i < arr.length; i++) {
        const item = arr[i] as Record<string, Object>;
        if (item) {
          list.push(NotifyMessage.fromRaw(item));
        }
      }
      return list;
    }

    const raw = data as Record<string, Object>;
    // 情况 2：顶层 messages 是数组（标准格式）
    const messagesVal: Object | undefined = raw['messages'];
    if (messagesVal instanceof Array) {
      const arr: Object[] = messagesVal as Object[];
      for (let i = 0; i < arr.length; i++) {
        const item = arr[i] as Record<string, Object>;
        if (item) {
          list.push(NotifyMessage.fromRaw(item));
        }
      }
      return list;
    }

    // 情况 3：顶层本身像单条消息
    if (raw['id'] !== undefined || raw['message'] !== undefined || raw['body'] !== undefined) {
      list.push(NotifyMessage.fromRaw(raw));
    }
    return list;
  }

  // 获取指定 server 用户手动配置的 client token（不含内置默认；返回空 = 用户没填）。
  // server 为空时取当前 server。
  async getClientToken(context: common.Context | null = null, server: ServerEntry | null = null): Promise<string> {
    await ServerManager.getInstance().ensureLoaded();
    if (server) {
      return server.clientToken;
    }
    return ServerManager.getInstance().getCurrentClientToken();
  }

  /**
   * 实际生效的 client token：
   *   - 指定 server 有自定义（非空 trim 后）→ 返回用户值
   *   - 指定 server 未自定义 → 返回内置默认 token（BASE64 decode 后）
   * server 为空时取当前 server。
   */
  async getEffectiveClientToken(context: common.Context | null = null,
    server: ServerEntry | null = null): Promise<string> {
    const saved: string = await this.getClientToken(context, server);
    const trimmed: string = saved ? saved.trim() : '';
    if (trimmed.length > 0) {
      return trimmed;
    }
    const fallback: string = decodeDefaultClientToken();
    hilog.info(DOMAIN, TAG, 'server 未配置 client token，使用内置默认值');
    return fallback;
  }

  /** 当前 server 是否使用内置默认 token（per-server 配置为空或只含空白 = 默认） */
  async isClientTokenDefault(context: common.Context | null = null): Promise<boolean> {
    const saved: string = await this.getClientToken(context);
    return !(saved && saved.trim().length > 0);
  }

  /**
   * 是否已经有可用的 client token（自定义 or 内置默认）。
   * 用于 NotifyView 判断要不要展示"未配置"引导。
   */
  async hasEffectiveClientToken(context: common.Context | null = null): Promise<boolean> {
    const eff: string = await this.getEffectiveClientToken(context);
    // 显式返回布尔，避免 ArkTS 推断出 string | boolean 类型
    return eff.length > 0;
  }

  // 拉取消息列表。device_key 来自 DeviceRegisterService，client token 来自持久化
  // 返回 MessageListResult：ok=false 时 errorMsg 含原因（未注册/未配置 token/网络失败/认证失败）
  // since > 0 时拼接 ?since=N，用于触底分页加载更老的消息（gotify 协议：返回 ID <= since 的消息）

  // 设置当前 server 的 client token（per-server）。空串/纯空白 = 清除自定义，恢复到内置默认
  async setClientToken(context: common.Context | null, token: string): Promise<boolean> {
    await ServerManager.getInstance().ensureLoaded();
    const cur: ServerEntry | null = ServerManager.getInstance().getCurrentServer();
    if (!cur) {
      return false;
    }
    const v: string = token ? token.trim() : '';
    await ServerManager.getInstance().updateServerClientToken(context, cur.id, v);
    return true;
  }

  // 从响应体解析消息列表，容错多种结构：
  // 1) 顶层是 {messages: [...]} → 解析 messages（gotify/timelynotify 标准格式）
  // 2) 顶层直接是数组 → 直接解析

  // limit 默认 100，控制单次返回条数；客户端据此判断是否到底（返回 < limit 视为到底）
  // since > 0：向后翻页（返回 id < since），用于触底加载更老消息
  // after > 0：向前增量（返回 id > after，升序），用于拉取本地没有的新消息（与 since 互斥）
  // deletedSince > 0：返回该游标之后的删除事件（deletions 信封）
  async getMessages(context: common.Context | null = null, since: number = 0,
    limit: number = 100, after: number = 0, deletedSince: number = 0,
    server: ServerEntry | null = null, includeAfterCursor: boolean = false): Promise<MessageListResult> {
    const result = new MessageListResult();

    await ServerManager.getInstance().ensureLoaded();
    let deviceKey: string = '';
    let baseURL: string = '';
    if (server) {
      deviceKey = server.deviceKey;
      baseURL = server.baseURL;
    } else {
      deviceKey = await ServerManager.getInstance().getCurrentDeviceKey(context);
      baseURL = ServerManager.getInstance().getCurrentBaseURL();
    }
    if (!deviceKey || deviceKey.length === 0) {
      result.errorMsg = '设备未注册';
      return result;
    }

    const clientToken: string = await this.getEffectiveClientToken(context, server);
    if (!clientToken || clientToken.length === 0) {
      result.errorMsg = '未配置客户端 Token，请到服务器设置中配置';
      return result;
    }

    // 拼接 URL：指定 server 时用其 baseURL，否则用当前 server
    let fullURL: string = baseURL;
    const path: string = `/${deviceKey}/message`;
    if (fullURL.length > 0 && fullURL[fullURL.length - 1] === '/') {
      fullURL = fullURL.substring(0, fullURL.length - 1);
    }
    fullURL += path;
    const params: string[] = [];
    if (since > 0) {
      params.push(`since=${since}`);
    }
    // after=0 也必须能显式传给服务端：它代表从最早消息开始的完整历史播种，
    // 与不传 after（服务端默认返回最新一页）语义不同。
    if (after > 0 || includeAfterCursor) {
      params.push(`after=${after}`);
    }
    if (deletedSince > 0) {
      params.push(`deletedSince=${deletedSince}`);
    }
    if (limit > 0) {
      params.push(`limit=${limit}`);
    }
    if (params.length > 0) {
      fullURL += `?${params.join('&')}`;
    }
    hilog.info(DOMAIN, TAG, '拉取消息：GET %{public}s', fullURL);

    const headers: Record<string, string> = {
      'X-Gotify-Key': clientToken,
    };
    const resp: HttpResponse<GotifyMessageResponse> = await HttpUtil.get<GotifyMessageResponse>(fullURL, headers);

    if (resp.code === 401) {
      result.errorMsg = '客户端 Token 无效或已过期，请到服务器设置中重新配置';
      return result;
    }
    if (resp.code === 404) {
      result.errorMsg = '设备不存在';
      return result;
    }
    if (resp.code < 200 || resp.code >= 300) {
      result.errorMsg = `请求失败（HTTP ${resp.code}）`;
      return result;
    }
    if (!resp.result) {
      result.errorMsg = '响应为空';
      return result;
    }

    // 顶层直接是 {paging, messages}，不走服务端统一 envelope
    result.messages = NotifyMessageService.extractMessages(resp.result as Object);

    // 解析 paging.hasMore（after 增量翻页用）
    const raw = resp.result as Object as Record<string, Object>;
    const pagingVal: Object | undefined = raw['paging'];
    if (pagingVal && typeof pagingVal === 'object') {
      const paging = pagingVal as Record<string, Object>;
      const hasMoreVal: Object | undefined = paging['hasMore'];
      result.hasMore = typeof hasMoreVal === 'boolean' ? hasMoreVal : false;
    }

    // 解析 deletions 信封（仅请求带 deletedSince 时服务端返回）
    const delVal: Object | undefined = raw['deletions'];
    if (delVal && typeof delVal === 'object') {
      const del = delVal as Record<string, Object>;
      result.delCursor = NotifyMessageService.asNumber(del['cursor']);
      result.delHasMore = NotifyMessageService.asBoolean(del['hasMore']);
      result.reset = NotifyMessageService.asBoolean(del['reset']);
      const idsVal: Object | undefined = del['ids'];
      if (idsVal instanceof Array) {
        for (let i = 0; i < idsVal.length; i++) {
          const id: number = NotifyMessageService.asNumber(idsVal[i]);
          if (id > 0) {
            result.deletionIds.push(id);
          }
        }
      }
      const purgesVal: Object | undefined = del['purges'];
      if (purgesVal instanceof Array) {
        for (let i = 0; i < purgesVal.length; i++) {
          const c: number = NotifyMessageService.asNumber(purgesVal[i]);
          if (c > 0) {
            result.purges.push(c);
          }
        }
      }
    }

    result.ok = true;
    hilog.info(DOMAIN, TAG,
      '拉取成功，消息 %{public}d 条，删除 %{public}d 条，purge %{public}d，reset=%{public}s',
      result.messages.length, result.deletionIds.length,
      result.purges.length, result.reset ? 'true' : 'false');
    return result;
  }

  // 安全把任意值转成 number（非数字返回 0）
  private static asNumber(v: Object | undefined): number {
    if (typeof v === 'number') {
      return v;
    }
    if (typeof v === 'string') {
      const n: number = Number(v);
      return isNaN(n) ? 0 : n;
    }
    return 0;
  }

  // 安全把任意值转成 boolean
  private static asBoolean(v: Object | undefined): boolean {
    return typeof v === 'boolean' ? v : false;
  }

  // 全量导出消息：GET /{device_key}/message?limit=-1
  // 服务端分块流式返回该设备全部现存消息（信封 {paging, messages}；messages 数组在前、paging 补在末尾，
  // 对 JSON 解析无影响）。成功时 rawMessages 为服务端原始消息数组（无损导出），truncated=true 表示流中途异常被截断。
  async exportAllMessages(context: common.Context | null = null): Promise<MessageListResult> {
    const result = new MessageListResult();
    const ctx: common.Context | null = resolveContext(context);

    await ServerManager.getInstance().ensureLoaded();
    const deviceKey: string = await ServerManager.getInstance().getCurrentDeviceKey(ctx);
    if (!deviceKey || deviceKey.length === 0) {
      result.errorMsg = '设备未注册';
      return result;
    }

    const clientToken: string = await this.getEffectiveClientToken(ctx);
    if (!clientToken || clientToken.length === 0) {
      result.errorMsg = '未配置客户端 Token，请到服务器设置中配置';
      return result;
    }

    const fullURL: string = ServerManager.getInstance().resolveURL(`/${deviceKey}/message?limit=-1`);
    const headers: Record<string, string> = {
      'X-Gotify-Key': clientToken,
    };
    hilog.info(DOMAIN, TAG, '全量导出：GET %{public}s', fullURL);

    // 全量导出为流式响应，耗时随消息量增长，读超时放宽到 60s
    const resp: HttpResponse<GotifyMessageResponse> =
      await HttpUtil.get<GotifyMessageResponse>(fullURL, headers, 60000);

    if (resp.code === 401) {
      result.errorMsg = '客户端 Token 无效或已过期';
      return result;
    }
    if (resp.code === 404) {
      result.errorMsg = '设备不存在';
      return result;
    }
    if (resp.code < 200 || resp.code >= 300) {
      result.errorMsg = `请求失败（HTTP ${resp.code}）`;
      return result;
    }
    if (!resp.result) {
      result.errorMsg = '响应为空';
      return result;
    }

    // 提取 messages 原始数组（无损保留服务端全部字段，供 JSON 序列化导出）
    // 经 Object 中转避免 Record 直接转换的编译器类型重叠检查报错
    const raw = resp.result as Object as Record<string, Object>;
    const messagesVal: Object | undefined = raw['messages'];
    if (messagesVal instanceof Array) {
      result.rawMessages = messagesVal as Object[];
    }

    // paging.error 非空（如 'stream truncated'）→ 流式传输被截断，数据可能不完整
    const pagingVal: Object | undefined = raw['paging'];
    if (pagingVal && typeof pagingVal === 'object') {
      const paging = pagingVal as Record<string, Object>;
      const errVal: Object | undefined = paging['error'];
      if (typeof errVal === 'string' && errVal.length > 0) {
        result.truncated = true;
        hilog.warn(DOMAIN, TAG, '全量导出流被截断：paging.error=%{public}s', errVal);
      }
    }

    result.ok = true;
    hilog.info(DOMAIN, TAG, '全量导出成功，共 %{public}d 条', String(result.rawMessages.length));
    return result;
  }

  // 删除单条消息（服务端 API）：DELETE /{device_key}/message/{id}

  // 返回 '' 表示成功；非空是错误描述。server 为空时操作当前服务器。
  async deleteMessage(messageId: number, context: common.Context | null = null,
    server: ServerEntry | null = null): Promise<string> {
    if (messageId <= 0) {
      return '消息 ID 无效';
    }
    const ctx: common.Context | null = resolveContext(context);
    await ServerManager.getInstance().ensureLoaded();
    let deviceKey: string = '';
    let baseURL: string = '';
    if (server) {
      deviceKey = server.deviceKey;
      baseURL = server.baseURL;
    } else {
      deviceKey = await ServerManager.getInstance().getCurrentDeviceKey(ctx);
      baseURL = ServerManager.getInstance().getCurrentBaseURL();
    }
    if (!deviceKey || deviceKey.length === 0) {
      return '设备未注册';
    }
    const clientToken: string = await this.getEffectiveClientToken(ctx, server);
    if (!clientToken || clientToken.length === 0) {
      return '未配置客户端 Token';
    }
    if (baseURL.length > 0 && baseURL[baseURL.length - 1] === '/') {
      baseURL = baseURL.substring(0, baseURL.length - 1);
    }
    const fullURL: string = `${baseURL}/${deviceKey}/message/${messageId}`;
    const headers: Record<string, string> = { 'X-Gotify-Key': clientToken };
    hilog.info(DOMAIN, TAG, '删除消息：DELETE %{public}s', fullURL);
    try {
      const resp = await HttpUtil.delete<Object>(fullURL, headers);
      if (resp.code === 401) {
        return '客户端 Token 无效';
      }
      if (resp.code === 404) {
        return '消息不存在';
      }
      if (resp.code < 200 || resp.code >= 300) {
        return `删除失败（HTTP ${resp.code}）`;
      }
      hilog.info(DOMAIN, TAG, '消息 %{public}d 删除成功', messageId);
      return '';
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, TAG, '删除消息异常：%{public}s', msg);
      return `删除失败：${msg}`;
    }
  }

  // 删除全部消息（服务端 API）：DELETE /{device_key}/message。server 为空时操作当前服务器。
  async deleteAllMessages(context: common.Context | null = null,
    server: ServerEntry | null = null): Promise<string> {
    const ctx: common.Context | null = resolveContext(context);
    await ServerManager.getInstance().ensureLoaded();
    let deviceKey: string = '';
    let baseURL: string = '';
    if (server) {
      deviceKey = server.deviceKey;
      baseURL = server.baseURL;
    } else {
      deviceKey = await ServerManager.getInstance().getCurrentDeviceKey(ctx);
      baseURL = ServerManager.getInstance().getCurrentBaseURL();
    }
    if (!deviceKey || deviceKey.length === 0) {
      return '设备未注册';
    }
    const clientToken: string = await this.getEffectiveClientToken(ctx, server);
    if (!clientToken || clientToken.length === 0) {
      return '未配置客户端 Token';
    }
    if (baseURL.length > 0 && baseURL[baseURL.length - 1] === '/') {
      baseURL = baseURL.substring(0, baseURL.length - 1);
    }
    const fullURL: string = `${baseURL}/${deviceKey}/message`;
    const headers: Record<string, string> = { 'X-Gotify-Key': clientToken };
    hilog.info(DOMAIN, TAG, '删除全部消息：DELETE %{public}s', fullURL);
    try {
      const resp = await HttpUtil.delete<Object>(fullURL, headers);
      if (resp.code === 401) {
        return '客户端 Token 无效';
      }
      if (resp.code < 200 || resp.code >= 300) {
        return `清空失败（HTTP ${resp.code}）`;
      }
      hilog.info(DOMAIN, TAG, '全部消息清空成功');
      return '';
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, TAG, '清空消息异常：%{public}s', msg);
      return `清空失败：${msg}`;
    }
  }

  // 发送测试推送（SERVER_API.md：POST /push，V2 单设备推送，默认无认证）
  // 固定 title「订阅通知」+ 固定文案 body，目标为当前服务器对应的 device_key
  // 返回 '' 表示成功；非空为错误描述
  async sendTestPush(context: common.Context | null = null): Promise<string> {
    const ctx: common.Context | null = resolveContext(context);
    await ServerManager.getInstance().ensureLoaded();
    const deviceKey: string = await ServerManager.getInstance().getCurrentDeviceKey(ctx);
    if (!deviceKey || deviceKey.length === 0) {
      return '设备未注册';
    }

    const req = new PushRequest();
    req.device_key = deviceKey;
    req.title = '[订阅通知] 及时通知推送';
    req.body = '这是一条测试通知，收到即表示订阅推送链路工作正常';
    req.icon = 'https://static.wallleap.cn/temp/nwvgnm7l2on5u6c531mo.jpg'
    req.sound = 'multiwayinvitation'

    const fullURL: string = ServerManager.getInstance().resolveURL('/push');
    hilog.info(DOMAIN, TAG, '测试推送：POST %{public}s', fullURL);
    try {
      const resp: HttpResponse<PushEnvelope> = await HttpUtil.post<PushEnvelope, PushRequest>(fullURL, req);
      if (resp.code < 200 || resp.code >= 300) {
        // code=0 为网络层异常（resp.message 已含原因），否则为 HTTP 状态错误
        return resp.code === 0 ? resp.message : `推送失败（HTTP ${resp.code}）`;
      }
      if (!resp.result) {
        return '响应为空';
      }
      // 服务端信封 code 非 200 时透出原因（正常应与 HTTP 状态一致）
      if (resp.result.code !== 200 && resp.result.message.length > 0) {
        return resp.result.message;
      }
      hilog.info(DOMAIN, TAG, '测试推送成功：device_key=%{public}s', deviceKey);
      return '';
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, TAG, '测试推送异常：%{public}s', msg);
      return `推送失败：${msg}`;
    }
  }
}
