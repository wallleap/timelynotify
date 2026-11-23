import { hilog } from '@kit.PerformanceAnalysisKit';
import { hdsMaterial, HdsNavigation, HdsNavigationTitleMode, ScrollEffectType } from '@kit.UIDesignKit';
import { DOMAIN } from '../common/Constant';
import { AppContextStore } from '../common/AppContextStore';
import { KEY_ANTI_PEEP_BLUR } from '../services/AntiPeepService';
import { getDialogBackgroundOptions, shouldUseSystemMaterialPath } from '../utils/ImmersiveUtil';
import { DangerConfirmDialog } from './DangerConfirmDialog';

const TAG: string = 'ServerActionDlg';

// 空 builder 占位（给 controller 字段做默认值，避免 SDK 注入前空引用崩溃）
@Builder
function emptyActionBuilder(): void {
}

// 服务器项操作菜单（复制/重置还原Key/客户端Token/重命名/删除 + 右上角 close icon）
// 目标服务器由外层持有；本弹窗只负责展示选项并通过回调通知
@CustomDialog
export struct ServerActionMenuDialog {
  controller: CustomDialogController = new CustomDialogController({
    builder: emptyActionBuilder(),
    autoCancel: true,
    alignment: DialogAlignment.Center,
    offset: { dx: 0, dy: 0 },
  });
  onCopy: () => void = () => {
  };
  onResetKey: () => void = () => {
  };
  onClientToken: () => void = () => {
  };
  onEncryption: () => void = () => {
  };
  onRename: () => void = () => {
  };
  onDelete: () => void = () => {
  };
  serverLabel: string = '';
  private actionScroller: Scroller = new Scroller();

  @Builder
  private glassCloseButton() {
    Row() {
      Image($r('app.media.close'))
        .width(20)
        .height(20)
        .objectFit(ImageFit.Contain)
        .fillColor($r('app.color.color_text_primary'))
        .draggable(false);
    }
    .width(38)
    .height(38)
    .borderRadius(38)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .border({ width: 1, color: $r('app.color.color_border_glass') })
    .backgroundColor(Color.Transparent)
    .onClick(() => this.close());
  }

