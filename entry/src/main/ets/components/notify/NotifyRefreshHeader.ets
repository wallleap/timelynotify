/** 通知列表下拉刷新指示器，按沉浸式布局自动留出标题栏空间。 */
@Component
export struct NotifyRefreshHeader {
  @Prop refreshState: RefreshStatus = RefreshStatus.Inactive;
  @Prop statusBarHeight: number = 0;
  @Prop immersiveEnabled: boolean = false;

  build() {
    Column() {
      Row().height(this.immersiveEnabled ? 8 : this.statusBarHeight + 80);
      if (this.refreshState !== RefreshStatus.Inactive) {
        LoadingProgress().width(28).height(28).color($r('app.color.color_brand'));
      }
    }.width('100%').alignItems(HorizontalAlign.Center);
  }
}
