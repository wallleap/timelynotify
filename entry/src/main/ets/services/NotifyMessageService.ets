import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ApiConfig } from '../config/ApiConfig';
import { ServerManager } from './ServerManager';
import { DeviceRegisterService } from './DeviceRegisterService';
import { PreferencesUtil } from '../utils/PreferencesUtil';
import { HttpUtil, HttpResponse } from '../utils/HttpUtil';
import { AppContextStore } from '../common/AppContextStore';
import { NotifyMessage } from '../model/NotifyMessage';

const DOMAIN: number = 0x0000;
const TAG: string = 'NotifyMsgSvc';

// 服务端响应格式（gotify 兼容）：{ paging, messages: [...] }
// 注意：message 接口不走服务端统一 envelope，顶层直接是 {paging, messages}
class GotifyMessageResponse extends Object {
  paging: Object | null = null;
  messages: Object | null = null;
}

// 调用结果
export class MessageListResult {
  ok: boolean = false;
  messages: NotifyMessage[] = [];
  errorMsg: string = '';
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

  // 获取缓存的 client token（用户手动配置）
  async getClientToken(context: common.Context | null = null): Promise<string> {
    const ctx: common.Context | null = resolveContext(context);
    if (!ctx) {
      return '';
    }
    return PreferencesUtil.getString(ctx, PreferencesUtil.KEY_CLIENT_TOKEN, '');
  }

  async setClientToken(context: common.Context | null, token: string): Promise<boolean> {
    const ctx: common.Context | null = resolveContext(context);
    if (!ctx) {
      return false;
    }
    return PreferencesUtil.putString(ctx, PreferencesUtil.KEY_CLIENT_TOKEN, token.trim());
  }

  // 拉取消息列表。device_key 来自 DeviceRegisterService，client token 来自持久化
  // 返回 MessageListResult：ok=false 时 errorMsg 含原因（未注册/未配置 token/网络失败/认证失败）
  async getMessages(context: common.Context | null = null): Promise<MessageListResult> {
    const result = new MessageListResult();
    const ctx: common.Context | null = resolveContext(context);

    const deviceKey: string | null = await DeviceRegisterService.getInstance().ensureRegistered(context);
    if (!deviceKey || deviceKey.length === 0) {
      result.errorMsg = '设备未注册';
      return result;
    }

    const clientToken: string = ctx ? await PreferencesUtil.getString(ctx, PreferencesUtil.KEY_CLIENT_TOKEN, '') : '';
    if (!clientToken || clientToken.length === 0) {
      result.errorMsg = '未配置客户端 Token';
      return result;
    }

    const base: string = ServerManager.getInstance().getCurrentBaseURL();
    const fullURL: string = `${base}/${deviceKey}/message`;
    hilog.info(DOMAIN, TAG, '拉取消息：GET %{public}s', fullURL);

    const headers: Record<string, string> = {
      'X-Gotify-Key': clientToken,
    };
    const resp: HttpResponse<GotifyMessageResponse> = await HttpUtil.get<GotifyMessageResponse>(fullURL, headers);

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

    // 顶层直接是 {paging, messages}，不走服务端统一 envelope
    result.messages = NotifyMessageService.extractMessages(resp.result as Object);
    result.ok = true;
    hilog.info(DOMAIN, TAG, '拉取成功，共 %{public}d 条', String(result.messages.length));
    return result;
  }

  // 从响应体解析消息列表，容错多种结构：
  // 1) 顶层是 {messages: [...]} → 解析 messages（gotify/timelynotify 标准格式）
  // 2) 顶层直接是数组 → 直接解析
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
}
