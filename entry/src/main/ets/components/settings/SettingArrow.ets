/** 设置项统一的右侧箭头。 */
@Component
export struct SettingArrow {
  build() {
    Image($r('app.media.arrow_right'))
      .width(20)
      .height(20)
      .objectFit(ImageFit.Contain)
      .fillColor($r('app.color.color_text_hint'))
      .draggable(false);
  }
}