  @Builder
  private fallbackTitle() {
    Row() {
      Column({ space: 2 }) {
        Text($r('app.string.srvact_menu_title'))
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.color_text_primary'));
        Text(this.serverLabel)
          .fontSize(12)
          .fontColor($r('app.color.color_text_hint'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start);
      this.glassCloseButton();
    }
    .width('100%')
    .height(64)
    .padding({ left: 16, right: 16 });
  }

  @Builder
  private actionItemsScroll() {
    Scroll(this.actionScroller) {
      Column() {
      Divider().color($r('app.color.color_border_subtle'));

      Text($r('app.string.srvact_action_copy'))
        .fontSize(16)
        .fontColor($r('app.color.color_text_primary'))
        .width('100%')
        .height(52)
        .textAlign(TextAlign.Center)
        .onClick(() => {
          this.close();
          this.onCopy();
        });

      Divider().color($r('app.color.color_border_subtle'));

      Text($r('app.string.srvact_action_reset_key'))
        .fontSize(16)
        .fontColor($r('app.color.color_text_primary'))
        .width('100%')
        .height(52)
        .textAlign(TextAlign.Center)
        .onClick(() => {
          this.close();
          this.onResetKey();
        });

      Divider().color($r('app.color.color_border_subtle'));

      // per-server 客户端 Token（X-Gotify-Key 认证）；留空走内置默认
      Text($r('app.string.srvact_action_client_token'))
        .fontSize(16)
        .fontColor($r('app.color.color_text_primary'))
        .width('100%')
        .height(52)
        .textAlign(TextAlign.Center)
        .onClick(() => {
          this.close();
          this.onClientToken();
        });

      Divider().color($r('app.color.color_border_subtle'));

      Text($r('app.string.srvact_action_decryption'))
        .fontSize(16)
        .fontColor($r('app.color.color_text_primary'))
        .width('100%')
        .height(52)
        .textAlign(TextAlign.Center)
        .onClick(() => {
          this.close();
          this.onEncryption();
        });

      Divider().color($r('app.color.color_border_subtle'));

      Text($r('app.string.srvact_action_rename'))
        .fontSize(16)
        .fontColor($r('app.color.color_text_primary'))
        .width('100%')
        .height(52)
        .textAlign(TextAlign.Center)
        .onClick(() => {
          this.close();
          this.onRename();
        });

      Divider().color($r('app.color.color_border_subtle'));

      Text($r('app.string.srvact_action_delete'))
        .fontSize(16)
        .fontColor($r('app.color.color_error'))
        .width('100%')
        .height(52)
        .textAlign(TextAlign.Center)
        .onClick(() => {
          this.close();
          this.onDelete();
        });
      }
      .width('100%')
      .padding({ top: 8, bottom: 8, left: 16, right: 16 });
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Auto)
    .edgeEffect(EdgeEffect.Spring)
    .clip(!shouldUseSystemMaterialPath());
  }

  build() {
    if (shouldUseSystemMaterialPath()) {
      Stack({ alignContent: Alignment.TopEnd }) {
        HdsNavigation() {
          this.actionItemsScroll();
        }
        .titleBar({
          enableComponentSafeArea: true,
          content: { title: { mainTitle: $r('app.string.srvact_menu_title'), subTitle: this.serverLabel } },
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
        .bindToScrollable([this.actionScroller])
        .width('100%')
        .height('100%')
        .backgroundColor(Color.Transparent);

        Row() {
          this.glassCloseButton();
        }
        .margin({ top: 12, right: 14 });
      }
      .width('100%')
      .height(400)
      .constraintSize({ maxHeight: '80%' })
      .backgroundColor(Color.Transparent)
      .borderRadius(14)
      .clip(true);
    } else {
      Column() {
        this.fallbackTitle();
        this.actionItemsScroll();
      }
      .width('100%')
      .height(400)
      .constraintSize({ maxHeight: '80%' })
      .backgroundColor(Color.Transparent)
      .borderRadius(14)
      .clip(true);
    }
  }

  private close(): void {
    try {
      this.controller.close();
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'close menu 失败');
    }
  }
}

// 重命名弹窗
@CustomDialog
export struct ServerRenameDialog {
  // 域名说明与底层服务器列表同步保护，不模糊弹窗背板。
  @StorageProp(KEY_ANTI_PEEP_BLUR) antiPeepBlur: boolean = false;
  controller: CustomDialogController = new CustomDialogController({
    builder: emptyActionBuilder(),
    autoCancel: true,
    alignment: DialogAlignment.Center,
    offset: { dx: 0, dy: 0 },
  });
  @State inputName: string = '';
  // 当前服务地址提取出的域名，仅用于留空名称时的展示说明。
  serverDomain: string = '';
  // 通过回调拉取初始名（闭包捕获外层 this，open 时取最新值）
  getInitName: () => string = () => '';
  onConfirm: (newName: string) => void = (_n: string) => {
  };

  aboutToAppear() {
    this.inputName = this.getInitName();
  }

  build() {
    Column({ space: 12 }) {
      Text($r('app.string.srvact_rename_title'))
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .width('100%')
        .textAlign(TextAlign.Center);

      Text($r('app.string.srvact_rename_hint', this.serverDomain))
        .blur(this.antiPeepBlur ? 22 : 0)
        .accessibilityLevel(this.antiPeepBlur ? 'no-hide-descendants' : 'auto')
        .fontSize(12)
        .fontColor($r('app.color.color_text_hint'))
        .width('100%')
        .textAlign(TextAlign.Center);

      TextInput({ placeholder: $r('app.string.srvact_rename_placeholder'), text: this.inputName })
        .width('100%')
        .height(42)
        .backgroundColor($r('app.color.color_bg_input_glass'))
        .borderRadius(8)
        .padding({ left: 12, right: 12 })
        .onChange((val: string) => {
          this.inputName = val;
        });

      Row({ space: 8 }) {
        Button($r('app.string.common_cancel'))
          .layoutWeight(1)
          .height(40)
          .fontSize(14)
          .backgroundColor(Color.Transparent)
          .fontColor($r('app.color.color_text_secondary'))
          .borderRadius(8)
          .onClick(() => {
            this.close();
          });

        Button($r('app.string.common_save'))
          .layoutWeight(1)
          .height(40)
          .fontSize(14)
          .backgroundColor($r('app.color.color_brand'))
          .borderRadius(8)
          .onClick(() => {
            this.confirm();
          });
      }
      .width('100%');
    }
    .padding(18)
    .backgroundColor(Color.Transparent)
    .borderRadius(14);
  }

  private close(): void {
    try {
      this.controller.close();
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'close rename 失败');
    }
  }

  private confirm(): void {
    this.close();
    this.onConfirm(this.inputName);
  }
}

// 重置 / 还原 Key 弹窗
// 输入框留空 → 重置（不带 device_key 注册，生成新 key）
// 输入框有值 → 还原（带该 device_key 注册）
@CustomDialog
export struct ServerKeyDialog {
  controller: CustomDialogController = new CustomDialogController({
    builder: emptyActionBuilder(),
    autoCancel: true,
    alignment: DialogAlignment.Center,
    offset: { dx: 0, dy: 0 },
  });
  @State inputKey: string = '';
  @State currentKey: string = '';
  getCurrentKey: () => string = () => '';
  // inputKey 为空 = 重置；有值 = 还原
  onConfirm: (inputKey: string) => void = (_k: string) => {
  };

  aboutToAppear() {
    this.currentKey = this.getCurrentKey();
    this.inputKey = '';
  }

  build() {
    Column({ space: 12 }) {
      if (this.inputKey.trim().length === 0) {
        Image($r('app.media.danger_colorful'))
          .width(48)
          .height(48)
          .objectFit(ImageFit.Contain)
          .draggable(false)
          .alignSelf(ItemAlign.Center);
      }
      Text($r('app.string.srvact_action_reset_key'))
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .width('100%')
        .textAlign(TextAlign.Center);

      Column({ space: 4 }) {
        Text($r('app.string.srvact_key_current',
          this.currentKey && this.currentKey.length > 0 ? this.currentKey : this.unregisteredText()))
          .fontSize(12)
          .fontColor($r('app.color.color_text_hint'))
          .width('100%')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
        Text($r('app.string.srvact_key_help'))
          .fontSize(12)
          .fontColor($r('app.color.color_text_hint'))
          .width('100%');
      }
      .width('100%');

      TextInput({ placeholder: $r('app.string.srvact_key_placeholder'), text: this.inputKey })
        .width('100%')
        .height(42)
        .backgroundColor($r('app.color.color_bg_input_glass'))
        .borderRadius(8)
        .padding({ left: 12, right: 12 })
        .onChange((val: string) => {
          this.inputKey = val;
        });

      Row({ space: 8 }) {
        Button($r('app.string.common_cancel'))
          .layoutWeight(1)
          .height(40)
          .fontSize(14)
          .backgroundColor(Color.Transparent)
          .fontColor($r('app.color.color_text_secondary'))
          .borderRadius(8)
          .onClick(() => {
            this.close();
          });

        Button(this.inputKey.trim().length > 0 ?
          $r('app.string.srvact_key_restore') : $r('app.string.srvact_key_reset'))
          .layoutWeight(1)
          .height(40)
          .fontSize(14)
          .backgroundColor($r('app.color.color_brand'))
          .borderRadius(8)
          .onClick(() => {
            this.confirm();
          });
      }
      .width('100%');
    }
    .padding(18)
    .backgroundColor(Color.Transparent)
    .borderRadius(14);
  }

  private close(): void {
    try {
      this.controller.close();
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'close key 失败');
    }
  }

  private confirm(): void {
    const k: string = this.inputKey.trim();
    if (k.length === 0) {
      const background = getDialogBackgroundOptions();
      let controller: CustomDialogController | undefined;
      controller = new CustomDialogController({
        builder: DangerConfirmDialog({
          title: $r('app.string.srvact_key_confirm_reset_title'),
          message: $r('app.string.srvact_key_confirm_reset_message'),
          confirmText: $r('app.string.srvact_key_confirm_reset'),
          onResult: (confirmed: boolean): void => {
            controller?.close();
            if (confirmed) {
              this.close();
              this.onConfirm('');
            }
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
      return;
    }
    this.close();
    this.onConfirm(k);
  }

  // 未注册占位需要原始 string，参与 %s 格式化
  private unregisteredText(): string {
    const context = AppContextStore.getInstance().getContext();
    return context ? context.resourceManager.getStringSync($r('app.string.srvact_key_unregistered').id) : '';
  }
}
