import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ApiConfig } from '../config/ApiConfig';
import { ServerManager } from './ServerManager';
import { ServerEntry } from '../model/ServerEntry';
import { HttpResponse, HttpUtil } from '../utils/HttpUtil';
import { PreferencesUtil } from '../utils/PreferencesUtil';
import { AppContextStore } from '../common/AppContextStore';
import { DOMAIN } from '../common/Constant';

const TAG: string = 'DeviceRegister';

// 服务端统一返回格式：{code, message, data, timestamp}
export class RegisterPayload extends Object {
  device_token: string = '';
  platform: string = '';
  key: string = '';
  device_key: string = '';
}

export class RegisterEnvelope extends Object {
  code: number = 0;
  message: string = '';
  data: RegisterPayload | null = null;
  timestamp: number = 0;
}

// 注册请求体（首次：仅 device_token + platform；还原：带 device_key）
export class RegisterRequest extends Object {
  device_token: string = '';
  platform: string = '';
  device_key?: string;
}

// 华为 Push Token 获取回调类型
export type DeviceTokenProvider = () => Promise<string>;

export class DeviceRegisterService {
  private static instance: DeviceRegisterService | null = null;
  private tokenProvider: DeviceTokenProvider = async (): Promise<string> => {
    hilog.warn(DOMAIN, TAG, '未注入真实的 Push Token Provider，使用占位 token，请接入华为 Push Kit 后替换');
    return 'placeholder-device-token-pending-pushkit';
  };
  // 当前正在进行的注册任务（null = 无任务在跑）。并发调用 ensureRegistered 共享同一 promise，
  // 避免重复触发 PushKit getToken 与注册接口；UI 可通过 whenRegistrationSettled() 等待完成。
  private pendingPromise: Promise<string | null> | null = null;

  static getInstance(): DeviceRegisterService {
    if (!DeviceRegisterService.instance) {
      DeviceRegisterService.instance = new DeviceRegisterService();
    }
    return DeviceRegisterService.instance;
  }

  setDeviceTokenProvider(provider: DeviceTokenProvider): void {
    this.tokenProvider = provider;
  }

  // 并发调用会共享同一个 pendingPromise，避免重复触发 PushKit getToken 和注册接口
  async ensureRegistered(context: common.Context | null = null): Promise<string | null> {
    const ctx: common.Context | null = this.resolveContext(context);
    if (!ctx) {
      return null;
    }
    const cachedKey: string = await PreferencesUtil.getString(ctx, PreferencesUtil.KEY_DEVICE_KEY, '');
    if (cachedKey && cachedKey.length > 0) {
      hilog.info(DOMAIN, TAG, '已注册，device_key 命中缓存：%{public}s', cachedKey);
      return cachedKey;
    }
    if (this.pendingPromise) {
      hilog.info(DOMAIN, TAG, '注册任务进行中，复用 pending promise');
      return this.pendingPromise;
    }
    this.pendingPromise = this.doRegister(ctx, undefined);
    try {
      return await this.pendingPromise;
    } finally {
      this.pendingPromise = null;
    }
  }

  // 已注册则直接返回缓存的 device_key；否则注册。context 可传 null

