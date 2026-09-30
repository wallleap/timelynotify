import { hilog } from '@kit.PerformanceAnalysisKit';
import { hdsMaterial, HdsNavigation, HdsNavigationTitleMode, ScrollEffectType } from '@kit.UIDesignKit';
import { DOMAIN } from '../common/Constant';
import { shouldUseSystemMaterialPath } from '../utils/ImmersiveUtil';

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
        Text('服务器操作')
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

      Text('复制地址和 Key')
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

      Text('重置或还原 Key')
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
      Text('设置客户端 Token')
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

      Text('加密设置')
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

      Text('设置服务器名称')
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

      Text('删除服务器')
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
          content: { title: { mainTitle: '服务器操作', subTitle: this.serverLabel } },
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
  controller: CustomDialogController = new CustomDialogController({
    builder: emptyActionBuilder(),
    autoCancel: true,
    alignment: DialogAlignment.Center,
    offset: { dx: 0, dy: 0 },
  });
  @State inputName: string = '';
  // 通过回调拉取初始名（闭包捕获外层 this，open 时取最新值）
  getInitName: () => string = () => '';
  onConfirm: (newName: string) => void = (_n: string) => {
  };

  aboutToAppear() {
    this.inputName = this.getInitName();
  }

  build() {
    Column({ space: 12 }) {
      Text('设置服务器名称')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .width('100%')
        .textAlign(TextAlign.Center);

      TextInput({ placeholder: '输入新名称（留空则清除名称）', text: this.inputName })
        .width('100%')
        .height(42)
        .backgroundColor($r('app.color.color_bg_input_glass'))
        .borderRadius(8)
        .padding({ left: 12, right: 12 })
        .onChange((val: string) => {
          this.inputName = val;
        });

      Row({ space: 8 }) {
        Button('取消')
          .layoutWeight(1)
          .height(40)
          .fontSize(14)
          .backgroundColor(Color.Transparent)
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
      Text('重置或还原 Key')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .width('100%')
        .textAlign(TextAlign.Center);

      Column({ space: 4 }) {
        Text(`当前 Key：${this.currentKey && this.currentKey.length > 0 ? this.currentKey : '（未注册）'}`)
          .fontSize(12)
          .fontColor($r('app.color.color_text_hint'))
          .width('100%')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
        Text('输入框留空 = 重置（生成新 Key）；填入 Key = 还原')
          .fontSize(12)
          .fontColor($r('app.color.color_text_hint'))
          .width('100%');
      }
      .width('100%');

      TextInput({ placeholder: '可选：输入要还原的 device_key', text: this.inputKey })
        .width('100%')
        .height(42)
        .backgroundColor($r('app.color.color_bg_input_glass'))
        .borderRadius(8)
        .padding({ left: 12, right: 12 })
        .onChange((val: string) => {
          this.inputKey = val;
        });

      Row({ space: 8 }) {
        Button('取消')
          .layoutWeight(1)
          .height(40)
          .fontSize(14)
          .backgroundColor(Color.Transparent)
          .fontColor($r('app.color.color_text_secondary'))
          .borderRadius(8)
          .onClick(() => {
            this.close();
          });

        Button(this.inputKey.trim().length > 0 ? '还原' : '重置')
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
    this.close();
    this.onConfirm(k);
  }
}
