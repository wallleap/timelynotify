import { common } from '@kit.AbilityKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { UIContext } from '@kit.ArkUI';
import { AppInfoService, SOURCE_CODE_URL } from '../../services/AppInfoService';
import { ExternalLinkService, USE_DOCS_URL, PRIVACY_URL } from '../../services/ExternalLinkService';
import { FeedbackService } from '../../services/FeedbackService';
import { ClipboardService } from '../../services/ClipboardService';
import { ThemeService } from '../../services/ThemeService';
import showToast from '../showToast';
import { resolveBlurStyle } from '../../utils/ImmersiveUtil';

/**
 * 「关于」板块：当前版本（点击复制）+ 开源代码 + 使用文档 + 隐私协议 + 反馈问题。
 * 全自治：自身管理 versionName/versionCode/certFingerprintTail，业务下沉到各 Service。
 *
 * 注意：为保持与原 MineView 行为一致，本板块会自己 refresh 版本号 + 签名指纹
 * （即使 AppInfoSection 也会 refresh 一次，二者各自刷新互不干扰；读取是幂等的）
 */
@Component
export struct AboutSection {
  // 版本号展示（读取自 BundleInfo；异常时使用兜底常量）
  @State versionNameDisplay: string = '1.0.0';
  @State versionCodeDisplay: number = 1000000;
  // 签名证书指纹尾 8 位（点击复制版本信息时一并复制）
  @State certFingerprintTail: string = '';

  aboutToAppear() {
    this.refreshAppVersion();
    this.refreshCertFingerprint();
  }

  @Builder
  arrowRightIcon() {
    Image($r('app.media.arrow_right'))
      .width(20)
      .height(20)
      .objectFit(ImageFit.Contain)
      .fillColor($r('app.color.text_quinary_color'));
  }

  build() {
    Column({ space: 8 }) {
      Text('关于')
        .fontSize(12)
        .fontColor($r('app.color.text_quinary_color'))
        .width('100%')
        .padding({ left: 12 });

      Column({ space: 0 }) {
        // 版本号行（整行点击复制版本信息）
        Row() {
          Text('当前版本')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary_color'))
            .layoutWeight(1);
          Text(`${this.versionNameDisplay} (${this.versionCodeDisplay})`)
            .fontSize(14)
            .fontColor($r('app.color.text_tertiary_color'));
        }.width('100%').padding(16).onClick(() => {
          this.copyVersionInfo();
        });

        Divider().color($r('app.color.divider_color')).strokeWidth(1).margin({ left: 16, right: 16 });

        // 开源代码行（点击跳转 GitHub）
        Row() {
          Text('开源代码')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary_color'))
            .layoutWeight(1);
          this.arrowRightIcon();
        }.width('100%').padding(16).onClick(() => {
          this.openSourceLink();
        });

        Divider().color($r('app.color.divider_color')).strokeWidth(1).margin({ left: 16, right: 16 });

        // 使用文档行（进入内嵌 WebView）
        Row() {
          Text('使用文档')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary_color'))
            .layoutWeight(1);
          this.arrowRightIcon();
        }.width('100%').padding(16).onClick(() => {
          this.openDocs();
        });

        Divider().color($r('app.color.divider_color')).strokeWidth(1).margin({ left: 16, right: 16 });

        // 隐私协议行
        Row() {
          Text('隐私协议')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary_color'))
            .layoutWeight(1);
          this.arrowRightIcon();
        }.width('100%').padding(16).onClick(() => {
          this.openPrivacy();
        });

        Divider().color($r('app.color.divider_color')).strokeWidth(1).margin({ left: 16, right: 16 });

        // 反馈问题行（发送邮件）
        Row() {
          Text('反馈问题')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary_color'))
            .layoutWeight(1);
          this.arrowRightIcon();
        }.width('100%').padding(16).onClick(() => {
          this.sendFeedback();
        });
      }
      .width('100%')
      .backgroundBlurStyle(resolveBlurStyle('bar')!)
      .backgroundColor($r('app.color.card_glass_background'))
      .borderRadius(12);
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

  // 点击当前版本行：复制完整版本 + 构建溯源信息到剪贴板
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

  // 点击开源代码行：进入内嵌 WebView 页面
  private async openSourceLink(): Promise<void> {
    await ExternalLinkService.openSharePage(this.getUIContext(), SOURCE_CODE_URL, '开源代码');
  }

  // 点击使用文档行：进入内嵌 WebView 页面
  private async openDocs(): Promise<void> {
    await ExternalLinkService.openSharePage(this.getUIContext(), USE_DOCS_URL, '使用文档');
  }

  // 点击隐私协议行：进入内嵌 WebView 页面
  private async openPrivacy(): Promise<void> {
    await ExternalLinkService.openSharePage(this.getUIContext(), PRIVACY_URL, '隐私协议');
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
