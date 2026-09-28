/** 通知列表下拉刷新指示器，复用列表实测的顶部遮挡距离。 */
@Component
export struct NotifyRefreshHeader {
  @Prop refreshState: RefreshStatus = RefreshStatus.Inactive;
  @Prop topInset: number = 0;

  build() {
    Column() {
      Row().height(this.topInset + 16);
      if (this.refreshState !== RefreshStatus.Inactive) {
        LoadingProgress().width(28).height(28).color($r('app.color.color_brand'));
      }
    }.width('100%').alignItems(HorizontalAlign.Center);
  }
}
