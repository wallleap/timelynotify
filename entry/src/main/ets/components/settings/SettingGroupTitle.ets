/**
 * 设置分组标题：统一「外观 / 通知行为 / 关于 / 信息」等板块标题的字号、字重、颜色与左内边距，
 * 避免各设置页各自链式书写导致样式漂移。
 */
@Component
export struct SettingGroupTitle {
  // 分组标题文案
  title: string = '';
  // 标题下方补充说明（可选），用于「捐赠」等需要弱提示的分组
  hint: string = '';

  build() {
    Column({ space: 2 }) {
      Text(this.title)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.color_text_hint'))
        .width('100%');
      if (this.hint.length > 0) {
        Text(this.hint)
          .fontSize(12)
          .fontColor($r('app.color.color_text_hint'))
          .width('100%');
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 8 });
  }
}
