import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0000;
const TAG: string = 'ServerActionDlg';

// 空 builder 占位（给 controller 字段做默认值，避免 SDK 注入前空引用崩溃）
@Builder
function emptyActionBuilder(): void {
}

// 服务器项操作菜单（复制/重置还原Key/重命名/删除 + 右上角 close icon）
// 目标服务器由外层持有；本弹窗只负责展示选项并通过回调通知
@CustomDialog
export struct ServerActionMenuDialog {
  controller: CustomDialogController = new CustomDialogController({
    builder: emptyActionBuilder(),
    autoCancel: true,
    alignment: DialogAlignment.Center,
    offset: { dx: 0, dy: 0 },
  });

  onCopy: () => void = () => {};
  onResetKey: () => void = () => {};
  onRename: () => void = () => {};
  onDelete: () => void = () => {};

  private close(): void {
    try {
      this.controller.close();
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'close menu 失败');
    }
  }

  build() {
    Column() {
      // 顶部：标题 + 右上角 close icon
      Stack({ alignContent: Alignment.TopEnd }) {
        Text('操作')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: 6, bottom: 6 });

        Image($r('app.media.close'))
          .width(22)
          .height(22)
          .objectFit(ImageFit.Contain)
          .fillColor('#999999')
          .padding(4)
          .onClick(() => {
            this.close();
          });
      }
      .width('100%');

      Divider().color('#EEEEEE');

      Text('复制地址和 Key')
        .fontSize(16)
        .fontColor('#111111')
        .width('100%')
        .height(48)
        .textAlign(TextAlign.Center)
        .onClick(() => {
          this.close();
          this.onCopy();
        });

      Divider().color('#EEEEEE');

      Text('重置或还原 Key')
        .fontSize(16)
        .fontColor('#111111')
        .width('100%')
        .height(48)
        .textAlign(TextAlign.Center)
        .onClick(() => {
          this.close();
          this.onResetKey();
        });

      Divider().color('#EEEEEE');

      Text('设置服务器名称')
        .fontSize(16)
        .fontColor('#111111')
        .width('100%')
        .height(48)
        .textAlign(TextAlign.Center)
        .onClick(() => {
          this.close();
          this.onRename();
        });

      Divider().color('#EEEEEE');

      Text('删除服务器')
        .fontSize(16)
        .fontColor('#FF3B30')
        .width('100%')
        .height(48)
        .textAlign(TextAlign.Center)
        .onClick(() => {
          this.close();
          this.onDelete();
        });
    }
    .width('78%')
    .padding({ top: 12, bottom: 8, left: 4, right: 4 })
    .backgroundColor('#FFFFFF')
    .borderRadius(14);
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

  // 通过回调拉取初始名（闭包捕获外层 this，open 时取最新值）
  getInitName: () => string = () => '';
  onConfirm: (newName: string) => void = (_n: string) => {};

  @State inputName: string = '';

  aboutToAppear() {
    this.inputName = this.getInitName();
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
        .backgroundColor('#F5F5F5')
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
          .backgroundColor('#EEEEEE')
          .fontColor('#333333')
          .borderRadius(8)
          .onClick(() => {
            this.close();
          });

        Button('保存')
          .layoutWeight(1)
          .height(40)
          .fontSize(14)
          .backgroundColor('#FF6F22')
          .borderRadius(8)
          .onClick(() => {
            this.confirm();
          });
      }
      .width('100%');
    }
    .width('80%')
    .padding(18)
    .backgroundColor('#FFFFFF')
    .borderRadius(14);
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

  getCurrentKey: () => string = () => '';
  // inputKey 为空 = 重置；有值 = 还原
  onConfirm: (inputKey: string) => void = (_k: string) => {};

  @State inputKey: string = '';
  @State currentKey: string = '';

  aboutToAppear() {
    this.currentKey = this.getCurrentKey();
    this.inputKey = '';
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
          .fontColor('#999999')
          .width('100%')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
        Text('输入框留空 = 重置（生成新 Key）；填入 Key = 还原')
          .fontSize(12)
          .fontColor('#999999')
          .width('100%');
      }
      .width('100%');

      TextInput({ placeholder: '可选：输入要还原的 device_key', text: this.inputKey })
        .width('100%')
        .height(42)
        .backgroundColor('#F5F5F5')
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
          .backgroundColor('#EEEEEE')
          .fontColor('#333333')
          .borderRadius(8)
          .onClick(() => {
            this.close();
          });

        Button(this.inputKey.trim().length > 0 ? '还原' : '重置')
          .layoutWeight(1)
          .height(40)
          .fontSize(14)
          .backgroundColor('#FF6F22')
          .borderRadius(8)
          .onClick(() => {
            this.confirm();
          });
      }
      .width('100%');
    }
    .width('82%')
    .padding(18)
    .backgroundColor('#FFFFFF')
    .borderRadius(14);
  }
}
