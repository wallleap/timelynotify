/** 删除、清除等不可恢复操作共用的确认弹窗。 */
@Builder
function emptyDangerConfirmBuilder(): void {
}

@CustomDialog
export struct DangerConfirmDialog {
  controller: CustomDialogController = new CustomDialogController({
    builder: emptyDangerConfirmBuilder(),
    autoCancel: false,
    alignment: DialogAlignment.Center,
  });
  title: string = '';
  message: string = '';
  confirmText: string = '确定';
  onResult: (confirmed: boolean) => void = (_confirmed: boolean) => {};

  build() {
    Column({ space: 0 }) {
      Image($r('app.media.danger_colorful'))
        .width(48)
        .height(48)
        .objectFit(ImageFit.Contain)
        .draggable(false)
        .margin({ bottom: 10 });
      Text(this.title)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.color_text_primary'))
        .textAlign(TextAlign.Center)
        .width('100%');
      Scroll() {
        Text(this.message)
          .fontSize(14)
          .fontColor($r('app.color.color_text_secondary'))
          .textAlign(TextAlign.Center)
          .width('100%');
      }
      .width('100%')
      .constraintSize({ maxHeight: 240 })
      .margin({ top: 12, bottom: 18 });
      Row({ space: 8 }) {
        Button('取消')
          .layoutWeight(1)
          .height(42)
          .fontSize(14)
          .backgroundColor(Color.Transparent)
          .fontColor($r('app.color.color_text_secondary'))
          .onClick(() => this.finish(false));
        Button(this.confirmText)
          .layoutWeight(1)
          .height(42)
          .fontSize(14)
          .backgroundColor($r('app.color.color_error'))
          .fontColor(Color.White)
          .onClick(() => this.finish(true));
      }
      .width('100%');
    }
    .width('100%')
    .padding(18)
    .backgroundColor(Color.Transparent)
    .borderRadius(14);
  }

  private finish(confirmed: boolean): void {
    // controller 由创建方持有；在此实例上直接读取可能尚未注入。
    this.onResult(confirmed);
  }
}
