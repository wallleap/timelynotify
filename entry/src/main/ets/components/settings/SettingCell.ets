/** 普通设置行：统一文本和留白，右侧控件由调用方提供。 */
@Component
export struct SettingCell {
  title: string = '';
  // 仅需要图标的入口传入，普通设置行保持原有布局。
  icon?: Resource;
  description?: string;
  // 保留已有状态描述的强调色；不在基础组件里判断业务状态。
  descriptionColor?: ResourceColor;
  // 构建信息的单行省略规则由调用方指定，其它描述保持原有自然换行。
  descriptionMaxLines: number = 100;
  // 无点击行为的 Toggle / Select 行不触发业务回调。
  clickable: boolean = false;
  onActivate: () => void = () => {};
  // 右侧由调用方提供控件，Cell 不持有业务状态。
  @BuilderParam trailing: () => void;

  build() {
    Row({ space: 12 }) {
      if (this.icon !== undefined) {
        Image(this.icon)
          .width(24)
          .height(24)
          .objectFit(ImageFit.Contain)
          .fillColor($r('app.color.color_text_tertiary'))
          .draggable(false);
      }
      if (this.description !== undefined) {
        Column({ space: 4 }) {
          Text(this.title)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.color_text_primary'));
          Text(this.description)
            .fontSize(12)
            .fontColor(this.descriptionColor ?? $r('app.color.color_text_hint'))
            .maxLines(this.descriptionMaxLines)
            .textOverflow({ overflow: TextOverflow.Ellipsis });
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1);
      } else {
        Text(this.title)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.color_text_primary'))
          .layoutWeight(1);
      }
      this.trailing();
    }
    .width('100%')
    .padding(16)
    .onClick(() => {
      if (this.clickable) {
        this.onActivate();
      }
    });
  }
}
