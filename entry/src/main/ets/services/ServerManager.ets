import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ServerEntry } from '../model/ServerEntry';
import { ApiConfig } from '../config/ApiConfig';
import { AppContextStore } from '../common/AppContextStore';
import { PreferencesUtil } from '../utils/PreferencesUtil';
import { HttpResponse, HttpUtil } from '../utils/HttpUtil';
import { DeviceRegisterService } from './DeviceRegisterService';
import { DOMAIN } from '../common/Constant';

const TAG: string = 'ServerMgr';

// 解析 context：优先入参，否则回退全局
function resolveContext(ctx: common.Context | null): common.Context | null {
  if (ctx) {
    return ctx;
  }
  return AppContextStore.getInstance().getContext();
}

// 服务器列表序列化中间结构（JSON 友好）
class ServerEntryJson extends Object {
  id: string = '';
  name: string = '';
  baseURL: string = '';
  isBuiltIn: boolean = false;
  deviceKey: string = '';
  clientToken: string = '';
}

type ServerChangeListener = (list: ServerEntry[], currentId: string) => void;

function genId(): string {
  // 生成 12 位短 id（时间戳 + 随机）
  const ts: string = Date.now().toString(36);
  const rnd: string = Math.floor(Math.random() * 0xFFFFFF).toString(36).padStart(6, '0');
  return `${ts}${rnd}`;
}

function normalizeBaseURL(url: string): string {
  let u: string = url.trim();
  if (u.length === 0) {
    return '';
  }
  // 去末尾斜杠
  while (u.length > 0 && u[u.length - 1] === '/') {
    u = u.substring(0, u.length - 1);
  }
  // 缺少协议头时默认补 http://
  if (u.indexOf('://') < 0) {
    u = `http://${u}`;
  }
  return u;
}

