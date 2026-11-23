import { hilog } from '@kit.PerformanceAnalysisKit';
import { hdsMaterial, HdsNavigation, HdsNavigationTitleMode, ScrollEffectType } from '@kit.UIDesignKit';
import { EncryptionConfig } from '../model/EncryptionConfig';
import { EncryptionConfigService } from '../services/EncryptionConfigService';
import { DOMAIN } from '../common/Constant';
import { getDialogBackgroundOptions, shouldUseSystemMaterialPath, withImmersiveMenuMaterial } from '../utils/ImmersiveUtil';
import { DangerConfirmDialog } from './DangerConfirmDialog';
import showToast from './showToast';

const TAG: string = 'DecryptionDlg';

// 三段式布局：标题与操作区固定，配置在弹窗显示后加载，正文独立滚动。
@Builder
function emptyDecryptionBuilder(): void {
}

@CustomDialog
export struct DecryptionSettingsDialog {
  controller: CustomDialogController = new CustomDialogController({
    builder: emptyDecryptionBuilder(),
    autoCancel: true,
    alignment: DialogAlignment.Center,
    offset: { dx: 0, dy: 0 },
  });
  serverLabel: string = '';
  loadConfig: () => Promise<EncryptionConfig> = async () => new EncryptionConfig();
  onSave: (config: EncryptionConfig) => Promise<boolean> = async (_config: EncryptionConfig) => false;
  onClear: () => Promise<boolean> = async () => false;
  @State private isEncryptionEnabled: boolean = true;
  @State private algorithm: string = 'AES128';
  @State private mode: string = 'CBC';
  @State private paddingValue: string = 'PKCS7';
  @State private keyText: string = '';
  private active: boolean = false;
  private configLoaded: boolean = false;
  private saving: boolean = false;
  private originalAlgorithm: string = 'AES128';
  private originalMode: string = 'CBC';
  private originalKey: string = '';
  private formScroller: Scroller = new Scroller();

  aboutToDisappear() {
    this.active = false;
  }

  private async loadConfigDisplay(): Promise<void> {
    try {
      const config: EncryptionConfig = await this.loadConfig();
      if (this.active) {
        this.isEncryptionEnabled = config.enabled;
        this.algorithm = config.algorithm;
        this.mode = config.mode;
        this.paddingValue = config.padding;
        this.keyText = config.key;
        this.originalAlgorithm = config.algorithm;
        this.originalMode = config.mode;
        this.originalKey = config.key;
        this.configLoaded = true;
      }
    } catch (_err) {
      hilog.warn(DOMAIN, TAG, '读取解密配置失败');
    }
  }

  @Builder
  private dialogContent(showFallbackTitle: boolean) {
    Column() {
      if (showFallbackTitle) {
        Column({ space: 4 }) {
          Text($r('app.string.decrypt_title'))
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .width('100%')
            .textAlign(TextAlign.Center);
          Text(this.serverLabel)
            .fontSize(12)
            .fontColor($r('app.color.color_text_hint'))
            .width('100%')
            .textAlign(TextAlign.Center)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis });
        }
        .width('100%')
        .padding({ left: 18, right: 18, top: 18, bottom: 8 });
      }

