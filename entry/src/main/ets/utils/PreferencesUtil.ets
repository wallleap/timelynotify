import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppContextStore } from '../common/AppContextStore';

const DOMAIN: number = 0x0000;
const TAG: string = 'PrefsUtil';

function formatError(err: Object): string {
  if (err instanceof Error) {
    return err.message;
  }
  if (typeof err === 'object') {
    const anyErr = err as Record<string, Object>;
    const parts: string[] = [];
    if (anyErr['code'] !== undefined && anyErr['code'] !== null) {
      parts.push(`code=${String(anyErr['code'])}`);
    }
    if (anyErr['message'] !== undefined && anyErr['message'] !== null) {
      parts.push(`message=${String(anyErr['message'])}`);
    }
    if (parts.length > 0) {
      const all: string = parts.join(' ');
      return all;
    }
    try {
      return JSON.stringify(err);
    } catch (_ignore) {
      return String(err);
    }
  }
  return String(err);
}

// 解析 context：优先入参（组件传入时最准），否则回退全局 AppContextStore
function resolveContext(ctx: common.Context | null): common.Context | null {
  if (ctx) {
    return ctx;
  }
  return AppContextStore.getInstance().getContext();
}

export class PreferencesUtil {
  private static readonly STORE_NAME: string = 'timelynotify_prefs';
  private static instance: preferences.Preferences | null = null;

  static readonly KEY_DEVICE_KEY: string = 'device_key';
  static readonly KEY_DEVICE_TOKEN: string = 'device_token';
  static readonly KEY_SERVER_LIST_JSON: string = 'server_list_json';
  static readonly KEY_SERVER_CURRENT_ID: string = 'server_current_id';

  private static async getStore(context: common.Context | null): Promise<preferences.Preferences | null> {
    const ctx: common.Context | null = resolveContext(context);
    if (!ctx) {
      hilog.error(DOMAIN, TAG, 'getStore 无法获取 context');
      return null;
    }
    if (!PreferencesUtil.instance) {
      try {
        PreferencesUtil.instance = await preferences.getPreferences(ctx, PreferencesUtil.STORE_NAME);
      } catch (err) {
        const msg: string = formatError(err);
        hilog.error(DOMAIN, TAG, 'getPreferences 失败：%{public}s', msg);
        return null;
      }
    }
    return PreferencesUtil.instance;
  }

  static async putString(context: common.Context | null, key: string, value: string): Promise<boolean> {
    const store = await PreferencesUtil.getStore(context);
    if (!store) {
      return false;
    }
    try {
      await store.put(key, value);
      await store.flush();
      return true;
    } catch (err) {
      const msg: string = formatError(err);
      hilog.error(DOMAIN, TAG, 'putString 失败 key=%{public}s：%{public}s', key, msg);
      return false;
    }
  }

  static async getString(
    context: common.Context | null,
    key: string,
    defaultValue: string = ''
  ): Promise<string> {
    const store = await PreferencesUtil.getStore(context);
    if (!store) {
      return defaultValue;
    }
    try {
      const value: Object = await store.get(key, defaultValue);
      if (typeof value === 'string') {
        return value;
      }
      return String(value);
    } catch (err) {
      const msg: string = formatError(err);
      hilog.error(DOMAIN, TAG, 'getString 失败 key=%{public}s：%{public}s', key, msg);
      return defaultValue;
    }
  }

  static async has(context: common.Context | null, key: string): Promise<boolean> {
    const store = await PreferencesUtil.getStore(context);
    if (!store) {
      return false;
    }
    try {
      return await store.has(key);
    } catch (err) {
      const msg: string = formatError(err);
      hilog.error(DOMAIN, TAG, 'has 失败 key=%{public}s：%{public}s', key, msg);
      return false;
    }
  }

  static async delete(context: common.Context | null, key: string): Promise<void> {
    const store = await PreferencesUtil.getStore(context);
    if (!store) {
      return;
    }
    try {
      await store.delete(key);
      await store.flush();
    } catch (err) {
      const msg: string = formatError(err);
      hilog.error(DOMAIN, TAG, 'delete 失败 key=%{public}s：%{public}s', key, msg);
    }
  }
}
