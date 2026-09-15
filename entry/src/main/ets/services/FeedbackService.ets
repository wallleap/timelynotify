import { BusinessError, deviceInfo } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { UIContext } from '@kit.ArkUI';
import showToast from '../components/showToast';
import { ClipboardService } from './ClipboardService';
import { DOMAIN } from '../common/Constant';

const TAG: string = 'FeedbackSvc';

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
      const body: string = '请在此描述你遇到的问题或建议：\n\n' + '---------------- 设备信息 ----------------\n' +
        `应用版本：${appVersion}\n` + `设备型号：${model}\n` + `系统版本：${osVer}\n` +
        `反馈时间：${new Date().toLocaleString()}\n`;
      const subject: string = `TimelyNotify 反馈 - ${model}`;
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
      showToast(uiCtx, `已复制邮箱：${FEEDBACK_EMAIL}`);
    } else {
      showToast(uiCtx, `请发送邮件至：${FEEDBACK_EMAIL}`);
    }
  }
}