      Scroll(this.formScroller) {
        Column({ space: 12 }) {
          Row() {
            Column({ space: 2 }) {
              Text($r('app.string.decrypt_e2e_title'))
                .fontSize(15)
                .fontColor($r('app.color.color_text_primary'));
              Text($r('app.string.decrypt_e2e_hint'))
                .fontSize(12)
                .fontColor($r('app.color.color_text_hint'));
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1);
            Toggle({ type: ToggleType.Switch, isOn: this.isEncryptionEnabled })
              .selectedColor($r('app.color.color_brand'))
              .onChange((isOn: boolean) => {
                this.isEncryptionEnabled = isOn;
              });
          }
          .width('100%');

          Text($r('app.string.decrypt_label_algorithm'))
            .fontSize(13)
            .fontColor($r('app.color.color_text_secondary'))
            .width('100%');
          Row() {
            Text(this.algorithm).fontSize(16).fontColor($r('app.color.color_text_primary'));
            Blank();
            SymbolGlyph($r('sys.symbol.chevron_down'))
              .fontSize(16)
              .fontColor([$r('app.color.color_text_primary')]);
          }
          .width('100%')
          .height(46)
          .padding({ left: 14, right: 14 })
          .backgroundColor($r('app.color.color_bg_input_glass'))
          .borderRadius(8)
          .bindMenu(this.algorithmMenu(),
            withImmersiveMenuMaterial({ placement: Placement.BottomLeft, showInSubWindow: true }));

          Text($r('app.string.decrypt_label_mode'))
            .fontSize(13)
            .fontColor($r('app.color.color_text_secondary'))
            .width('100%');
          Row() {
            Text(this.mode).fontSize(16).fontColor($r('app.color.color_text_primary'));
            Blank();
            SymbolGlyph($r('sys.symbol.chevron_down'))
              .fontSize(16)
              .fontColor([$r('app.color.color_text_primary')]);
          }
          .width('100%')
          .height(46)
          .padding({ left: 14, right: 14 })
          .backgroundColor($r('app.color.color_bg_input_glass'))
          .borderRadius(8)
          .bindMenu(this.modeMenu(),
            withImmersiveMenuMaterial({ placement: Placement.BottomLeft, showInSubWindow: true }));

          Text($r('app.string.decrypt_label_padding'))
            .fontSize(13)
            .fontColor($r('app.color.color_text_secondary'))
            .width('100%');
          Row() {
            Text(this.paddingValue).fontSize(16).fontColor($r('app.color.color_text_hint'));
          }
          .width('100%')
          .height(46)
          .padding({ left: 14, right: 14 })
          .backgroundColor($r('app.color.color_bg_input_glass'))
          .borderRadius(8);

          Text($r('app.string.decrypt_label_key'))
            .fontSize(13)
            .fontColor($r('app.color.color_text_secondary'))
            .width('100%');
          Row() {
            TextInput({
              text: this.keyText,
              placeholder: $r('app.string.decrypt_key_placeholder',
                EncryptionConfigService.expectedKeyBytes(this.algorithm)),
            })
              .layoutWeight(1)
              .height(46)
              .backgroundColor(Color.Transparent)
              .padding({ left: 12, right: 8 })
              .onChange((value: string) => {
                this.keyText = value;
              });
            Image($r('app.media.reset'))
              .width(20)
              .height(20)
              .fillColor($r('app.color.color_text_secondary'))
              .draggable(false)
              .margin({ left: 11, right: 11 })
              .onClick(() => this.generateKey());
          }
          .width('100%')
          .height(46)
          .backgroundColor($r('app.color.color_bg_input_glass'))
          .borderRadius(8);

          Text($r('app.string.decrypt_iv_note'))
            .fontSize(12)
            .fontColor($r('app.color.color_text_hint'))
            .width('100%');
          Text($r('app.string.decrypt_clear_action'))
            .fontSize(13)
            .fontColor($r('app.color.color_error'))
            .padding(8)
            .onClick(() => this.clear());
        }
        .width('100%')
        .padding({ left: 18, right: 18, top: 8, bottom: 8 });
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
      .edgeEffect(EdgeEffect.Spring)
      .clip(showFallbackTitle);

      Row({ space: 8 }) {
        Button($r('app.string.common_cancel'))
          .layoutWeight(1)
          .height(40)
          .fontSize(14)
          .backgroundColor(Color.Transparent)
          .fontColor($r('app.color.color_text_secondary'))
          .borderRadius(8)
          .onClick(() => this.controller.close());
        Button($r('app.string.common_save'))
          .layoutWeight(1)
          .height(40)
          .fontSize(14)
          .backgroundColor($r('app.color.color_brand'))
          .borderRadius(8)
          .onClick(() => this.save());
      }
      .width('100%')
      .padding({ left: 18, right: 18, top: 8, bottom: 18 });
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
    .onAppear(() => {
      this.active = true;
      this.loadConfigDisplay();
    });
  }

  build() {
    if (shouldUseSystemMaterialPath()) {
      HdsNavigation() {
        this.dialogContent(false);
      }
      .titleBar({
        enableComponentSafeArea: true,
        content: { title: { mainTitle: $r('app.string.decrypt_title'), subTitle: this.serverLabel } },
        style: {
          scrollEffectOpts: {
            enableScrollEffect: true,
            scrollEffectType: ScrollEffectType.GRADIENT_BLUR
          },
          systemMaterialEffect: {
            materialType: hdsMaterial.MaterialType.ADAPTIVE,
            materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
          }
        }
      })
      .hideBackButton(true)
      .titleMode(HdsNavigationTitleMode.MODAL)
      // 强制单栏 Stack：弹窗容器 ≥600vp 时 Auto 模式会切 Split，出现窄 navBar + 空白内容区
      .mode(NavigationMode.Stack)
      .bindToScrollable([this.formScroller])
      .width('100%')
      .height('80%')
      .backgroundColor(Color.Transparent)
      .borderRadius(14)
      .clip(true);
    } else {
      Column() {
        this.dialogContent(true);
      }
      .width('100%')
      .height('80%')
      .backgroundColor(Color.Transparent)
      .borderRadius(14)
      .clip(true);
    }
  }

  @Builder
  private algorithmMenuItems() {
    ForEach(['AES128', 'AES192', 'AES256'], (value: string) => {
      MenuItem({ content: value })
        .contentFontColor(value === this.algorithm ? $r('app.color.color_brand') :
          $r('app.color.color_text_primary'))
        .backgroundColor(value === this.algorithm ? $r('app.color.color_bg_selected_glass') : Color.Transparent)
        .onClick(() => {
          this.algorithm = value;
        });
    }, (value: string) => value);
  }

