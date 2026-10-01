/** 设置卡片内显式放置的分隔线。 */
@Component
export struct SettingDivider {
  build() {
    Divider()
      .color($r('app.color.color_border_subtle'))
      .strokeWidth(1)
      .margin({ left: 16, right: 16 });
  }
}
