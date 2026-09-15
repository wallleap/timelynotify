import { formatNotifyTime, NOTIFY_SEGMENT_CODE, NOTIFY_SEGMENT_URL, NotifySection, NotifyTextSegment, parseNotifyTextSegments } from './NotifyViewTypes';
import { NotifyGroupCountBadge, NotifyGroupShellLayer } from './NotifyGroupVisuals';

/** 折叠态分组卡片，页面负责持有展开状态、高度和实际操作。 */
@Component
export struct NotifyGroupCard {
  @Prop section: NotifySection = { key: '', groupKey: '', messages: [], grouped: false };
  @Prop isEditing: boolean = false;
  @Prop groupSelected: boolean = false;
  @Prop cardHeight: number = 0;
  onToggleSelection: () => void = () => {};
  onOpen: () => void = () => {};
  onHeightChange: (height: number) => void = (_height: number) => {};
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
    const message = this.section.messages[0];
    if (message.inboxContent.length > 0) {
      Column() {
        ForEach(message.inboxContent, (line: string, index: number) => {
          if (index < 4) {
            Text() { this.spans(line) }.width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).lineHeight(21);
          }
        }, (line: string, index: number) => `${index}_${line}`)
      }.width('100%').margin({ top: 4 });
    } else if (message.body.length > 0) {
      Text() { this.spans(message.body) }.width('100%').maxLines(4).textOverflow({ overflow: TextOverflow.Ellipsis }).lineHeight(21).margin({ top: 4 });
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.section.messages.length >= 3 && this.cardHeight > 0) {
        NotifyGroupShellLayer({ shellHeight: this.cardHeight, inset: 16, yOffset: 18,
          shellColor: $r('app.color.card_shell_deep') });
      }
      if (this.section.messages.length >= 2 && this.cardHeight > 0) {
        NotifyGroupShellLayer({ shellHeight: this.cardHeight, inset: 8, yOffset: 9,
          shellColor: $r('app.color.card_shell_shallow') });
      }
      Row({ space: 12 }) {
        if (this.isEditing) {
          Checkbox().select(this.groupSelected).selectedColor($r('app.color.text_accent_color'))
            .shape(CheckBoxShape.CIRCLE);
        }
        Column({ space: 6 }) {
          Row({ space: 8 }) {
            Column() {
              if (this.section.messages[0].title.length > 0) {
                Text(this.section.messages[0].title).fontSize(15).fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.text_primary_color')).width('100%').maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis });
              }
              if (this.section.messages[0].subtitle.length > 0) {
                Text(this.section.messages[0].subtitle).fontSize(13).fontColor($r('app.color.text_accent_color'))
                  .width('100%').maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis });
              }
              this.body();
            }.layoutWeight(1);
            if (this.section.messages[0].image.length > 0) {
              Image(this.section.messages[0].image).width(38).height(38).borderRadius(12).objectFit(ImageFit.Cover).alt($r('app.media.app_icon'));
            }
          }
          .width('100%').alignItems(VerticalAlign.Top).geometryTransition(`gmc:${this.section.groupKey}`)
          .transition(TransitionEffect.OPACITY.animation({ duration: 200 }));
          Row() {
            Row() { NotifyGroupCountBadge({ count: this.section.messages.length }); }
              .geometryTransition(`gmb:${this.section.groupKey}`);
            Blank();
            Text(formatNotifyTime(this.section.messages[0].timestamp)).fontSize(11)
              .fontColor($r('app.color.text_quinary_color'));
          }.width('100%');
        }.layoutWeight(1);
      }
      .width('100%').padding(12).backgroundColor($r('app.color.card_background')).borderRadius(12)
      .onAreaChange((_old: Area, value: Area) => this.onHeightChange(value.height as number))
      .onClick(() => this.isEditing ? this.onToggleSelection() : this.onOpen());
    }
    .width('100%').padding({ bottom: this.section.messages.length >= 3 ? 18 : 9 });
  }
}
