/** 分组通知的纯视觉元素，供折叠态与展开态复用。 */
@Component
export struct NotifyGroupCountBadge {
  @Prop count: number = 0;

  build() {
    Text(`${this.count} 条通知`)
      .fontSize(10)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.group_count_badge_text'))
      .padding({ left: 8, right: 8, top: 2, bottom: 2 })
      .borderRadius(10)
      .backgroundColor($r('app.color.group_count_badge_bg'));
  }
}

/** 折叠分组主卡片背后的层叠壳；高度由 NotifyView 的测量状态提供。 */
@Component
export struct NotifyGroupShellLayer {
  @Prop shellHeight: number = 0;
  @Prop inset: number = 0;
  @Prop yOffset: number = 0;
  @Prop shellColor: Resource = $r('app.color.card_shell_shallow');

  build() {
    Row() {
      Column().layoutWeight(1).height('100%').borderRadius(12).backgroundColor(this.shellColor);
    }
    .width('100%').height(this.shellHeight).padding({ left: this.inset, right: this.inset })
    .offset({ y: this.yOffset }).hitTestBehavior(HitTestMode.None);
  }
}
