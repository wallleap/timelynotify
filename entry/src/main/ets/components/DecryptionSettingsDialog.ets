import { hilog } from '@kit.PerformanceAnalysisKit';
import { EncryptionConfig } from '../model/EncryptionConfig';
import { EncryptionConfigService } from '../services/EncryptionConfigService';
import { DOMAIN } from '../common/Constant';
import { getDialogMaterial, withImmersiveMenuMaterial } from '../utils/ImmersiveUtil';
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

  build() {
    Column() {
      Column({ space: 4 }) {
        Text('解密设置')
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

      Scroll() {
        Column({ space: 12 }) {
          Row() {
            Column({ space: 2 }) {
              Text('端到端解密')
                .fontSize(15)
                .fontColor($r('app.color.color_text_primary'));
              Text('Key 仅保存在本机，服务器不会解密')
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

          Text('算法')
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

          Text('模式')
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

          Text('Padding（由模式自动决定）')
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

          Text('Key')
            .fontSize(13)
            .fontColor($r('app.color.color_text_secondary'))
            .width('100%');
          Row() {
            TextInput({
              text: this.keyText,
              placeholder: `请输入 ${EncryptionConfigService.expectedKeyBytes(this.algorithm)} 字节 Key`,
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

          Text('IV 不在此保存：CBC 由发送端携带 16 字节 IV，GCM 携带 12 字节 IV；ECB 无 IV。')
            .fontSize(12)
            .fontColor($r('app.color.color_text_hint'))
            .width('100%');
          Text('清除解密配置')
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
      .edgeEffect(EdgeEffect.Spring);

      Row({ space: 8 }) {
        Button('取消')
          .layoutWeight(1)
          .height(40)
          .fontSize(14)
          .backgroundColor(Color.Transparent)
          .fontColor($r('app.color.color_text_secondary'))
          .borderRadius(8)
          .onClick(() => this.controller.close());
        Button('保存')
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
    .constraintSize({ maxHeight: '80%' })
    .backgroundColor(Color.Transparent)
    .borderRadius(14)
    .onAppear(() => {
      this.active = true;
      this.loadConfigDisplay();
    });
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
      showToast(this.getUIContext(), '生成 Key 失败');
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
      showToast(this.getUIContext(), '解密配置尚未读取完成');
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
      showToast(this.getUIContext(), '保存失败');
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
    try {
      const result = await this.getUIContext().getPromptAction().showDialog({
        title: '确认更换解密配置',
        message: '请先备份当前 Key，并同步更新发送端。保存后，使用旧 Key 或旧算法加密的历史通知可能无法继续解密。',
        buttons: [
          { text: '取消', color: $r('app.color.color_text_tertiary') },
          { text: '确认更换', color: $r('app.color.color_error') },
        ],
        systemMaterial: getDialogMaterial(),
      });
      return result.index === 1;
    } catch (_err) {
      hilog.warn(DOMAIN, TAG, '显示更换解密配置确认弹窗失败');
      return false;
    }
  }

  private async clear(): Promise<void> {
    if (this.saving) {
      return;
    }
    if (!this.configLoaded) {
      showToast(this.getUIContext(), '解密配置尚未读取完成');
      return;
    }
    try {
      const result = await this.getUIContext().getPromptAction().showDialog({
        title: '清除解密配置',
        message: '清除后本机保存的 Key 将被删除，使用该 Key 加密的历史通知可能无法继续解密。请先备份 Key。',
        buttons: [
          { text: '取消', color: $r('app.color.color_text_tertiary') },
          { text: '确认清除', color: $r('app.color.color_error') },
        ],
        systemMaterial: getDialogMaterial(),
      });
      if (result.index !== 1) {
        return;
      }
      this.saving = true;
      if (await this.onClear()) {
        this.controller.close();
      }
    } catch (_err) {
      hilog.warn(DOMAIN, TAG, '清除解密配置失败');
      showToast(this.getUIContext(), '清除失败');
    } finally {
      this.saving = false;
    }
  }

}
