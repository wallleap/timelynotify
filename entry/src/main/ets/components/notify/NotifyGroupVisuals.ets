/** 分组通知的纯视觉元素，供折叠态与展开态复用。 */
@Component
export struct NotifyGroupCountBadge {
  @Prop count: number = 0;

  build() {
    Text(`${this.count} 条通知`)
      .fontSize(10)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.color_text_badge'))
      .padding({ left: 8, right: 8, top: 2, bottom: 2 })
      .borderRadius(10)
      .backgroundColor($r('app.color.color_bg_badge'));
  }
}

/** 通知仍携带密文时显示的状态标签；用于平铺消息、分组预览和展开行。 */
@Component
export struct NotifyEncryptionBadge {
  build() {
    Text('加密')
      .fontSize(10)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.color_brand'))
      .padding({ left: 8, right: 8, top: 2, bottom: 2 })
      .borderRadius(10)
      .backgroundColor($r('app.color.color_state_brand_selected'));
  }
}

/** 折叠分组主卡片背后的层叠壳；高度由 NotifyView 的测量状态提供。 */
@Component
export struct NotifyGroupShellLayer {
  @Prop shellHeight: number = 0;
  @Prop inset: number = 0;
  @Prop yOffset: number = 0;
  @Prop shellColor: Resource = $r('app.color.color_bg_stack_shallow');

  build() {
    Row() {
      Column().layoutWeight(1).height('100%').borderRadius(12).backgroundColor(this.shellColor);
    }
    .width('100%').height(this.shellHeight).padding({ left: this.inset, right: this.inset })
    .offset({ y: this.yOffset }).hitTestBehavior(HitTestMode.None);
  }
}
