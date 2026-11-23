import { BusinessError, deviceInfo } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { UIContext } from '@kit.ArkUI';
import showToast from '../components/showToast';
import { ClipboardService } from './ClipboardService';
import { AppContextStore } from '../common/AppContextStore';
import { DOMAIN } from '../common/Constant';

const TAG: string = 'FeedbackSvc';

/** 读取当前语言的字符串资源（邮件模板文案）；Context 未就绪时回退空串 */
function tr(res: Resource, arg1?: string | number, arg2?: string | number): string {
  const ctx: common.Context | null = AppContextStore.getInstance().getContext();
  if (ctx === null) {
    return '';
  }
  if (arg1 === undefined) {
    return ctx.resourceManager.getStringSync(res.id);
  }
  if (arg2 === undefined) {
    return ctx.resourceManager.getStringSync(res.id, arg1);
  }
  return ctx.resourceManager.getStringSync(res.id, arg1, arg2);
}

/** 反馈邮箱常量（MineView 顶部常量搬入服务层） */
export const FEEDBACK_EMAIL: string = 'vonnelu@163.com';

/**
 * 反馈问题服务：通过 startAbilityByType 拉起系统邮件应用，自动附带设备信息；
 * 无可用邮件应用时复制邮箱地址到剪贴板作为兜底。
 */
export class FeedbackService {
  /**
   * 发送反馈邮件。
   * @param uiCtx 调用方 UIContext（用于 Toast 提示）
   * @param ctx UIAbilityContext（startAbilityByType 必需）
   * @param appVersion 应用版本展示串（如 "TimelyNotify 1.0.0 (1000000)"）
   */
  static sendFeedback(uiCtx: UIContext, ctx: common.UIAbilityContext, appVersion: string): void {
    try {
      let model: string = '';
      let osVer: string = '';
      try {
        model = deviceInfo.productModel;
        osVer = deviceInfo.osFullName;
      } catch (_e) {
        // 设备信息读取失败时留空，不阻断发邮件
      }
      const body: string = tr($r('app.string.feedback_mail_intro')) +
        tr($r('app.string.feedback_mail_device_info_header')) +
        tr($r('app.string.feedback_mail_app_version'), appVersion) +
        tr($r('app.string.feedback_mail_device_model'), model) +
        tr($r('app.string.feedback_mail_os_version'), osVer) +
        tr($r('app.string.feedback_mail_time'), new Date().toLocaleString());
      const subject: string = tr($r('app.string.feedback_mail_subject'), model);
      const wantParam: Record<string, Object> = {
        'sceneType': 1,
        'email': [encodeURI(FEEDBACK_EMAIL)],
        'subject': encodeURI(subject),
        'body': encodeURI(body)
      };
      const abilityStartCallback: common.AbilityStartCallback = {
        onError: (code: number, name: string, message: string) => {
          hilog.warn(DOMAIN, TAG, '邮件应用拉起失败：code=%{public}d name=%{public}s msg=%{public}s，回退为复制邮箱',
            code, name, message);
          FeedbackService.fallbackCopyEmail(uiCtx);
        },
        onResult: (_result) => {
          hilog.info(DOMAIN, TAG, '邮件应用返回');
        }
      };
      ctx.startAbilityByType('mail', wantParam, abilityStartCallback, (err: BusinessError) => {
        if (err) {
          hilog.warn(DOMAIN, TAG, 'startAbilityByType 异常：%{public}s，回退为复制邮箱', err.message);
          FeedbackService.fallbackCopyEmail(uiCtx);
        } else {
          hilog.info(DOMAIN, TAG, '邮件应用拉起成功');
        }
      });
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, TAG, 'sendFeedback 异常：%{public}s，回退为复制邮箱', msg);
      FeedbackService.fallbackCopyEmail(uiCtx);
    }
  }

  /** 无可用邮件应用时，复制邮箱地址到剪贴板作为兜底 */
  static async fallbackCopyEmail(uiCtx: UIContext): Promise<void> {
    const ok: boolean = await ClipboardService.copyText(FEEDBACK_EMAIL);
    if (ok) {
      showToast(uiCtx, $r('app.string.feedback_email_copied', FEEDBACK_EMAIL));
    } else {
      showToast(uiCtx, $r('app.string.feedback_email_send_to', FEEDBACK_EMAIL));
    }
  }
}
