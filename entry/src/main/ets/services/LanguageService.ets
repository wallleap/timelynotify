import { i18n } from '@kit.LocalizationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { PreferencesUtil } from '../utils/PreferencesUtil';
import { AppContextStore } from '../common/AppContextStore';
import { DOMAIN } from '../common/Constant';

const TAG: string = 'LanguageService';

/**
 * 应用内语言设置服务。
 * 'default' 跟随系统语言（切换后需重启应用生效）；
 * 'zh-Hans' / 'en-US' 为应用偏好语言，设置后立即生效且不影响系统语言。
 */
export class LanguageService {
  /** 偏好存储键；值为 'default' | 'zh-Hans' | 'en-US'。 */
  static readonly KEY_APP_LANGUAGE: string = 'app_language';
  /** 跟随系统语言 */
  static readonly LANG_FOLLOW_SYSTEM: string = 'default';
  /** 简体中文 */
  static readonly LANG_ZH_HANS: string = 'zh-Hans';
  /** 英语 */
  static readonly LANG_EN_US: string = 'en-US';

  /** 读取持久化的语言设置，缺失时返回跟随系统。 */
  static async getSavedLanguage(): Promise<string> {
    return PreferencesUtil.getString(AppContextStore.getInstance().getContext(),
      LanguageService.KEY_APP_LANGUAGE, LanguageService.LANG_FOLLOW_SYSTEM);
  }

  /** 应用启动时恢复持久化的语言设置，保证偏好语言与界面资源一致。 */
  static async applySavedLanguage(): Promise<void> {
    const language: string = await LanguageService.getSavedLanguage();
    LanguageService.setPreferredLanguage(language);
  }

  /**
   * 设置应用语言并持久化。
   * 'default' 表示清除偏好、跟随系统（重新启动应用后生效）；
   * 指定语言立即生效。返回是否成功。
   */
  static async setLanguage(language: string): Promise<boolean> {
    const applied: boolean = LanguageService.setPreferredLanguage(language);
    if (!applied) {
      return false;
    }
    return PreferencesUtil.putString(AppContextStore.getInstance().getContext(),
      LanguageService.KEY_APP_LANGUAGE, language);
  }

  /** 调用系统接口设置应用偏好语言；入参非法或系统不支持时返回 false。 */
  private static setPreferredLanguage(language: string): boolean {
    try {
      i18n.System.setAppPreferredLanguage(language);
      return true;
    } catch (err) {
      const message: string = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, TAG, 'setAppPreferredLanguage %{public}s failed: %{public}s', language, message);
      return false;
    }
  }
}