  // 用于 UI（如 MineView）在首次显示前等待 PushKit token 写盘完成。
  async whenRegistrationSettled(): Promise<void> {
    if (!this.pendingPromise) {
      return;
    }
    try {
      await this.pendingPromise;
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, TAG, 'whenRegistrationSettled 等待异常：%{public}s', msg);
    }
  }

  // 等待当前注册任务完成（如有）。无任务在跑时立即返回；不会主动触发注册。

  // 读取已持久化的 device_key（仅读缓存，不触发注册；未注册时返回空串）
  async getDeviceKey(context: common.Context | null = null): Promise<string> {
    const ctx: common.Context | null = this.resolveContext(context);
    if (!ctx) {
      return '';
    }
    return PreferencesUtil.getString(ctx, PreferencesUtil.KEY_DEVICE_KEY, '');
  }

  // 读取已持久化的 device_token（Push 推送 token；未取到时返回空串）
  async getDeviceToken(context: common.Context | null = null): Promise<string> {
    const ctx: common.Context | null = this.resolveContext(context);
    if (!ctx) {
      return '';
    }
    return PreferencesUtil.getString(ctx, PreferencesUtil.KEY_DEVICE_TOKEN, '');
  }

  // 强制重新注册。deviceKey 为空 = 重置（生成新 key）；有值 = 还原（关联已有 device_key）。context 可传 null
  async register(context: common.Context | null, deviceKey?: string): Promise<string | null> {
    const ctx: common.Context | null = this.resolveContext(context);
    if (!ctx) {
      return null;
    }
    return this.doRegister(ctx, deviceKey);
  }

  // 返回 true 表示 token 发生过变更并已触发重绑。
  async refreshTokenIfNeeded(context: common.Context | null = null): Promise<boolean> {
    const ctx: common.Context | null = this.resolveContext(context);
    if (!ctx) {
      return false;
    }
    let freshToken: string = '';
    try {
      freshToken = await this.tokenProvider();
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'refreshTokenIfNeeded：获取最新 token 异常：%{public}s', String(err));
      return false;
    }
    if (!freshToken || freshToken.length === 0) {
      hilog.warn(DOMAIN, TAG, 'refreshTokenIfNeeded：最新 token 为空，跳过检测');
      return false;
    }
    const cached: string = await PreferencesUtil.getString(ctx, PreferencesUtil.KEY_DEVICE_TOKEN, '');
    if (freshToken === cached) {
      return false;
    }
    hilog.info(DOMAIN, TAG, 'refreshTokenIfNeeded：检测到 device_token 变更，更新缓存并重绑各 server');
    await PreferencesUtil.putString(ctx, PreferencesUtil.KEY_DEVICE_TOKEN, freshToken);

    // 对所有已保存 deviceKey 的 server 逐个还原（新 token + 旧 device_key）
    try {
      await ServerManager.getInstance().ensureLoaded();
      const servers: ServerEntry[] = ServerManager.getInstance().getList();
      for (let i = 0; i < servers.length; i++) {
        const s: ServerEntry = servers[i];
        if (!s.deviceKey || s.deviceKey.length === 0) {
          continue;
        }
        try {
          const k: string | null = await this.doRegisterWithBaseURL(s.baseURL, s.deviceKey);
          hilog.info(
            DOMAIN, TAG,
            'refreshTokenIfNeeded：重绑 server=%{public}s 结果=%{public}s',
            s.baseURL, k ? '成功' : '失败'
          );
        } catch (err) {
          hilog.warn(DOMAIN, TAG, 'refreshTokenIfNeeded：重绑 server=%{public}s 异常：%{public}s', s.baseURL,
            String(err));
        }
      }
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'refreshTokenIfNeeded：重绑流程异常：%{public}s', String(err));
    }
    return true;
  }

  // 最终将获得的 deviceKey 回写到 ServerManager 持久化
  async syncKeyForServer(context: common.Context | null, serverId: string, baseURL: string,
    savedDeviceKey: string): Promise<string | null> {
    const ctx: common.Context | null = this.resolveContext(context);
    let finalKey: string | null = null;

    if (savedDeviceKey && savedDeviceKey.length > 0) {
      // 1) 先验证保存的 key 是否有效
      const valid: boolean = await this.verifyKey(baseURL, savedDeviceKey);
      if (valid) {
        finalKey = savedDeviceKey;
        hilog.info(DOMAIN, TAG, 'syncKeyForServer：保存的 key 有效，直接使用，无需调接口');
      } else {
        // 2) 无效 → 还原（三参数：device_token + platform + device_key）
        hilog.info(DOMAIN, TAG, 'syncKeyForServer：保存的 key 无效，尝试还原');
        finalKey = await this.doRegisterWithBaseURL(baseURL, savedDeviceKey);
        if (!finalKey) {
          hilog.warn(DOMAIN, TAG, 'syncKeyForServer：还原失败，保留原 key 不再重置');
        }
      }
    } else {
      // 3) 没有保存的 key → 重置（不传 device_key，让服务端生成新的）
      hilog.info(DOMAIN, TAG, 'syncKeyForServer：该 server 无保存 key，重置生成新的');
      finalKey = await this.doRegisterWithBaseURL(baseURL, undefined);
    }

    // 无论哪个分支拿到 key，都回写到 ServerManager 持久化
    if (finalKey && finalKey.length > 0) {
      try {
        await ServerManager.getInstance().updateServerDeviceKey(ctx, serverId, finalKey);
      } catch (err) {
        hilog.warn(DOMAIN, TAG, 'syncKeyForServer：回写 per-server deviceKey 失败：%{public}s', String(err));
      }
      // 同步写全局缓存（向后兼容 getCurrentDeviceKey 的全局兜底）
      if (ctx) {
        await PreferencesUtil.putString(ctx, PreferencesUtil.KEY_DEVICE_KEY, finalKey);
      }
    }
    return finalKey;
  }

  async clearRegistration(context: common.Context | null = null): Promise<void> {
    const ctx: common.Context | null = this.resolveContext(context);
    if (!ctx) {
      return;
    }
    await PreferencesUtil.delete(ctx, PreferencesUtil.KEY_DEVICE_KEY);
    await PreferencesUtil.delete(ctx, PreferencesUtil.KEY_DEVICE_TOKEN);
    hilog.info(DOMAIN, TAG, '本地注册信息已清除');
  }

  // 启动时检测 Push token 是否变更：
  // 每次启动都调用 tokenProvider 获取最新 token，与缓存比对。
  // 若变更：更新缓存，并对所有已保存 deviceKey 的 server 逐个"还原"注册，
  // 把新 token 与已有 device_key 重新绑定（否则推送会静默失效）。

  // 解析 context：优先入参，否则回退全局 AppContextStore（与 ServerManager 一致）
  private resolveContext(ctx: common.Context | null): common.Context | null {
    if (ctx) {
      return ctx;
    }
    return AppContextStore.getInstance().getContext();
  }

  // 同步指定 server 的 device_key：
  // 1) 有 per-server 保存的 deviceKey → 先验证，有效则用；无效则还原（三参数）
  // 2) 没有保存的 deviceKey → 重新注册（不传 device_key）

  private async doRegister(ctx: common.Context, deviceKey?: string): Promise<string | null> {
    try {
      // device_token：优先用缓存，否则从 provider 获取并落盘
      let deviceToken: string = await PreferencesUtil.getString(ctx, PreferencesUtil.KEY_DEVICE_TOKEN, '');
      if (!deviceToken || deviceToken.length === 0) {
        deviceToken = await this.tokenProvider();
        if (deviceToken && deviceToken.length > 0) {
          await PreferencesUtil.putString(ctx, PreferencesUtil.KEY_DEVICE_TOKEN, deviceToken);
        }
      }
      if (!deviceToken || deviceToken.length === 0) {
        hilog.error(DOMAIN, TAG, 'device_token 为空，中止注册');
        return null;
      }

      const req = new RegisterRequest();
      req.device_token = deviceToken;
      req.platform = ApiConfig.PLATFORM_HARMONY;
      if (deviceKey && deviceKey.length > 0) {
        req.device_key = deviceKey;
      }

      // 保证 ServerManager 初始化完成再拼 URL，避免读到兜底生产 URL
      await ServerManager.getInstance().ensureLoaded();
      const fullURL: string = ServerManager.getInstance().resolveURL(ApiConfig.REGISTER_PATH);
      hilog.info(DOMAIN, TAG, '开始注册：POST %{public}s', fullURL);
      const resp: HttpResponse<RegisterEnvelope> = await HttpUtil.post<RegisterEnvelope, RegisterRequest>(
        fullURL,
        req,
      );

      // 第一层：网络/HTTP 层是否成功
      if (!(resp.code >= 200 && resp.code < 300)) {
        hilog.error(DOMAIN, TAG, '注册失败（HTTP 层）：httpCode=%{public}d msg=%{public}s', resp.code, resp.message);
        return null;
      }
      if (!resp.result) {
        hilog.error(DOMAIN, TAG, '注册失败（HTTP 200 但响应体为空）');
        return null;
      }

      const envelope: RegisterEnvelope = resp.result;

      // 第二层：业务层 code 是否成功
      if (envelope.code !== 200) {
        hilog.error(
          DOMAIN,
          TAG,
          '注册失败（业务层）：bizCode=%{public}d bizMsg=%{public}s',
          envelope.code,
          envelope.message,
        );
        return null;
      }
      if (!envelope.data) {
        hilog.warn(DOMAIN, TAG, '注册响应业务成功但 data 为空');
        return null;
      }

      const payload: RegisterPayload = envelope.data;
      // 服务端同时返回 device_key 与 key（同名同义），优先取 device_key，兼容取 key
      const newDeviceKey: string = payload.device_key && payload.device_key.length > 0
        ? payload.device_key
        : payload.key;

      if (deviceKey && deviceKey.length > 0) {
        hilog.info(DOMAIN, TAG, '还原 key 已提交，服务端返回 device_key=%{public}s', newDeviceKey);
      } else {
        hilog.info(DOMAIN, TAG, '重置完成，新 device_key=%{public}s', newDeviceKey);
      }

      if (newDeviceKey && newDeviceKey.length > 0) {
        // 1) 写全局缓存（ensureRegistered 的 cache-hit 仍需，且 getCurrentDeviceKey 会兜底回退）
        await PreferencesUtil.putString(ctx, PreferencesUtil.KEY_DEVICE_KEY, newDeviceKey);
        // 2) 同步写 per-server（当前 server），这才是真正的权威数据源
        try {
          const mgr = ServerManager.getInstance();
          await mgr.ensureLoaded();
          const cur = mgr.getCurrentServer();
          if (cur) {
            await mgr.updateServerDeviceKey(ctx, cur.id, newDeviceKey);
            hilog.info(DOMAIN, TAG, 'doRegister：已同步 per-server deviceKey');
          }
        } catch (err) {
          hilog.warn(DOMAIN, TAG, 'doRegister：同步 per-server deviceKey 异常：%{public}s', String(err));
        }
        return newDeviceKey;
      } else {
        hilog.warn(DOMAIN, TAG, '注册响应业务成功但 data 中 device_key/key 均为空');
        return null;
      }
    } catch (err) {
      if (err instanceof Error) {
        hilog.error(DOMAIN, TAG, '注册异常：%{public}s', err.message);
      } else {
        hilog.error(DOMAIN, TAG, '注册异常：%{public}s', String(err));
      }
      return null;
    }
  }

  // 验证指定 device_key 在给定 baseURL 的服务器上是否有效
  private async verifyKey(baseURL: string, deviceKey: string): Promise<boolean> {
    if (!deviceKey || deviceKey.length === 0) {
      return false;
    }
    const verifyURL: string = `${baseURL}/register/${deviceKey}`;
    try {
      const resp: HttpResponse<RegisterEnvelope> = await HttpUtil.get<RegisterEnvelope>(verifyURL);
      // HTTP 200 且业务 code 200 → key 存在
      if (resp.code === 200 && resp.result && resp.result.code === 200) {
        hilog.info(DOMAIN, TAG, 'device_key 验证通过：%{public}s', deviceKey);
        return true;
      }
      hilog.warn(
        DOMAIN, TAG,
        'device_key 验证失败：httpCode=%{public}d bizCode=%{public}d',
        resp.code, resp.result ? resp.result.code : -1
      );
      return false;
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'device_key 验证异常：%{public}s', String(err));
      return false;
    }
  }

  // 带指定 baseURL 的注册（原 doRegister 硬编码用 ServerManager 全局 URL，这里直接用入参）
  private async doRegisterWithBaseURL(baseURL: string, deviceKey?: string): Promise<string | null> {
    try {
      let deviceToken: string = await PreferencesUtil.getString(
        this.resolveContext(null) as common.Context, PreferencesUtil.KEY_DEVICE_TOKEN, ''
      );
      if (!deviceToken || deviceToken.length === 0) {
        deviceToken = await this.tokenProvider();
        if (deviceToken && deviceToken.length > 0) {
          await PreferencesUtil.putString(
            this.resolveContext(null) as common.Context, PreferencesUtil.KEY_DEVICE_TOKEN, deviceToken
          );
        }
      }
      if (!deviceToken || deviceToken.length === 0) {
        hilog.error(DOMAIN, TAG, 'doRegisterWithBaseURL：device_token 为空，中止注册');
        return null;
      }

      const req = new RegisterRequest();
      req.device_token = deviceToken;
      req.platform = ApiConfig.PLATFORM_HARMONY;
      if (deviceKey && deviceKey.length > 0) {
        req.device_key = deviceKey;
      }

      const fullURL: string = `${baseURL}${ApiConfig.REGISTER_PATH}`;
      hilog.info(DOMAIN, TAG, 'doRegisterWithBaseURL：POST %{public}s', fullURL);
      const resp: HttpResponse<RegisterEnvelope> = await HttpUtil.post<RegisterEnvelope, RegisterRequest>(
        fullURL, req
      );

      if (!(resp.code >= 200 && resp.code < 300) || !resp.result || resp.result.code !== 200 || !resp.result.data) {
        hilog.error(DOMAIN, TAG, 'doRegisterWithBaseURL 注册失败：%{public}s', JSON.stringify(resp));
        return null;
      }

      const payload: RegisterPayload = resp.result.data;
      const newDeviceKey: string = payload.device_key && payload.device_key.length > 0
        ? payload.device_key : payload.key;
      if (newDeviceKey && newDeviceKey.length > 0) {
        // 不再写全局 KEY_DEVICE_KEY，由调用方 syncKeyForServer 回写 per-server
        hilog.info(DOMAIN, TAG, 'doRegisterWithBaseURL：完成，device_key=%{public}s', newDeviceKey);
        return newDeviceKey;
      }
      return null;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'doRegisterWithBaseURL 异常：%{public}s', String(err));
      return null;
    }
  }
}
