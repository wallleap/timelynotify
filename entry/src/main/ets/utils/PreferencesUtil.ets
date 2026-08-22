import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

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

export class PreferencesUtil {
  private static readonly STORE_NAME: string = 'timelynotify_prefs';
  private static instance: preferences.Preferences | null = null;

  static readonly KEY_DEVICE_KEY: string = 'device_key';
  static readonly KEY_DEVICE_TOKEN: string = 'device_token';

  private static async getStore(context: common.Context): Promise<preferences.Preferences | null> {
    if (!PreferencesUtil.instance) {
      try {
        PreferencesUtil.instance = await preferences.getPreferences(context, PreferencesUtil.STORE_NAME);
      } catch (err) {
        const msg: string = formatError(err);
        hilog.error(DOMAIN, TAG, 'getPreferences 失败：%{public}s', msg);
        return null;
      }
    }
    return PreferencesUtil.instance;
  }

  static async putString(context: common.Context, key: string, value: string): Promise<boolean> {
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
    context: common.Context,
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

  static async has(context: common.Context, key: string): Promise<boolean> {
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

  static async delete(context: common.Context, key: string): Promise<void> {
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
