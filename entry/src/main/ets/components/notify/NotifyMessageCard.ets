import { NotifyMessage } from '../../model/NotifyMessage';
import { formatNotifyTime, NOTIFY_SEGMENT_CODE, NOTIFY_SEGMENT_URL, NotifyTextSegment, parseNotifyTextSegments } from './NotifyViewTypes';

/** 单条通知卡片；详情、选择与富文本交互通过页面回调处理。 */
@Component
export struct NotifyMessageCard {
  @Prop message: NotifyMessage = new NotifyMessage();
  @Prop isEditing: boolean = false;
  @Prop selected: boolean = false;
  onSelect: (id: number) => void = (_id: number) => {};
  onOpen: (message: NotifyMessage) => void = (_message: NotifyMessage) => {};
  onOpenUrl: (url: string) => void = (_url: string) => {};
  onCopyCode: (code: string) => void = (_code: string) => {};

  @Builder
  private spans(text: string) {
    ForEach(parseNotifyTextSegments(text), (segment: NotifyTextSegment, index: number) => {
      if (segment.type === NOTIFY_SEGMENT_URL) {
        Span(segment.text).fontSize(14).fontColor($r('app.color.text_accent_color')).onClick(() => this.onOpenUrl(segment.text));
      } else if (segment.type === NOTIFY_SEGMENT_CODE) {
        Span(segment.text).fontSize(14).fontColor($r('app.color.text_accent_color')).onClick(() => this.onCopyCode(segment.text));
      } else {
        Span(segment.text).fontSize(14).fontColor($r('app.color.text_secondary_color'));
      }
    }, (segment: NotifyTextSegment, index: number) => `${index}_${segment.type}_${segment.text}`)
  }

  @Builder
  private body() {
    if (this.message.inboxContent.length > 0) {
      Column() {
        ForEach(this.message.inboxContent, (line: string, index: number) => {
          if (index < 4) {
            Text() { this.spans(line) }.width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).lineHeight(21);
          }
        }, (line: string, index: number) => `${index}_${line}`)
      }.width('100%').alignItems(HorizontalAlign.Start).margin({ top: 4 });
    } else if (this.message.body.length > 0) {
      Text() { this.spans(this.message.body) }.width('100%').maxLines(4)
        .textOverflow({ overflow: TextOverflow.Ellipsis }).lineHeight(21).margin({ top: 4 });
    }
  }

  build() {
    Row({ space: 12 }) {
      if (this.isEditing) {
        Checkbox().select(this.selected).selectedColor($r('app.color.text_accent_color')).shape(CheckBoxShape.CIRCLE);
      }
      Column({ space: 6 }) {
        Row({ space: 8 }) {
          Column() {
            if (this.message.title.length > 0) {
              Text(this.message.title).fontSize(15).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary_color'))
                .width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
            }
            if (this.message.subtitle.length > 0) {
              Text(this.message.subtitle).fontSize(13).fontColor($r('app.color.text_accent_color'))
                .width('100%').maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis });
            }
            this.body();
          }.layoutWeight(1).alignItems(HorizontalAlign.Start);
          if (this.message.image.length > 0) {
            Image(this.message.image).width(38).height(38).borderRadius(12).objectFit(ImageFit.Cover).flexShrink(0).alt($r('app.media.app_icon'));
          }
        }.width('100%').alignItems(VerticalAlign.Top);
        Text(formatNotifyTime(this.message.timestamp)).fontSize(11).fontColor($r('app.color.text_quinary_color'))
          .width('100%').textAlign(TextAlign.End);
      }.layoutWeight(1).alignItems(HorizontalAlign.Start);
    }
    .width('100%').padding(12).backgroundColor($r('app.color.card_background')).borderRadius(12).alignItems(VerticalAlign.Top)
    .onClick(() => this.isEditing ? this.onSelect(this.message.id) : this.onOpen(this.message));
  }
}