// 验证 URL 是否是合法的 http/https 链接或域名
// 返回空字符串 = 合法；返回非空 = 错误信息
function validateURL(input: string): string {
  const trimmed: string = input.trim();
  if (trimmed.length === 0) {
    return '请输入服务器地址';
  }
  // 允许用户输入纯域名/IP/带端口/带路径，normalizeBaseURL 会补协议
  // 验证域名格式：支持 domain.com, IP, localhost, 带端口
  // 先去掉协议头再验证 host 部分
  let hostPart: string = trimmed;
  const protoEnd: number = hostPart.indexOf('://');
  if (protoEnd >= 0) {
    const proto: string = hostPart.substring(0, protoEnd);
    if (proto !== 'http' && proto !== 'https') {
      return '仅支持 http 或 https 协议';
    }
    hostPart = hostPart.substring(protoEnd + 3);
  }
  // 去掉路径
  const slashIdx: number = hostPart.indexOf('/');
  if (slashIdx >= 0) {
    hostPart = hostPart.substring(0, slashIdx);
  }
  // 去掉端口
  const colonIdx: number = hostPart.lastIndexOf(':');
  if (colonIdx >= 0) {
    const portStr: string = hostPart.substring(colonIdx + 1);
    const portNum: number = parseInt(portStr);
    if (isNaN(portNum) || portNum < 1 || portNum > 65535) {
      return '端口号无效';
    }
    hostPart = hostPart.substring(0, colonIdx);
  }
  if (hostPart.length === 0) {
    return '请输入服务器地址';
  }
  // 域名/IP 验证
  // 允许: 域名、IP、localhost
  const domainRegex = /^([a-zA-Z0-9]([a-zA-Z0-9\-]*[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$/;
  const ipRegex = /^(\d{1,3}\.){3}\d{1,3}$/;
  const localhostRegex = /^localhost$/;
  if (!domainRegex.test(hostPart) && !ipRegex.test(hostPart) && !localhostRegex.test(hostPart)) {
    return '请输入合法的域名或 IP 地址';
  }
  return '';
}

// Ping 响应结构
class PingResponse extends Object {
  code: number = 0;
  message: string = '';
  timestamp: number = 0;
}

export class ServerManager {
  private static instance: ServerManager | null = null;
  private static readonly KEY_DELETED_BUILTIN: string = 'server_deleted_builtin';
  // 内置 server 的 deviceKey 映射（id → key）。内置条目本身不持久化（跟随 ApiConfig 动态构造），
  // 但 deviceKey 必须跨启动保留，否则每次冷启动都会因 per-server key 为空而重置
  private static readonly KEY_BUILTIN_DEVICE_KEYS: string = 'server_builtin_device_keys';
  // 内置 server 的 clientToken 映射（id → token）。内置条目本身不持久化，
  // 但用户配置的 per-server client token 必须跨启动保留
  private static readonly KEY_BUILTIN_CLIENT_TOKENS: string = 'server_builtin_client_tokens';
  private servers: ServerEntry[] = [];
  private currentId: string = '';
  // 内置项：baseURL 不持久化、不缓存，每次获取都从 ApiConfig 动态取值，
  // 保证 ApiConfig.PROD_BASE_URL 修改后内置项地址立即跟随
  private deletedBuiltInIds: string[] = [];
  private listeners: ServerChangeListener[] = [];
  // 初始化 Promise：所有需要读取当前 server/baseURL 的入口都应先 await ensureLoaded()，
  // 避免与 load() 竞态导致读到空 currentId 走兜底生产 URL
  private ready: Promise<void> | null = null;
  private readyResolver: (() => void) | null = null;
  private loadingPromise: Promise<void> | null = null;
  private hasLoaded: boolean = false;

  private constructor() {
    this.ready = new Promise<void>((resolve) => {
      this.readyResolver = resolve;
    });
  }

  static getInstance(): ServerManager {
    if (!ServerManager.instance) {
      ServerManager.instance = new ServerManager();
    }
    return ServerManager.instance;
  }

  /**
   * 等待 ServerManager 完成首次 load()。
   * 所有需要读取当前 server/baseURL/hostDisplay 等状态的入口，
   * 在调用前 await 这个方法，避免与初始化竞态读到兜底值。
   * 已初始化后立即 resolve，不会阻塞。
   */
  async ensureLoaded(): Promise<void> {
    if (this.hasLoaded) {
      return;
    }
    if (this.ready) {
      await this.ready;
    }
  }

  addChangeListener(listener: ServerChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  removeChangeListener(listener: ServerChangeListener): void {
    const idx: number = this.listeners.indexOf(listener);
    if (idx >= 0) {
      this.listeners.splice(idx, 1);
    }
  }

  // 启动时调用：合并剩余内置 + 持久化自定义，恢复当前选中。幂等，重复调用安全。
  async load(context: common.Context | null = null): Promise<void> {
    // 幂等保护：已完成初始化直接返回（或等待进行中的完成）
    if (this.loadingPromise !== null) {
      await this.loadingPromise;
      return;
    }
    if (this.hasLoaded) {
      return;
    }
    // 先占坑，避免并发重入
    let localResolve: (() => void) | null = null;
    this.loadingPromise = new Promise<void>((res) => {
      localResolve = res;
    });

    try {
      const ctx: common.Context | null = resolveContext(context);

      // 1) 读取已删除的内置 id 列表
      const deletedRaw: string = await PreferencesUtil.getString(ctx, ServerManager.KEY_DELETED_BUILTIN, '');
      if (deletedRaw && deletedRaw.length > 0) {
        try {
          const arr: Object = JSON.parse(deletedRaw);
          if (arr instanceof Array) {
            this.deletedBuiltInIds = [];
            for (let i = 0; i < arr.length; i++) {
              if (typeof arr[i] === 'string') {
                this.deletedBuiltInIds.push(String(arr[i]));
              }
            }
          }
        } catch (err) {
          this.deletedBuiltInIds = [];
        }
      }

      // 2) 剩余内置 + 自定义（内置每次都用 getBuiltInServers() 动态构造，保证跟随 ApiConfig 变更）
      const builtIn: ServerEntry[] = this.getBuiltInServers();
      // 读取内置 server 的 deviceKey 映射并回填（内置条目本身不持久化，key 单独存）
      const builtinKeysRaw: string = await PreferencesUtil.getString(ctx, ServerManager.KEY_BUILTIN_DEVICE_KEYS, '');
      if (builtinKeysRaw && builtinKeysRaw.length > 0) {
        try {
          const keyMap = JSON.parse(builtinKeysRaw) as Record<string, Object>;
          for (let i = 0; i < builtIn.length; i++) {
            const b: ServerEntry = builtIn[i];
            const k: Object | undefined = keyMap[b.id];
            if (k && typeof k === 'string' && String(k).length > 0) {
              b.deviceKey = String(k);
            }
          }
        } catch (err) {
          hilog.warn(DOMAIN, TAG, '内置 server deviceKey 映射解析失败，忽略');
        }
      }
      // 读取内置 server 的 clientToken 映射并回填（与 deviceKey 同理，单独持久化）
      const builtinTokensRaw: string =
        await PreferencesUtil.getString(ctx, ServerManager.KEY_BUILTIN_CLIENT_TOKENS, '');
      if (builtinTokensRaw && builtinTokensRaw.length > 0) {
        try {
          const tokenMap = JSON.parse(builtinTokensRaw) as Record<string, Object>;
          for (let i = 0; i < builtIn.length; i++) {
            const b: ServerEntry = builtIn[i];
            const t: Object | undefined = tokenMap[b.id];
            if (t && typeof t === 'string' && String(t).length > 0) {
              b.clientToken = String(t);
            }
          }
        } catch (err) {
          hilog.warn(DOMAIN, TAG, '内置 server clientToken 映射解析失败，忽略');
        }
      }
      const list: ServerEntry[] = [];
      for (let i = 0; i < builtIn.length; i++) {
        const b: ServerEntry = builtIn[i];
        if (!this.isDeletedBuiltInId(b.id)) {
          list.push(b);
        }
      }
      const raw: string = await PreferencesUtil.getString(ctx, PreferencesUtil.KEY_SERVER_LIST_JSON, '');
      if (raw && raw.length > 0) {
        try {
          const arr: Object = JSON.parse(raw);
          if (arr instanceof Array) {
            for (let i = 0; i < arr.length; i++) {
              const obj = arr[i] as Record<string, Object>;
              if (!obj) {
                continue;
              }
              const id: string = typeof obj['id'] === 'string' ? String(obj['id']) : '';
              const name: string = typeof obj['name'] === 'string' ? String(obj['name']) : '';
              const baseURL: string = typeof obj['baseURL'] === 'string' ? String(obj['baseURL']) : '';
              const savedDeviceKey: string = typeof obj['deviceKey'] === 'string' ? String(obj['deviceKey']) : '';
              const savedClientToken: string =
                typeof obj['clientToken'] === 'string' ? String(obj['clientToken']) : '';
              if (id && baseURL) {
                list.push(new ServerEntry(id, name, normalizeBaseURL(baseURL), false, savedDeviceKey,
                  savedClientToken));
              }
            }
          }
        } catch (err) {
          hilog.warn(DOMAIN, TAG, '服务器列表反序列化失败，使用内置列表');
        }
      }

      this.servers = list;
      const savedId: string = await PreferencesUtil.getString(ctx, PreferencesUtil.KEY_SERVER_CURRENT_ID, '');
      if (savedId && this.findById(savedId)) {
        this.currentId = savedId;
      } else if (this.servers.length > 0) {
        this.currentId = this.servers[0].id;
      } else {
        this.currentId = '';
      }
      // 迁移：旧版全局 client_token → 当前 server 的 per-server clientToken
      // 旧版所有 server 共享一个全局 token，迁移到当前 server（用户正在使用的那个）；
      // 其余 server 留空走内置默认。迁移后清除全局 key，避免重复迁移
      const legacyGlobalToken: string =
        await PreferencesUtil.getString(ctx, PreferencesUtil.KEY_CLIENT_TOKEN, '');
      if (legacyGlobalToken && legacyGlobalToken.trim().length > 0) {
        const cur: ServerEntry | null = this.findById(this.currentId);
        if (cur && (!cur.clientToken || cur.clientToken.trim().length === 0)) {
          cur.clientToken = legacyGlobalToken.trim();
          hilog.info(DOMAIN, TAG, '迁移旧版全局 client_token 到当前 server：id=%{public}s', this.currentId);
          await this.persist(ctx);
        }
        // 无论是否写入 per-server，都清除旧全局 key（trim 后非空才算配置过，避免重复迁移）
        await PreferencesUtil.delete(ctx, PreferencesUtil.KEY_CLIENT_TOKEN);
        hilog.info(DOMAIN, TAG, '已清除旧版全局 client_token');
      }
      this.hasLoaded = true;
      hilog.info(
        DOMAIN,
        TAG,
        '服务器列表加载完成：总数=%{public}d 当前=%{public}s baseURL=%{public}s',
        String(this.servers.length),
        this.currentId,
        this.getCurrentBaseURL(),
      );
      this.emitChange();
    } finally {
      // resolve 两个 Promise：进行中的 load + ensureLoaded 等待者
      if (this.readyResolver) {
        this.readyResolver();
        this.readyResolver = null;
      }
      this.ready = null;
      if (localResolve) {
        localResolve();
      }
      this.loadingPromise = null;
    }
  }

  getList(): ServerEntry[] {
    return this.servers.slice();
  }

  getCurrentServer(): ServerEntry | null {
    return this.findById(this.currentId);
  }

  /** private isBuiltInId(id: string): boolean {
  const builtIn: ServerEntry[] = this.getBuiltInServers();
  for (let i = 0; i < builtIn.length; i++) {
  if (builtIn[i].id === id) {
  return true;
  }
  }
  return false;
  } */

  getCurrentBaseURL(): string {
    const cur = this.findById(this.currentId);
    if (cur) {
      // 内置项：强制用动态最新值，避免 ApiConfig 变更后持久化了的 old baseURL 被返回
      if (cur.isBuiltIn) {
        const fresh = this.getBuiltInServers().find((s) => s.id === cur.id);
        if (fresh) {
          return fresh.baseURL;
        }
      }
      return cur.baseURL;
    }
    // 兜底：生产（动态）
    const builtIn: ServerEntry[] = this.getBuiltInServers();
    return builtIn.length > 0 ? builtIn[0].baseURL : ApiConfig.PROD_BASE_URL;
  }

  // 则内联触发一次 syncKeyForServer 拿到 key 再返回。
  async getCurrentDeviceKey(context: common.Context | null = null): Promise<string> {
    await this.ensureLoaded();
    const cur: ServerEntry | null = this.getCurrentServer();
    if (!cur) {
      hilog.warn(DOMAIN, TAG, 'getCurrentDeviceKey：无当前 server');
      return '';
    }
    if (cur.deviceKey && cur.deviceKey.length > 0) {
      hilog.info(DOMAIN, TAG, 'getCurrentDeviceKey：使用 per-server key');
      return cur.deviceKey;
    }
    // per-server 为空：内联触发 syncKeyForServer（验证/还原/重置）
    hilog.info(DOMAIN, TAG, 'getCurrentDeviceKey：per-server key 为空，内联 syncKeyForServer');
    const baseURL: string = this.getCurrentBaseURL();
    const key: string | null = await DeviceRegisterService.getInstance().syncKeyForServer(
      context, cur.id, baseURL, cur.deviceKey
    );
    return key ?? '';
  }

  // 更新指定 server 的 device_key 并持久化。context 可传 null
  async updateServerDeviceKey(context: common.Context | null, serverId: string, deviceKey: string): Promise<void> {
    const ctx: common.Context | null = resolveContext(context);
    const entry: ServerEntry | null = this.findById(serverId);
    if (entry) {
      entry.deviceKey = deviceKey;
      await this.persist(ctx);
      hilog.info(DOMAIN, TAG, '已更新 device_key：serverId=%{public}s key=%{public}s', serverId, deviceKey);
    }
  }

  // 获取当前 server 用户配置的 client token（不含内置默认；空串 = 用户未配置，调用方应回退默认）
  getCurrentClientToken(): string {
    const cur: ServerEntry | null = this.findById(this.currentId);
    return cur ? cur.clientToken : '';
  }

  // 更新指定 server 的 client token 并持久化。空串 = 清除自定义（恢复内置默认）。context 可传 null
  async updateServerClientToken(context: common.Context | null, serverId: string,
    clientToken: string): Promise<void> {
    const ctx: common.Context | null = resolveContext(context);
    const entry: ServerEntry | null = this.findById(serverId);
    if (entry) {
      entry.clientToken = clientToken;
      await this.persist(ctx);
      hilog.info(DOMAIN, TAG, '已更新 client_token：serverId=%{public}s', serverId);
    }
  }

  // 给页面显示用：host[:port] 短名
  getCurrentHostDisplay(): string {
    const url: string = this.getCurrentBaseURL();
    let s: string = url;
    const protoEnd: number = s.indexOf('://');
    if (protoEnd >= 0) {
      s = s.substring(protoEnd + 3);
    }
    const slashIdx: number = s.indexOf('/');
    if (slashIdx >= 0) {
      s = s.substring(0, slashIdx);
    }
    return s;
  }

  // 拼接完整请求 URL（baseURL + path）
  resolveURL(path: string): string {
    const base: string = this.getCurrentBaseURL();
    if (!path || path.length === 0) {
      return base;
    }
    if (path.indexOf('://') >= 0) {
      return path;
    }
    const p: string = path[0] === '/' ? path : `/${path}`;
    return `${base}${p}`;
  }

  // 切换到指定 id 的服务器；返回 true 表示已切换并持久化。context 可传 null
  async switchTo(context: common.Context | null, id: string): Promise<boolean> {
    const ctx: common.Context | null = resolveContext(context);
    const server = this.findById(id);
    if (!server) {
      hilog.warn(DOMAIN, TAG, 'switchTo 目标不存在 id=%{public}s', id);
      return false;
    }
    if (this.currentId === id) {
      return true;
    }
    this.currentId = id;
    await this.persist(ctx);
    hilog.info(DOMAIN, TAG, '已切换服务器：id=%{public}s url=%{public}s', server.id, server.baseURL);
    this.emitChange();
    // 切换后异步验证/还原 device_key，不阻塞返回
    this.syncKeyForServerAsync(ctx, id);
    return true;
  }

  // 验证 URL 并 ping 服务器。返回空字符串 = OK；返回非空 = 错误信息
  async validateAndPing(rawURL: string): Promise<string> {
    const errMsg: string = validateURL(rawURL);
    if (errMsg.length > 0) {
      return errMsg;
    }
    const normalized: string = normalizeBaseURL(rawURL);
    const pingURL: string = `${normalized}/ping`;
    hilog.info(DOMAIN, TAG, '正在 ping：%{public}s', pingURL);
    const resp: HttpResponse<PingResponse> = await HttpUtil.get<PingResponse>(pingURL);
    if (resp.code !== 200) {
      return `服务器无响应（HTTP ${resp.code}）`;
    }
    if (!resp.result) {
      return '服务器返回格式无效';
    }
    const pingResp: PingResponse = resp.result as PingResponse;
    if (pingResp.code !== 200) {
      return `服务器返回错误（code=${pingResp.code}）`;
    }
    if (pingResp.message !== 'pong') {
      return `服务器响应异常（message=${pingResp.message}）`;
    }
    hilog.info(DOMAIN, TAG, 'ping 成功：%{public}s', pingURL);
    return '';
  }

  // 获取当前 server 应使用的 device_key：只认 per-server 保存的 deviceKey。
  // 若 per-server 为空，说明 syncKeyForServer 还没跑（如刚切 server 或首次使用），

  // 新增自定义服务器（URL 已存在则只切过去）。返回新条目/命中条目。context 可传 null
  async addServer(context: common.Context | null, rawURL: string, name: string): Promise<ServerEntry | null> {
    const ctx: common.Context | null = resolveContext(context);
    const normalized: string = normalizeBaseURL(rawURL);
    if (!normalized) {
      return null;
    }
    const existed: ServerEntry | null = this.findByBaseURL(normalized);
    if (existed) {
      await this.switchTo(ctx, existed.id);
      return existed;
    }
    const id: string = genId();
    const entry = new ServerEntry(id, name ? name.trim() : '', normalized, false);
    this.servers.push(entry);
    this.currentId = id;
    await this.persist(ctx);
    hilog.info(DOMAIN, TAG, '新增服务器：id=%{public}s url=%{public}s', entry.id, entry.baseURL);
    this.emitChange();
    return entry;
  }

  // 删除服务器（含内置）。不能删到 0 个，至少保留一个。context 可传 null
  async deleteServer(context: common.Context | null, id: string): Promise<boolean> {
    const ctx: common.Context | null = resolveContext(context);
    const target: ServerEntry | null = this.findById(id);
    if (!target) {
      return false;
    }
    if (this.servers.length <= 1) {
      hilog.warn(DOMAIN, TAG, '至少保留一个服务器，拒绝删除 id=%{public}s', id);
      return false;
    }
    const idx: number = this.servers.indexOf(target);
    if (idx < 0) {
      return false;
    }
    this.servers.splice(idx, 1);
    // 内置服务器：记录到删除列表，重启后不会重新出现
    if (target.isBuiltIn) {
      this.deletedBuiltInIds.push(id);
    }
    if (this.currentId === id) {
      this.currentId = this.servers[0].id;
      hilog.info(DOMAIN, TAG, '删除的是当前服务器，已回退到：%{public}s', this.currentId);
    }
    await this.persist(ctx);
    this.emitChange();
    return true;
  }

  // 重命名服务器。context 可传 null
  async renameServer(context: common.Context | null, id: string, newName: string): Promise<boolean> {
    const ctx: common.Context | null = resolveContext(context);
    const target: ServerEntry | null = this.findById(id);
    if (!target) {
      return false;
    }
    const name: string = newName.trim();
    target.name = name;
    await this.persist(ctx);
    hilog.info(DOMAIN, TAG, '已重命名：id=%{public}s name=%{public}s', id, name);
    this.emitChange();
    return true;
  }

  // 内置项定义与工厂：每次调用都用 ApiConfig 当前值，避免编译期固化
  private getBuiltInServers(): ServerEntry[] {
    const prod = new ServerEntry(
      'builtin-prod',
      '默认服务',
      normalizeBaseURL(ApiConfig.PROD_BASE_URL),
      true,
    );
    return [prod];
  }

  private emitChange(): void {
    const snapshot: ServerEntry[] = this.getList();
    for (let i = 0; i < this.listeners.length; i++) {
      try {
        this.listeners[i](snapshot, this.currentId);
      } catch (err) {
        hilog.warn(DOMAIN, TAG, 'listener 调用失败');
      }
    }
  }

  private isDeletedBuiltInId(id: string): boolean {
    for (let i = 0; i < this.deletedBuiltInIds.length; i++) {
      if (this.deletedBuiltInIds[i] === id) {
        return true;
      }
    }
    return false;
  }

  private async persist(context: common.Context | null): Promise<void> {
    const ctx: common.Context | null = resolveContext(context);
    // 持久化自定义（非内置）条目
    const customs: ServerEntryJson[] = [];
    for (let i = 0; i < this.servers.length; i++) {
      const s: ServerEntry = this.servers[i];
      if (!s.isBuiltIn) {
        const j = new ServerEntryJson();
        j.id = s.id;
        j.name = s.name;
        j.baseURL = s.baseURL;
        j.isBuiltIn = false;
        j.deviceKey = s.deviceKey;
        j.clientToken = s.clientToken;
        customs.push(j);
      }
    }
    await PreferencesUtil.putString(ctx, PreferencesUtil.KEY_SERVER_LIST_JSON, JSON.stringify(customs));
    await PreferencesUtil.putString(ctx, PreferencesUtil.KEY_SERVER_CURRENT_ID, this.currentId);
    // 持久化内置 server 的 deviceKey 映射（仅非空项）
    const builtinKeys: Record<string, string> = {};
    for (let i = 0; i < this.servers.length; i++) {
      const s: ServerEntry = this.servers[i];
      if (s.isBuiltIn && s.deviceKey && s.deviceKey.length > 0) {
        builtinKeys[s.id] = s.deviceKey;
      }
    }
    await PreferencesUtil.putString(ctx, ServerManager.KEY_BUILTIN_DEVICE_KEYS, JSON.stringify(builtinKeys));
    // 持久化内置 server 的 clientToken 映射（仅非空项）
    const builtinTokens: Record<string, string> = {};
    for (let i = 0; i < this.servers.length; i++) {
      const s: ServerEntry = this.servers[i];
      if (s.isBuiltIn && s.clientToken && s.clientToken.length > 0) {
        builtinTokens[s.id] = s.clientToken;
      }
    }
    await PreferencesUtil.putString(ctx, ServerManager.KEY_BUILTIN_CLIENT_TOKENS, JSON.stringify(builtinTokens));
    // 持久化已删除的内置 id 列表
    await PreferencesUtil.putString(ctx, ServerManager.KEY_DELETED_BUILTIN, JSON.stringify(this.deletedBuiltInIds));
  }

  private findById(id: string): ServerEntry | null {
    for (let i = 0; i < this.servers.length; i++) {
      if (this.servers[i].id === id) {
        return this.servers[i];
      }
    }
    return null;
  }

  private findByBaseURL(baseURL: string): ServerEntry | null {
    const normalized: string = normalizeBaseURL(baseURL);
    for (let i = 0; i < this.servers.length; i++) {
      if (this.servers[i].baseURL === normalized) {
        return this.servers[i];
      }
    }
    return null;
  }

  private syncKeyForServerAsync(ctx: common.Context | null, serverId: string): void {
    const server: ServerEntry | null = this.findById(serverId);
    if (!server) {
      return;
    }
    DeviceRegisterService.getInstance().syncKeyForServer(
      ctx, serverId, this.getCurrentBaseURL(), server.deviceKey
    ).then((key: string | null) => {
      hilog.info(DOMAIN, TAG, 'switchTo syncKeyForServer 完成：key=%{public}s', key ?? 'null');
    }).catch((err: Error) => {
      hilog.warn(DOMAIN, TAG, 'switchTo syncKeyForServer 异常：%{public}s', err.message);
    });
  }
}
