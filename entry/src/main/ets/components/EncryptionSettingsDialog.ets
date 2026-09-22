import { hilog } from '@kit.PerformanceAnalysisKit';
import { DOMAIN } from '../common/Constant';
import { EncryptionConfig } from '../model/EncryptionConfig';
import { EncryptionConfigService } from '../services/EncryptionConfigService';
import showToast from './showToast';

const TAG: string = 'EncryptionDlg';

@Builder
function emptyEncryptionBuilder(): void {
}

// 每台服务器独立的端到端解密设置。IV 由发送端逐条生成，因此本地不提供 IV 输入框。
@CustomDialog
export struct EncryptionSettingsDialog {
  controller: CustomDialogController = new CustomDialogController({
    builder: emptyEncryptionBuilder(),
    autoCancel: true,
    alignment: DialogAlignment.Center,
  });
  @State isEncryptionEnabled: boolean = false;
  @State algorithm: string = 'AES128';
  @State mode: string = 'CBC';
  @State keyText: string = '';
  private originalAlgorithm: string = 'AES128';
  private originalMode: string = 'CBC';
  private originalKeyText: string = '';
  getConfig: () => EncryptionConfig = () => new EncryptionConfig();
  getServerName: () => string = () => '';
  onSave: (config: EncryptionConfig) => void = (_config: EncryptionConfig) => {
  };
  onClear: () => void = () => {
  };

  aboutToAppear(): void {
    const config: EncryptionConfig = this.getConfig();
    this.isEncryptionEnabled = config.enabled;
    this.algorithm = config.algorithm;
    this.mode = config.mode;
    this.keyText = config.key;
    // 保存弹窗打开时的有效配置，用于判断本次保存是否会让旧密文失去对应的解密参数。
    this.originalAlgorithm = config.algorithm;
    this.originalMode = config.mode;
    this.originalKeyText = config.key;
  }

