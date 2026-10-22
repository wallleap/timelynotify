/**
 * 列表分页及空结果状态提示：统一字号、语义颜色和加载指示器，自动适配亮暗主题。
 * 状态优先级为加载中、失败、可加载更多、已到底。
 *
 * 调用方保留 ListItem 和点击回调，本组件只负责展示，不查询数据、不管理分页。
 * 使用示例：ListItem() { ListStatusFooter({ loading: loading, hasMore: hasMore, failed: failed }) }
 * 普通列表使用默认 40vp 高度，组内底栏可传 rowHeight: 44 保留卡片布局。
 * 空结果可传 emptyText；搜索等场景通过 loadingText、failureText 保留业务文案。
 */
@Component
export struct ListStatusFooter {
  // 请求执行期间展示转圈与加载文字，优先于旧的失败或分页状态。
  @Prop loading: boolean = false;
  // 是否存在下一页；加载及失败状态结束后才用于决定提示文字。
  @Prop hasMore: boolean = false;
  // 加载失败时提示用户重试，重试动作由外层列表项处理。
  @Prop failed: boolean = false;
  // 仅定制文案，各业务继续共用同一套视觉规则和状态优先级。
  @Prop loadingText: string = '加载中...';
  @Prop failureText: string = '加载失败，点击重试';
  @Prop emptyText: string = '没有更多了';
  // 底栏高度（vp），默认与普通通知列表一致。
  @Prop rowHeight: number = 40;

  build() {
    Row() {
      if (this.loading) {
        LoadingProgress().width(16).height(16).color($r('app.color.color_brand'));
        Text(this.loadingText).fontSize(13).fontColor($r('app.color.color_text_hint')).margin({ left: 6 });
      } else if (this.failed) {
        Text(this.failureText).fontSize(13).fontColor($r('app.color.color_error'));
      } else if (this.hasMore) {
        Text('加载更多').fontSize(13).fontColor($r('app.color.color_brand'));
      } else {
        Text(this.emptyText).fontSize(13).fontColor($r('app.color.color_text_hint'));
      }
    }
    .width('100%').height(this.rowHeight)
    .justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center);
  }
}
