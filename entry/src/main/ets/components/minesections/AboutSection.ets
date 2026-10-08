import { common } from '@kit.AbilityKit';
import { updateManager } from '@kit.AppGalleryKit';
import { UIContext } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { DOMAIN } from '../../common/Constant';
import { AppInfoService, SOURCE_CODE_URL } from '../../services/AppInfoService';
import { ExternalLinkService, PRIVACY_URL } from '../../services/ExternalLinkService';
import { FeedbackService } from '../../services/FeedbackService';
import { ClipboardService } from '../../services/ClipboardService';
import { ThemeService } from '../../services/ThemeService';
import showToast from '../showToast';
import { SettingGroup } from '../settings/SettingGroup';
import { SettingGroupTitle } from '../settings/SettingGroupTitle';
import { SettingCell } from '../settings/SettingCell';
import { SettingArrow } from '../settings/SettingArrow';
import { SettingDivider } from '../settings/SettingDivider';

/**
 * 「关于」板块：检测更新 + 开源代码 + 隐私协议 + 反馈问题；底部展示版本与备案号。
 * 全自治：自身管理 versionName/versionCode/certFingerprintTail，业务下沉到各 Service。
 *
 * 自身刷新版本号与签名指纹，用于版本展示、复制及反馈邮件。
 */
@Component
export struct AboutSection {
  // 已上架应用的市场详情页；检测到新版本后才打开。
  private readonly appGalleryUrl: string =
    'https://appgallery.huawei.com/app/detail?id=cn.oicode.timelynotify';
  // 点击备案号时打开工信部备案管理系统。
  private readonly icpRecordUrl: string = 'https://beian.miit.gov.cn/';
  // 版本号展示（读取自 BundleInfo；异常时使用兜底常量）
  @State versionNameDisplay: string = '1.0.0';
  @State versionCodeDisplay: number = 1000000;
  // 避免连续点击并发调用应用市场更新检测接口。
  @State checkingUpdate: boolean = false;
  // 签名证书指纹尾 8 位（点击复制版本信息时一并复制）
  @State certFingerprintTail: string = '';

  aboutToAppear() {
    this.refreshAppVersion();
    this.refreshCertFingerprint();
  }

  build() {
    Column({ space: 12 }) {
      SettingGroupTitle({ title: '关于' });

      SettingGroup() {
        // 点击后检测应用市场更新；版本信息移到卡片下方。
        SettingCell({
          title: '检测更新', icon: $r('app.media.update'),
          clickable: true, onActivate: () => this.checkUpdate()
        }) {
          SettingArrow();
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

      // 关于信息随页面滚动停留在所有设置项下方，点击版本仍可复制构建信息。
      Column({ space: 6 }) {
        Text(`版本 ${this.versionNameDisplay} (${this.versionCodeDisplay})`)
          .fontSize(12)
          .fontColor($r('app.color.color_text_tertiary'))
          .onClick(() => this.copyVersionInfo());
        Text('赣ICP备20000895号-3A')
          .fontSize(12)
          .fontColor($r('app.color.color_text_tertiary'))
          .onClick(() => this.openIcpRecord());
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
      .margin({ top: 8 });
    }.width('100%');
  }

  // 读取自身应用版本号（Stage 模式官方接口，无需权限）
  private async refreshAppVersion(): Promise<void> {
    const info = await AppInfoService.fetchVersionInfo();
    this.versionNameDisplay = info.name;
    this.versionCodeDisplay = info.code;
  }

  // 运行时读取签名证书指纹尾 8 位
  private async refreshCertFingerprint(): Promise<void> {
    this.certFingerprintTail = await AppInfoService.fetchCertFingerprintTail();
  }

  // 点击底部版本信息：复制完整版本 + 构建溯源信息到剪贴板。
  private async copyVersionInfo(): Promise<void> {
    const uiCtx: UIContext = this.getUIContext();
    const text: string = AppInfoService.buildVersionClipboardText(
      this.versionNameDisplay, this.versionCodeDisplay, this.certFingerprintTail
    );
    const ok: boolean = await ClipboardService.copyText(text);
    if (ok) {
      showToast(uiCtx, `已复制版本：${this.versionNameDisplay}`, 1200);
    } else {
      // 复制失败时直接把文本作为 Toast 兜底展示
      showToast(uiCtx, text, 1500);
    }
  }

  // 先向应用市场检查更新；仅在有新版本时打开市场详情页。
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
      const result: updateManager.CheckUpdateResult = await updateManager.checkAppUpdate(ctx);
      if (result.updateAvailable === updateManager.UpdateAvailableCode.LATER_VERSION_EXIST) {
        await ctx.openLink(this.appGalleryUrl, { appLinkingOnly: false });
      } else if (result.updateAvailable === updateManager.UpdateAvailableCode.LATER_VERSION_NOT_EXIST) {
        showToast(uiCtx, '已是最新版本');
      } else {
        showToast(uiCtx, '检测更新失败，请稍后重试');
      }
    } catch (err) {
      const msg: string = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, 'AboutSection', '检测更新或打开应用市场失败：%{public}s', msg);
      showToast(uiCtx, '检测更新或打开应用市场失败');
    } finally {
      this.checkingUpdate = false;
    }
  }

  // 点击开源代码行：进入内嵌 WebView 页面
  private async openSourceLink(): Promise<void> {
    await ExternalLinkService.openSharePage(this.getUIContext(), SOURCE_CODE_URL, '开源代码');
  }

  // 点击隐私协议行：进入内嵌 WebView 页面
  private async openPrivacy(): Promise<void> {
    await ExternalLinkService.openSharePage(this.getUIContext(), PRIVACY_URL, '隐私协议');
  }

  // 点击备案号：使用系统链接入口打开工信部备案管理系统。
  private async openIcpRecord(): Promise<void> {
    const uiCtx: UIContext = this.getUIContext();
    const ctx: common.UIAbilityContext | null = ThemeService.getAbilityContext(uiCtx);
    if (!ctx) {
      showToast(uiCtx, '无法打开备案网站');
      return;
    }
    try {
      await ctx.openLink(this.icpRecordUrl, { appLinkingOnly: false });
    } catch (err) {
      const msg: string = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, 'AboutSection', '打开备案网站失败：%{public}s', msg);
      showToast(uiCtx, '无法打开备案网站');
    }
  }

  // 点击反馈问题行：通过 startAbilityByType 拉起系统邮件应用，自动附带设备信息
  private sendFeedback(): void {
    const uiCtx: UIContext = this.getUIContext();
    const ctx: common.UIAbilityContext | null = ThemeService.getAbilityContext(uiCtx);
    if (!ctx) {
      showToast(uiCtx, '上下文获取失败');
      return;
    }
    const appVersion: string = `TimelyNotify ${this.versionNameDisplay} (${this.versionCodeDisplay})`;
    FeedbackService.sendFeedback(uiCtx, ctx, appVersion);
  }
}