  build() {
    Scroll() {
      Column({ space: 12 }) {
        Text('加密设置')
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .width('100%')
          .textAlign(TextAlign.Center);
        Text(this.getServerName())
          .fontSize(12)
          .fontColor($r('app.color.color_text_hint'))
          .width('100%')
          .textAlign(TextAlign.Center)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });

        Row() {
          Column({ space: 2 }) {
            Text('端到端解密').fontSize(15).fontColor($r('app.color.color_text_primary'));
            Text('Key 仅保存在本机，服务器不会解密')
              .fontSize(12)
              .fontColor($r('app.color.color_text_hint'));
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1);
          Toggle({ type: ToggleType.Switch, isOn: this.isEncryptionEnabled })
            .selectedColor($r('app.color.color_brand'))
            .onChange((value: boolean) => {
              this.isEncryptionEnabled = value;
            });
        }
        .width('100%');

        Text('算法').fontSize(13).fontColor($r('app.color.color_text_secondary')).width('100%');
        Row() {
          Text(this.algorithm)
            .fontSize(16)
            .fontColor($r('app.color.color_text_primary'));
          Blank();
          SymbolGlyph($r('sys.symbol.chevron_down'))
            .fontSize(16)
            .fontColor([$r('app.color.color_text_primary')]);
        }
          .width('100%')
          .height(46)
          .padding({ left: 14, right: 14 })
          .backgroundColor($r('app.color.color_bg_input'))
          .borderRadius(8)
          .bindMenu(this.algorithmMenu(), { placement: Placement.BottomLeft });
        Text('模式').fontSize(13).fontColor($r('app.color.color_text_secondary')).width('100%');
        Row() {
          Text(this.mode)
            .fontSize(16)
            .fontColor($r('app.color.color_text_primary'));
          Blank();
          SymbolGlyph($r('sys.symbol.chevron_down'))
            .fontSize(16)
            .fontColor([$r('app.color.color_text_primary')]);
        }
          .width('100%')
          .height(46)
          .padding({ left: 14, right: 14 })
          .backgroundColor($r('app.color.color_bg_input'))
          .borderRadius(8)
          .bindMenu(this.modeMenu(), { placement: Placement.BottomLeft });
        Text('Padding（由模式自动决定）')
          .fontSize(13)
          .fontColor($r('app.color.color_text_secondary'))
          .width('100%');
        Row() {
          Text(this.paddingForMode())
            .fontSize(16)
            .fontColor($r('app.color.color_text_hint'));
        }
          .width('100%')
          .height(46)
          .padding({ left: 14, right: 14 })
          .backgroundColor($r('app.color.color_bg_input'))
          .borderRadius(8);

        Text('Key').fontSize(13).fontColor($r('app.color.color_text_secondary')).width('100%');
        Row() {
          TextInput({
            placeholder: `请输入 ${EncryptionConfigService.expectedKeyBytes(this.algorithm)} 字节 Key`,
            text: this.keyText,
          })
            .type(InputType.Normal)
            .layoutWeight(1)
            .height(46)
            .backgroundColor(Color.Transparent)
            .padding({ left: 12, right: 8 })
            .onChange((value: string) => {
              this.keyText = value;
            });
          Row() {
            Image($r('app.media.reset'))
              .width(20)
              .height(20)
              .fillColor($r('app.color.color_text_secondary'))
              .draggable(false);
          }
            .width(42)
            .height(46)
            .justifyContent(FlexAlign.Center)
            .onClick(() => this.generateKey());
        }
          .height(46)
          .width('100%')
          .backgroundColor($r('app.color.color_bg_input'))
          .borderRadius(8);
        Text('IV 不在此保存：CBC 由发送端携带 16 字节 IV，GCM 携带 12 字节 IV；ECB 无 IV。')
          .fontSize(12)
          .fontColor($r('app.color.color_text_hint'))
          .width('100%');

        Text('清除加密配置')
          .fontSize(13)
          .fontColor($r('app.color.color_error'))
          .padding(8)
          .onClick(() => {
            this.close();
            this.onClear();
          });

        Row({ space: 8 }) {
          Button('取消')
            .layoutWeight(1)
            .height(40)
            .fontSize(14)
            .backgroundColor($r('app.color.color_border_subtle'))
            .fontColor($r('app.color.color_text_secondary'))
            .borderRadius(8)
            .onClick(() => {
              this.close();
            });
          Button('保存')
            .layoutWeight(1)
            .height(40)
            .fontSize(14)
            .backgroundColor($r('app.color.color_brand'))
            .borderRadius(8)
            .onClick(() => this.save());
        }
        .width('100%');
      }
      .width('100%')
      .padding(18);
    }
    .width('92%')
    .constraintSize({ maxHeight: '80%' })
    // 系统滚动条会在自定义圆角弹窗内额外缩进；隐藏指示条但保留手势滚动。
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .backgroundColor($r('app.color.color_bg_surface'))
    .borderRadius(14);
  }

  @Builder
  private algorithmMenu() {
    Menu() {
      ForEach(['AES128', 'AES192', 'AES256'], (value: string) => {
        MenuItem({ content: value })
          .contentFontColor(value === this.algorithm ? $r('app.color.color_brand') :
            $r('app.color.color_text_primary'))
          .backgroundColor(value === this.algorithm ? $r('app.color.color_state_selected') : Color.Transparent)
          .onClick(() => {
            this.algorithm = value;
          });
      }, (value: string) => value);
    }
    .backgroundColor($r('app.color.color_bg_surface'));
  }

  @Builder
  private modeMenu() {
    Menu() {
      ForEach(['CBC', 'ECB', 'GCM'], (value: string) => {
        MenuItem({ content: value })
          .contentFontColor(value === this.mode ? $r('app.color.color_brand') :
            $r('app.color.color_text_primary'))
          .backgroundColor(value === this.mode ? $r('app.color.color_state_selected') : Color.Transparent)
          .onClick(() => {
            this.mode = value;
          });
      }, (value: string) => value);
    }
    .backgroundColor($r('app.color.color_bg_surface'));
  }

  private paddingForMode(): string {
    return this.mode === 'GCM' ? 'NoPadding' : 'PKCS7';
  }

  /** 生成符合当前 AES 算法长度的 Key，并替换输入框中的现有内容。 */
  private generateKey(): void {
    try {
      this.keyText = EncryptionConfigService.generateKey(this.algorithm);
    } catch (_err) {
      hilog.error(DOMAIN, TAG, '生成随机 Key 失败');
      showToast(this.getUIContext(), '生成 Key 失败');
    }
  }

  private async save(): Promise<void> {
    const config = new EncryptionConfig();
    config.enabled = this.isEncryptionEnabled;
    config.algorithm = this.algorithm;
    config.mode = this.mode;
    config.padding = this.paddingForMode();
    config.key = this.keyText;
    const error: string = EncryptionConfigService.validate(config);
    if (error.length > 0) {
      showToast(this.getUIContext(), error);
      return;
    }
    if (this.hasExistingConfigChanged() && !await this.confirmConfigChange()) {
      return;
    }
    this.close();
    this.onSave(config);
  }

  /** 已存在 Key 时，修改 Key、算法或模式都会影响旧密文的解密能力。 */
  private hasExistingConfigChanged(): boolean {
    return this.originalKeyText.length > 0 &&
      (this.keyText !== this.originalKeyText || this.algorithm !== this.originalAlgorithm ||
        this.mode !== this.originalMode);
  }

  /** 更换有效解密配置前要求用户确认发送端同步和历史消息影响。 */
  private async confirmConfigChange(): Promise<boolean> {
    try {
      const result = await this.getUIContext().getPromptAction().showDialog({
        title: '确认更换解密配置',
        message: '请先备份当前 Key，并同步更新发送端。保存后，使用旧 Key 或旧算法加密的历史通知可能无法继续解密。',
        buttons: [
          { text: '取消', color: $r('app.color.color_text_tertiary') },
          { text: '确认更换', color: $r('app.color.color_error') },
        ],
      });
      return result.index === 1;
    } catch (err) {
      const message: string = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, TAG, '显示更换 Key 确认弹窗失败：%{public}s', message);
      return false;
    }
  }

  private close(): void {
    try {
      this.controller.close();
    } catch (_err) {
      hilog.warn(DOMAIN, TAG, 'close encryption dialog 失败');
    }
  }
}
