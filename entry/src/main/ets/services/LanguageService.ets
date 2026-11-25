import { i18n } from '@kit.LocalizationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { PreferencesUtil } from '../utils/PreferencesUtil';
import { AppContextStore } from '../common/AppContextStore';
import { DOMAIN } from '../common/Constant';

const TAG: string = 'LanguageService';

/**
 * 应用内语言设置服务。
 * 'default' 跟随系统语言；'zh-Hans' / 'en-US' 为应用偏好语言。
 * 三种选择均持久化后立即刷新界面，不影响系统语言。
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
   * 设置应用语言并持久化，界面立即刷新。
   * 'default' 表示清除偏好、跟随系统：落 'default' 后再显式应用当前系统语言，
   * 保证本次会话立即切换；下次启动仍按系统语言加载。返回是否成功。
   */
  static async setLanguage(language: string): Promise<boolean> {
    const applied: boolean = LanguageService.setPreferredLanguage(language);
    if (!applied) {
      return false;
    }
    if (language === LanguageService.LANG_FOLLOW_SYSTEM) {
      // 'default' 的官方刷新时机是下次启动；补一步系统语言应用实现即时切换
      LanguageService.applySystemLanguageForRefresh();
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

  /** “跟随系统”选择后读取当前系统语言并显式应用，使界面无需重启立即切换；失败时保持 default 待下次启动生效。 */
  private static applySystemLanguageForRefresh(): void {
    try {
      const systemLanguage: string = i18n.System.getSystemLanguage();
      if (systemLanguage.length > 0) {
        i18n.System.setAppPreferredLanguage(systemLanguage);
      }
    } catch (err) {
      const message: string = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, TAG, 'apply system language failed: %{public}s', message);
    }
  }
}
