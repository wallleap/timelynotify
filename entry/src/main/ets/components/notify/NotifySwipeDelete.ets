/** 通知列表左滑操作区的统一删除按钮。 */
@Component
export struct NotifySwipeDelete {
  onDelete: () => void = () => {};

  build() {
    Row() {
      Row() {
        Image($r('app.media.delete')).width(22).height(22).objectFit(ImageFit.Contain).fillColor('#FFFFFF').draggable(false);
      }
      .width(44).height(44).borderRadius(44).justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center)
      .backgroundColor($r('app.color.text_error_color')).onClick(() => this.onDelete());
    }
    .width(68).height('100%').padding({ left: 12 }).justifyContent(FlexAlign.Start).alignItems(VerticalAlign.Center);
  }
}
