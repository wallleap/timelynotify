import { displayGroupTitle, NotifySection } from './NotifyViewTypes';
import { NotifyGroupCountBadge } from './NotifyGroupVisuals';

/** 展开态分组头；选择与收起行为由 NotifyView 回调处理。 */
@Component
export struct NotifyGroupExpandedHeader {
  @Prop section: NotifySection = { key: '', groupKey: '', messages: [], grouped: false, total: 0 };
  @Prop isEditing: boolean = false;
  @Prop groupSelected: boolean = false;
  onToggle: () => void = () => {};

  build() {
    Column() {
      Row({ space: 8 }) {
        if (this.isEditing) {
          Checkbox().select(this.groupSelected).selectedColor($r('app.color.text_accent_color')).shape(CheckBoxShape.CIRCLE);
        } else if (this.section.messages[0].image.length > 0) {
          Image(this.section.messages[0].image).width(24).height(24).borderRadius(6).objectFit(ImageFit.Cover).alt($r('app.media.app_icon'));
        } else {
          Image($r('app.media.app_icon')).width(24).height(24).borderRadius(6).objectFit(ImageFit.Cover).draggable(false);
        }
        Text(displayGroupTitle(this.section.groupKey)).fontSize(15).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary_color'))
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1);
        Row() { NotifyGroupCountBadge({ count: this.section.total }); }
          .flexShrink(0).geometryTransition(`gmb:${this.section.groupKey}`)
          .transition(TransitionEffect.OPACITY.animation({ duration: 200 }));
        Image($r('app.media.arrow_right')).width(20).height(20).fillColor($r('app.color.text_quinary_color')).draggable(false)
          .rotate({ angle: -90 }).padding({ left: 4, top: 2, bottom: 2 });
      }.width('100%').padding(12).alignItems(VerticalAlign.Center);
      Divider().color($r('app.color.divider_color')).strokeWidth(0.5).margin({ left: 12 });
    }
    .width('100%').backgroundColor($r('app.color.card_background'))
    .borderRadius({ topLeft: 12, topRight: 12, bottomLeft: 0, bottomRight: 0 })
    .hitTestBehavior(HitTestMode.Block).onClick(() => this.onToggle())
    .transition(TransitionEffect.OPACITY.animation({ duration: 200 }));
  }
}
