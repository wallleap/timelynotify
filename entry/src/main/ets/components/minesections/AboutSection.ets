import { common } from '@kit.AbilityKit';
import { UIContext } from '@kit.ArkUI';
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
 * 「关于」板块：当前版本（点击复制）+ 开源代码 + 隐私协议 + 反馈问题。
 * 全自治：自身管理 versionName/versionCode/certFingerprintTail，业务下沉到各 Service。
 *
 * 自身刷新版本号与签名指纹，用于版本展示、复制及反馈邮件。
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

  build() {
    Column({ space: 12 }) {
      SettingGroupTitle({ title: '关于' });

      SettingGroup() {
        // 版本号行（整行点击复制版本信息）
        SettingCell({ title: '当前版本', clickable: true, onActivate: () => this.copyVersionInfo() }) {
          Text(`${this.versionNameDisplay} (${this.versionCodeDisplay})`)
            .fontSize(14)
            .fontColor($r('app.color.color_text_tertiary'));
        }

        SettingDivider();

        // 开源代码行（点击跳转 GitHub）
        SettingCell({ title: '开源代码', clickable: true, onActivate: () => this.openSourceLink() }) {
          SettingArrow();
        }

        SettingDivider();

        // 隐私协议行
        SettingCell({ title: '隐私协议', clickable: true, onActivate: () => this.openPrivacy() }) {
          SettingArrow();
        }

        SettingDivider();

        // 反馈问题行（发送邮件）
        SettingCell({ title: '反馈问题', clickable: true, onActivate: () => this.sendFeedback() }) {
          SettingArrow();
        }
      }
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
