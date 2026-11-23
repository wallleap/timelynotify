import { common } from '@kit.AbilityKit';
import { UIContext } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { DOMAIN } from '../../common/Constant';
import { DeviceRegisterService } from '../../services/DeviceRegisterService';
import { AppInfoService } from '../../services/AppInfoService';
import { ClipboardService } from '../../services/ClipboardService';
import { ThemeService } from '../../services/ThemeService';
import showToast from '../showToast';
import { resolveBlurStyle } from '../../utils/ImmersiveUtil';
import { SettingGroup } from '../settings/SettingGroup';
import { SettingGroupTitle } from '../settings/SettingGroupTitle';
import { SettingCell } from '../settings/SettingCell';
import { SettingArrow } from '../settings/SettingArrow';

/**
 * 「信息」板块：构建信息行（云端构建编号 / commit / 签名指纹尾串）+ 推送 Token 卡片。
 * 全自治：自身管理 certFingerprintTail/deviceTokenDisplay，
 * 点击构建信息行打开云端构建记录页；点击推送 Token 卡片复制完整明文到剪贴板。
 */
@Component
export struct AppInfoSection {
  // 签名证书指纹尾 8 位（运行时读取；完整指纹发布在 README / GitHub Release 供比对）
  @State certFingerprintTail: string = '';
  // 推送 Token（Push 下发的 device_token；卡片展示用，点击复制完整明文）
  @State deviceTokenDisplay: string = '';

  aboutToAppear() {
    this.refreshCertFingerprint();
    this.refreshDeviceToken();
  }

  build() {
    Column({ space: 12 }) {
      SettingGroupTitle({ title: $r('app.string.mine_appinfo_section_title') });

      Column({ space: 12 }) {
        // 构建信息行（展示云端构建编号 / commit / 签名指纹尾串；点击打开构建记录页供用户比对防伪）
        SettingGroup() {
          SettingCell({
            title: $r('app.string.mine_appinfo_build_info'),
            icon: $r('app.media.shield_keyhole'),
            description: AppInfoService.buildInfoDisplay(this.certFingerprintTail),
            descriptionMaxLines: 1,
            clickable: true,
            onActivate: () => this.openBuildInfo()
          }) {
            // 云端构建才有对应记录页，本地构建不显示箭头。
            if (AppInfoService.hasCloudBuild()) {
              SettingArrow();
            }
          }
        }

        // 推送 Token 卡片（Device Token）；点击整行复制完整明文到剪贴板
        Row({ space: 14 }) {
          Image($r('app.media.key_square'))
            .width(24)
            .height(24)
            .objectFit(ImageFit.Contain)
            .fillColor($r('app.color.color_text_tertiary'))
            .draggable(false);
          Column({ space: 4 }) {
            Row() {
              Text($r('app.string.mine_appinfo_push_token'))
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.color_text_primary'));
              Text($r('app.string.mine_appinfo_auto_generated'))
                .fontSize(14)
                .fontColor($r('app.color.color_text_tertiary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis });
              Blank();
              Text($r('app.string.mine_appinfo_tap_to_copy')).fontSize(12).fontColor($r('app.color.color_brand'));
            }.width('100%');

            Text(this.buildDeviceTokenDisplay())
              .fontSize(12)
              .fontColor($r('app.color.color_text_hint'))
              .width('100%')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis });
          }.alignItems(HorizontalAlign.Start).layoutWeight(1);
        }
        .width('100%')
        .padding(16)
        .backgroundBlurStyle(resolveBlurStyle('bar')!)
        .backgroundColor($r('app.color.color_bg_surface_glass'))
        .borderRadius(12)
        .onClick(() => {
          this.copyDeviceToken();
        });
      }.width('100%')
    }.width('100%');
  }

  // 运行时读取签名证书指纹尾 8 位（失败时留空，构建信息行降级为只显示 commit）
  private async refreshCertFingerprint(): Promise<void> {
    this.certFingerprintTail = await AppInfoService.fetchCertFingerprintTail();
  }

  // 刷新 Device Token（Push 下发）。先等当前注册任务完成（如 PushKit 还在 getToken），
  // 再读盘；保证启动早期进入 MineView 时也能拿到 Push 写入后的值。
  private async refreshDeviceToken(): Promise<void> {
    await DeviceRegisterService.getInstance().whenRegistrationSettled();
    this.deviceTokenDisplay = await DeviceRegisterService.getInstance().getDeviceToken();
  }

  // 掩码展示：只保留最后 4 位可辨识，其余为圆点，避免卡片上泄露长 token
  private buildDeviceTokenDisplay(): ResourceStr {
    const t: string = this.deviceTokenDisplay;
    if (!t || t.length === 0) {
      return $r('app.string.mine_appinfo_not_fetched');
    }
    if (t.length <= 8) {
      const dots: string = '••'.padEnd(t.length, '•');
      return $r('app.string.mine_appinfo_token_masked', dots, t.length);
    }
    const tail: string = t.substring(t.length - 4);
    return $r('app.string.mine_appinfo_token_masked_tail', tail, t.length);
  }

  // 点击卡片：把 Device Token 完整明文复制到剪贴板
  private async copyDeviceToken(): Promise<void> {
    const uiCtx: UIContext = this.getUIContext();
    const t: string = this.deviceTokenDisplay;
    if (!t || t.length === 0) {
      showToast(uiCtx, $r('app.string.mine_appinfo_token_not_ready'), 3000);
      return;
    }
    const ok: boolean = await ClipboardService.copyText(t);
    if (ok) {
      showToast(uiCtx, $r('app.string.mine_appinfo_token_copied'), 1200);
    } else {
      showToast(uiCtx, $r('app.string.mine_appinfo_copy_failed'));
    }
  }

  // 点击构建信息行：通过系统链接入口打开云端构建记录页，以便在应用外验证包来源。
  private async openBuildInfo(): Promise<void> {
    const uiCtx: UIContext = this.getUIContext();
    if (!AppInfoService.hasCloudBuild()) {
      showToast(uiCtx, $r('app.string.mine_appinfo_local_build'), 2000);
      return;
    }
    const ctx: common.UIAbilityContext | null = ThemeService.getAbilityContext(uiCtx);
    if (!ctx) {
      showToast(uiCtx, $r('app.string.mine_appinfo_open_build_failed'));
      return;
    }
    try {
      await ctx.openLink(AppInfoService.buildRunUrl(), { appLinkingOnly: false });
    } catch (err) {
      const msg: string = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, 'AppInfoSection', '打开构建记录页面失败：%{public}s', msg);
      showToast(uiCtx, $r('app.string.mine_appinfo_open_build_failed'));
    }
  }
}