  @Builder
  private algorithmMenu() {
    Menu() {
      this.algorithmMenuItems();
    }
  }

  @Builder
  private modeMenuItems() {
    ForEach(['CBC', 'ECB', 'GCM'], (value: string) => {
      MenuItem({ content: value })
        .contentFontColor(value === this.mode ? $r('app.color.color_brand') :
          $r('app.color.color_text_primary'))
        .backgroundColor(value === this.mode ? $r('app.color.color_bg_selected_glass') : Color.Transparent)
        .onClick(() => {
          this.mode = value;
          this.paddingValue = value === 'GCM' ? 'NoPadding' : 'PKCS7';
        });
    }, (value: string) => value);
  }

  @Builder
  private modeMenu() {
    Menu() {
      this.modeMenuItems();
    }
  }

  private generateKey(): void {
    try {
      this.keyText = EncryptionConfigService.generateKey(this.algorithm);
    } catch (_err) {
      hilog.error(DOMAIN, TAG, '生成随机 Key 失败');
      showToast(this.getUIContext(), $r('app.string.decrypt_toast_generate_failed'));
    }
  }

  private buildConfig(): EncryptionConfig {
    const config = new EncryptionConfig();
    config.enabled = this.isEncryptionEnabled;
    config.algorithm = this.algorithm;
    config.mode = this.mode;
    config.padding = this.paddingValue;
    config.key = this.keyText;
    return config;
  }

  private async save(): Promise<void> {
    if (this.saving) {
      return;
    }
    if (!this.configLoaded) {
      showToast(this.getUIContext(), $r('app.string.decrypt_toast_not_loaded'));
      return;
    }
    const config: EncryptionConfig = this.buildConfig();
    const error: string = EncryptionConfigService.validate(config);
    if (error.length > 0) {
      showToast(this.getUIContext(), error);
      return;
    }
    if (this.hasExistingConfigChanged() && !await this.confirmConfigChange()) {
      return;
    }
    this.saving = true;
    try {
      if (await this.onSave(config)) {
        this.controller.close();
      }
    } catch (_err) {
      hilog.warn(DOMAIN, TAG, '保存解密配置失败');
      showToast(this.getUIContext(), $r('app.string.decrypt_toast_save_failed'));
    } finally {
      this.saving = false;
    }
  }

  private hasExistingConfigChanged(): boolean {
    return this.originalKey.length > 0 &&
      (this.keyText !== this.originalKey || this.algorithm !== this.originalAlgorithm ||
        this.mode !== this.originalMode);
  }

  private async confirmConfigChange(): Promise<boolean> {
    return this.confirmDanger($r('app.string.decrypt_confirm_change_title'),
      $r('app.string.decrypt_confirm_change_message'),
      $r('app.string.decrypt_confirm_change'));
  }

  private async confirmDanger(title: ResourceStr, message: ResourceStr,
    confirmText: ResourceStr): Promise<boolean> {
    try {
      const background = getDialogBackgroundOptions();
      return await new Promise<boolean>((resolve: (confirmed: boolean) => void) => {
        let controller: CustomDialogController | undefined;
        controller = new CustomDialogController({
          builder: DangerConfirmDialog({
            title: title,
            message: message,
            confirmText: confirmText,
            onResult: (confirmed: boolean): void => {
              controller?.close();
              resolve(confirmed);
            },
          }),
          alignment: DialogAlignment.Center,
          autoCancel: false,
          cornerRadius: 14,
          systemMaterial: background.systemMaterial,
          backgroundColor: background.backgroundColor,
          backgroundBlurStyle: background.backgroundBlurStyle,
        });
        controller.open();
      });
    } catch (_err) {
      hilog.warn(DOMAIN, TAG, '显示危险操作确认弹窗失败');
      return false;
    }
  }

  private async clear(): Promise<void> {
    if (this.saving) {
      return;
    }
    if (!this.configLoaded) {
      showToast(this.getUIContext(), $r('app.string.decrypt_toast_not_loaded'));
      return;
    }
    try {
      if (!await this.confirmDanger($r('app.string.decrypt_confirm_clear_title'),
        $r('app.string.decrypt_confirm_clear_message'),
        $r('app.string.decrypt_confirm_clear'))) {
        return;
      }
      this.saving = true;
      if (await this.onClear()) {
        this.controller.close();
      }
    } catch (_err) {
      hilog.warn(DOMAIN, TAG, '清除解密配置失败');
      showToast(this.getUIContext(), $r('app.string.decrypt_toast_clear_failed'));
    } finally {
      this.saving = false;
    }
  }

}
