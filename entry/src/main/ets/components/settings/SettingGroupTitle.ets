/**
 * 设置分组标题：统一「外观 / 通知行为 / 关于 / 信息」等板块标题的字号、字重、颜色与左内边距，
 * 避免各设置页各自链式书写导致样式漂移。
 */
@Component
export struct SettingGroupTitle {
  // 分组标题文案
  title: string = '';

  build() {
    Text(this.title)
      .fontSize(14)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.color_text_hint'))
      .width('100%')
      .padding({ left: 8 });
  }
}
