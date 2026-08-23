import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ApiConfig } from '../config/ApiConfig';
import { ServerManager } from './ServerManager';
import { HttpUtil, HttpResponse } from '../utils/HttpUtil';
import { PreferencesUtil } from '../utils/PreferencesUtil';

const DOMAIN: number = 0x0000;
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

// 注册请求体（首次：仅 device_token + platform）
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

  private isRegistering: boolean = false;

  static getInstance(): DeviceRegisterService {
    if (!DeviceRegisterService.instance) {
      DeviceRegisterService.instance = new DeviceRegisterService();
    }
    return DeviceRegisterService.instance;
  }

  setDeviceTokenProvider(provider: DeviceTokenProvider): void {
    this.tokenProvider = provider;
  }

  async ensureRegistered(context: common.Context): Promise<string | null> {
    const cachedKey = await PreferencesUtil.getString(context, PreferencesUtil.KEY_DEVICE_KEY, '');
    if (cachedKey && cachedKey.length > 0) {
      hilog.info(DOMAIN, TAG, '已注册，device_key 命中缓存：%{public}s', cachedKey);
      return cachedKey;
    }

    if (this.isRegistering) {
      hilog.info(DOMAIN, TAG, '注册中，等待其他任务完成…');
      return null;
    }
    this.isRegistering = true;

    try {
      const deviceToken = await this.tokenProvider();
      if (!deviceToken || deviceToken.length === 0) {
        hilog.error(DOMAIN, TAG, 'device_token 为空，中止注册');
        return null;
      }

      await PreferencesUtil.putString(context, PreferencesUtil.KEY_DEVICE_TOKEN, deviceToken);

      const req = new RegisterRequest();
      req.device_token = deviceToken;
      req.platform = ApiConfig.PLATFORM_HARMONY;

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
      const deviceKey: string = payload.device_key && payload.device_key.length > 0
        ? payload.device_key
        : payload.key;

      if (deviceKey && deviceKey.length > 0) {
        const ok: boolean = await PreferencesUtil.putString(context, PreferencesUtil.KEY_DEVICE_KEY, deviceKey);
        if (!ok) {
          hilog.warn(DOMAIN, TAG, '注册成功但 device_key 写入 Preferences 失败，device_key=%{public}s', deviceKey);
        } else {
          hilog.info(DOMAIN, TAG, '注册成功，device_key=%{public}s', deviceKey);
        }
        return deviceKey;
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
    } finally {
      this.isRegistering = false;
    }
  }

  async clearRegistration(context: common.Context): Promise<void> {
    await PreferencesUtil.delete(context, PreferencesUtil.KEY_DEVICE_KEY);
    await PreferencesUtil.delete(context, PreferencesUtil.KEY_DEVICE_TOKEN);
    hilog.info(DOMAIN, TAG, '本地注册信息已清除');
  }
}
