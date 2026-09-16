import { UIContext } from '@kit.ArkUI';
import { DeviceRegisterService } from '../../services/DeviceRegisterService';
import { AppInfoService } from '../../services/AppInfoService';
import { ExternalLinkService } from '../../services/ExternalLinkService';
import { ClipboardService } from '../../services/ClipboardService';
import showToast from '../showToast';
import { resolveBlurStyle } from '../../utils/ImmersiveUtil';

/**
 * 「信息」板块：构建信息行（云端构建编号 / commit / 签名指纹尾串）+ 推送 Token 卡片。
 * 全自治：自身管理 versionName/versionCode/certFingerprintTail/deviceTokenDisplay，
 * 点击构建信息行打开云端构建记录页；点击推送 Token 卡片复制完整明文到剪贴板。
 */
@Component
export struct AppInfoSection {
  // 版本号展示（读取自 BundleInfo；异常时使用兜底常量）
  @State versionNameDisplay: string = '1.0.0';
  @State versionCodeDisplay: number = 1000000;
  // 签名证书指纹尾 8 位（运行时读取；完整指纹发布在 README / GitHub Release 供比对）
  @State certFingerprintTail: string = '';
  // 推送 Token（Push 下发的 device_token；卡片展示用，点击复制完整明文）
  @State deviceTokenDisplay: string = '';

  aboutToAppear() {
    this.refreshAppVersion();
    this.refreshCertFingerprint();
    this.refreshDeviceToken();
  }

  @Builder
  arrowRightIcon() {
    Image($r('app.media.arrow_right'))
      .width(20)
      .height(20)
      .objectFit(ImageFit.Contain)
      .fillColor($r('app.color.color_text_hint'))
      .draggable(false);
  }

  build() {
    Column({ space: 8 }) {
      Text('信息')
        .fontSize(12)
        .fontColor($r('app.color.color_text_hint'))
        .width('100%')
        .padding({ left: 12 });

      Column({ space: 10 }) {
        // 构建信息行（展示云端构建编号 / commit / 签名指纹尾串；点击打开构建记录页供用户比对防伪）
        Row() {
          Column({ space: 2 }) {
            Text('构建信息')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.color_text_primary'));
            Text(AppInfoService.buildInfoDisplay(this.certFingerprintTail))
              .fontSize(12)
              .fontColor($r('app.color.color_text_hint'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis });
          }.alignItems(HorizontalAlign.Start).layoutWeight(1);

          // 云端构建才有对应记录页，本地构建不显示箭头
          if (AppInfoService.hasCloudBuild()) {
            this.arrowRightIcon();
          }
        }
        .width('100%')
        .padding(16)
        .backgroundBlurStyle(resolveBlurStyle('bar')!)
        .backgroundColor($r('app.color.color_bg_surface_glass'))
        .borderRadius(12)
        .onClick(() => {
          this.openBuildInfo();
        });

        // 推送 Token 卡片（Device Token）；点击整行复制完整明文到剪贴板
        Row({ space: 14 }) {
          Column({ space: 4 }) {
            Row() {
              Text('推送 Token')
                .fontSize(17)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.color_text_primary'));
              Text(' (自动生成)')
                .fontSize(14)
                .fontColor($r('app.color.color_text_tertiary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis });
              Blank();
              Text('点击复制').fontSize(12).fontColor($r('app.color.color_brand'));
            }.width('100%');

            Text(this.buildDeviceTokenDisplay())
              .fontSize(14)
              .fontColor(this.deviceTokenDisplay.length > 0 ? $r('app.color.color_text_tertiary') :
                $r('app.color.color_text_hint'))
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

  // 读取自身应用版本号（Stage 模式官方接口，无需权限）
  private async refreshAppVersion(): Promise<void> {
    const info = await AppInfoService.fetchVersionInfo();
    this.versionNameDisplay = info.name;
    this.versionCodeDisplay = info.code;
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
  private buildDeviceTokenDisplay(): string {
    const t: string = this.deviceTokenDisplay;
    if (!t || t.length === 0) {
      return '未获取';
    }
    if (t.length <= 8) {
      const dots: string = '••'.padEnd(t.length, '•');
      return `${dots} (${t.length} 位)`;
    }
    const tail: string = t.substring(t.length - 4);
    const prefixMasked: string = '••••••••';
    return `${prefixMasked}...${tail} (${t.length} 位)`;
  }

  // 点击卡片：把 Device Token 完整明文复制到剪贴板
  private async copyDeviceToken(): Promise<void> {
    const uiCtx: UIContext = this.getUIContext();
    const t: string = this.deviceTokenDisplay;
    if (!t || t.length === 0) {
      showToast(uiCtx, '推送 Token 尚未获取', 3000);
      return;
    }
    const ok: boolean = await ClipboardService.copyText(t);
    if (ok) {
      showToast(uiCtx, '已复制推送 Token', 1200);
    } else {
      showToast(uiCtx, '复制失败');
    }
  }

  // 点击构建信息行：打开云端构建记录页（伪造包无法在官方仓库创建对应 run 记录，以此验证包来源）
  private async openBuildInfo(): Promise<void> {
    const uiCtx: UIContext = this.getUIContext();
    if (!AppInfoService.hasCloudBuild()) {
      showToast(uiCtx, '本地构建，无云端构建记录', 2000);
      return;
    }
    await ExternalLinkService.openSharePage(uiCtx, AppInfoService.buildRunUrl(), '构建信息');
  }
}
