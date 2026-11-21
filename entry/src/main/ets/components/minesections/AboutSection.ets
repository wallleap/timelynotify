import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { promptAction, UIContext } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { DOMAIN, KEY_APP_UPDATE_AVAILABLE } from '../../common/Constant';
import { AppInfoService, SOURCE_CODE_URL } from '../../services/AppInfoService';
import { AppUpdateCheckStatus, AppUpdateService } from '../../services/AppUpdateService';
import { ExternalLinkService, PRIVACY_URL } from '../../services/ExternalLinkService';
import { FeedbackService } from '../../services/FeedbackService';
import { ThemeService } from '../../services/ThemeService';
import { getDialogMaterial } from '../../utils/ImmersiveUtil';
import showToast from '../showToast';
import { SettingGroup } from '../settings/SettingGroup';
import { SettingGroupTitle } from '../settings/SettingGroupTitle';
import { SettingCell } from '../settings/SettingCell';
import { SettingArrow } from '../settings/SettingArrow';
import { SettingDivider } from '../settings/SettingDivider';

/**
 * 「关于」板块：检测更新 + 开源代码 + 隐私协议 + 反馈问题。
 * 捐赠版块见 DonationSection，底部版本与备案号见 AboutFooter。
 */
@Component
export struct AboutSection {
  // 已上架应用的市场详情页；检测到新版本且用户确认后才打开。
  private readonly appGalleryUrl: string =
    'https://appgallery.huawei.com/app/detail?id=cn.oicode.timelynotify';
  // 避免连续点击并发调用应用市场更新检测接口。
  @State checkingUpdate: boolean = false;
  // 静默或手动检测到新版本时，在检测更新行右侧显示提示点。
  @StorageProp(KEY_APP_UPDATE_AVAILABLE) updateAvailable: boolean = false;

  build() {
    Column({ space: 12 }) {
      SettingGroupTitle({ title: '关于' });

      SettingGroup() {
        // 点击后检测应用市场更新；版本信息由 AboutFooter 展示。
        SettingCell({
          title: '检测更新', icon: $r('app.media.update'),
          clickable: true, onActivate: () => this.checkUpdate()
        }) {
          Row({ space: 8 }) {
            if (this.updateAvailable) {
              Row()
                .width(8)
                .height(8)
                .borderRadius(4)
                .backgroundColor($r('app.color.color_error'));
            }
            SettingArrow();
          }
        }

        SettingDivider();

        // 开源代码行（点击跳转 GitHub）
        SettingCell({
          title: '开源代码', icon: $r('app.media.message_circle_code'),
          clickable: true, onActivate: () => this.openSourceLink()
        }) {
          SettingArrow();
        }

        SettingDivider();

        // 隐私协议行
        SettingCell({
          title: '隐私协议', icon: $r('app.media.file_text'),
          clickable: true, onActivate: () => this.openPrivacy()
        }) {
          SettingArrow();
        }

        SettingDivider();

        // 反馈问题行（发送邮件）
        SettingCell({
          title: '反馈问题', icon: $r('app.media.mail_question_mark'),
          clickable: true, onActivate: () => this.sendFeedback()
        }) {
          SettingArrow();
        }
      }
    }.width('100%');
  }

  // 静默或手动检测到新版本时显示红点；点击后先询问用户，不直接跳转。
  private async checkUpdate(): Promise<void> {
    if (this.checkingUpdate) {
      return;
    }
    const uiCtx: UIContext = this.getUIContext();
    const ctx: common.UIAbilityContext | null = ThemeService.getAbilityContext(uiCtx);
    if (!ctx) {
      showToast(uiCtx, '检测更新失败，请稍后重试');
      return;
    }
    this.checkingUpdate = true;
    try {
      const status: AppUpdateCheckStatus = await AppUpdateService.checkManually(ctx);
      if (status === AppUpdateCheckStatus.AVAILABLE) {
        this.showUpdateDialog(uiCtx, ctx);
      } else if (status === AppUpdateCheckStatus.CURRENT) {
        showToast(uiCtx, '已是最新版本');
      } else {
        showToast(uiCtx, '检测更新失败，请稍后重试');
      }
    } catch (err) {
      const msg: string = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, 'AboutSection', '检测更新失败：%{public}s', msg);
      showToast(uiCtx, '检测更新失败，请稍后重试');
    } finally {
      this.checkingUpdate = false;
    }
  }

  // 有新版本时显示确认弹窗；取消或关闭弹窗均不打开应用市场。
  private showUpdateDialog(uiCtx: UIContext, ctx: common.UIAbilityContext): void {
    const buttons: promptAction.Button[] = [
      { text: '暂不更新', color: $r('app.color.color_text_tertiary') },
      { text: '前往应用市场更新', color: $r('app.color.color_brand') }
    ];
    uiCtx.getPromptAction().showDialog({
      title: '发现新版本',
      message: '检测到新版本，是否前往应用市场更新？',
      buttons: buttons,
      systemMaterial: getDialogMaterial(),
    }, (err: BusinessError, result: promptAction.ShowDialogSuccessResponse) => {
      if (err) {
        hilog.warn(DOMAIN, 'AboutSection', '显示更新弹窗失败：%{public}s', err.message);
        showToast(uiCtx, '无法显示更新提示');
        return;
      }
      if (result.index === 1) {
        this.openAppGallery(uiCtx, ctx);
      }
    });
  }

  // 用户确认后打开应用市场；跳转失败时保留在当前页面并提示。
  private async openAppGallery(uiCtx: UIContext, ctx: common.UIAbilityContext): Promise<void> {
    AppUpdateService.markMarketOpened();
    try {
      await ctx.openLink(this.appGalleryUrl, { appLinkingOnly: false });
    } catch (err) {
      AppUpdateService.cancelMarketRecheck();
      const msg: string = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, 'AboutSection', '打开应用市场失败：%{public}s', msg);
      showToast(uiCtx, '无法打开应用市场');
    }
  }

  // 点击开源代码行：通过系统链接入口在应用外打开仓库页面。
  private async openSourceLink(): Promise<void> {
    const uiCtx: UIContext = this.getUIContext();
    const ctx: common.UIAbilityContext | null = ThemeService.getAbilityContext(uiCtx);
    if (!ctx) {
      showToast(uiCtx, '无法打开开源代码页面');
      return;
    }
    try {
      await ctx.openLink(SOURCE_CODE_URL, { appLinkingOnly: false });
    } catch (err) {
      const msg: string = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, 'AboutSection', '打开开源代码页面失败：%{public}s', msg);
      showToast(uiCtx, '无法打开开源代码页面');
    }
  }

  // 点击隐私协议行：进入内嵌 WebView 页面
  private async openPrivacy(): Promise<void> {
    await ExternalLinkService.openSharePage(this.getUIContext(), PRIVACY_URL, '隐私协议');
  }

  // 点击反馈问题行：通过 startAbilityByType 拉起系统邮件应用，自动附带设备信息
  private async sendFeedback(): Promise<void> {
    const uiCtx: UIContext = this.getUIContext();
    const ctx: common.UIAbilityContext | null = ThemeService.getAbilityContext(uiCtx);
    if (!ctx) {
      showToast(uiCtx, '上下文获取失败');
      return;
    }
    const info = await AppInfoService.fetchVersionInfo();
    FeedbackService.sendFeedback(uiCtx, ctx, `${info.name} (${info.code})`);
  }
}
