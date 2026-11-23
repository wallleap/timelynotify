import { common } from '@kit.AbilityKit';
import { UIContext } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { DOMAIN } from '../../common/Constant';
import { AppInfoService } from '../../services/AppInfoService';
import { ClipboardService } from '../../services/ClipboardService';
import { ThemeService } from '../../services/ThemeService';
import showToast from '../showToast';

/**
 * 「关于」页底部信息：版本号与备案号。
 * 点击版本号复制版本 + 构建溯源信息；点击备案号打开工信部备案管理系统。
 */
@Component
export struct AboutFooter {
  // 点击备案号时打开工信部备案管理系统。
  private readonly icpRecordUrl: string = 'https://beian.miit.gov.cn/';
  // 版本号展示（读取自 BundleInfo；异常时使用兜底常量）
  @State versionNameDisplay: string = '1.0.0';
  @State versionCodeDisplay: number = 1000000;
  // 签名证书指纹尾 8 位（点击复制版本信息时一并复制）
  @State certFingerprintTail: string = '';

  aboutToAppear(): void {
    this.refreshAppVersion();
    this.refreshCertFingerprint();
  }

  build() {
    Column({ space: 6 }) {
      Text($r('app.string.mine_footer_version', this.versionNameDisplay, this.versionCodeDisplay))
        .fontSize(12)
        .fontColor($r('app.color.color_text_tertiary'))
        .onClick(() => this.copyVersionInfo());
      // ICP 备案号为法律标识，保持原文不做多语言处理
      Text('赣ICP备20000895号-3A')
        .fontSize(12)
        .fontColor($r('app.color.color_text_tertiary'))
        .onClick(() => this.openIcpRecord());
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center);
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

  // 点击版本信息：复制完整版本 + 构建溯源信息到剪贴板。
  private async copyVersionInfo(): Promise<void> {
    const uiCtx: UIContext = this.getUIContext();
    const text: string = AppInfoService.buildVersionClipboardText(
      this.versionNameDisplay, this.versionCodeDisplay, this.certFingerprintTail
    );
    const ok: boolean = await ClipboardService.copyText(text);
    if (ok) {
      showToast(uiCtx, $r('app.string.mine_footer_version_copied', this.versionNameDisplay), 1200);
    } else {
      // 复制失败时直接把文本作为 Toast 兜底展示
      showToast(uiCtx, text, 1500);
    }
  }

  // 点击备案号：使用系统链接入口打开工信部备案管理系统。
  private async openIcpRecord(): Promise<void> {
    const uiCtx: UIContext = this.getUIContext();
    const ctx: common.UIAbilityContext | null = ThemeService.getAbilityContext(uiCtx);
    if (!ctx) {
      showToast(uiCtx, $r('app.string.mine_footer_open_icp_failed'));
      return;
    }
    try {
      await ctx.openLink(this.icpRecordUrl, { appLinkingOnly: false });
    } catch (err) {
      const msg: string = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, 'AboutFooter', '打开备案网站失败：%{public}s', msg);
      showToast(uiCtx, $r('app.string.mine_footer_open_icp_failed'));
    }
  }
}
