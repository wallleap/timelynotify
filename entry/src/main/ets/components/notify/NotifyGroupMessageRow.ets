import { NotifyMessage } from '../../model/NotifyMessage';
import { formatNotifyTime, NOTIFY_SEGMENT_CODE, NOTIFY_SEGMENT_URL, NotifyTextSegment, parseNotifyTextSegments } from './NotifyViewTypes';

/** 展开分组内的一条消息行，保留共享元素转场、富文本与选择交互。 */
@Component
export struct NotifyGroupMessageRow {
  @Prop message: NotifyMessage = new NotifyMessage();
  @Prop isLast: boolean = false;
  @Prop isEditing: boolean = false;
  @Prop selected: boolean = false;
  @Prop contentTransitionId: string = '';
  onSelect: (id: number) => void = (_id: number) => {};
  onOpen: (message: NotifyMessage) => void = (_message: NotifyMessage) => {};
  onOpenUrl: (url: string) => void = (_url: string) => {};
  onCopyCode: (code: string) => void = (_code: string) => {};
  onCopyUrl: (url: string) => void = (_url: string) => {};

  @Builder
  private spans(text: string) {
    ForEach(parseNotifyTextSegments(text), (segment: NotifyTextSegment, index: number) => {
      if (segment.type === NOTIFY_SEGMENT_URL) {
        Span(segment.text).fontSize(14).fontColor($r('app.color.link_color')).onClick(() => this.onOpenUrl(segment.text));
      } else if (segment.type === NOTIFY_SEGMENT_CODE) {
        Span(segment.text).fontSize(14).fontColor($r('app.color.text_accent_color')).onClick(() => this.onCopyCode(segment.text));
      } else {
        Span(segment.text).fontSize(14).fontColor($r('app.color.text_secondary_color'));
      }
    }, (segment: NotifyTextSegment, index: number) => `${index}_${segment.type}_${segment.text}`)
  }

  @Builder
  private linkActions(url: string) {
    if (url.length > 0) {
      // 贴在消息行底部的浅灰操作区，复制（灰）/打开（主色）两项等宽排列。
      Row() {
        Row({ space: 4 }) {
          Image($r('app.media.copy')).width(13).height(13).fillColor($r('app.color.text_secondary_color')).draggable(false)
            .objectFit(ImageFit.Contain).flexShrink(0);
          Text('复制链接').fontSize(13).fontColor($r('app.color.text_secondary_color'));
        }.layoutWeight(1).justifyContent(FlexAlign.Center)
          .onClick(() => this.onCopyUrl(url));
        Divider().vertical(true).strokeWidth(1).color($r('app.color.text_quinary_color')).height(16).opacity(0.35);
        Row({ space: 4 }) {
          Image($r('app.media.url')).width(13).height(13).fillColor($r('app.color.text_accent_color')).draggable(false)
            .objectFit(ImageFit.Contain).flexShrink(0);
          Text('打开链接').fontSize(13).fontColor($r('app.color.text_accent_color'));
        }.layoutWeight(1).justifyContent(FlexAlign.Center)
          .onClick(() => this.onOpenUrl(url));
      }
      .width('100%').padding({ top: 10, bottom: 10 })
      .backgroundColor($r('app.color.link_action_background')).alignItems(VerticalAlign.Center);
    }
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
      }.width('100%').margin({ top: 4 });
    } else if (this.message.body.length > 0) {
      Text() { this.spans(this.message.body) }.width('100%').maxLines(4).textOverflow({ overflow: TextOverflow.Ellipsis }).lineHeight(21).margin({ top: 4 });
    }
  }

  build() {
    Stack({ alignContent: Alignment.BottomStart }) {
      Column() {
        Row({ space: 12 }) {
          if (this.isEditing) {
            Checkbox().select(this.selected).selectedColor($r('app.color.text_accent_color')).shape(CheckBoxShape.CIRCLE).flexShrink(0);
          }
          Column({ space: 6 }) {
            Row({ space: 8 }) {
              Column() {
                if (this.message.title.length > 0) {
                  Text(this.message.title).fontSize(15).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary_color')).width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
                }
                if (this.message.subtitle.length > 0) {
                  Text(this.message.subtitle).fontSize(13).fontColor($r('app.color.text_accent_color')).width('100%').maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis });
                }
                this.body();
              }.layoutWeight(1).alignItems(HorizontalAlign.Start);
              if (this.message.image.length > 0) {
                Image(this.message.image).width(38).height(38).borderRadius(12).objectFit(ImageFit.Cover).flexShrink(0).alt($r('app.media.app_icon'));
              }
            }.width('100%').alignItems(VerticalAlign.Top).geometryTransition(this.contentTransitionId)
              .transition(TransitionEffect.OPACITY.animation({ duration: 200 }));
            Text(formatNotifyTime(this.message.timestamp)).fontSize(11).fontColor($r('app.color.text_quinary_color')).width('100%').textAlign(TextAlign.End);
          }.layoutWeight(1).alignItems(HorizontalAlign.Start);
        }.width('100%').alignItems(VerticalAlign.Top).padding({ left: 12, right: 12, top: 12, bottom: 12 });
        if (this.message.url.length > 0) {
          this.linkActions(this.message.url);
        }
      }.width('100%');
      if (!this.isLast) {
        Divider().color($r('app.color.divider_color')).strokeWidth(0.5).width('100%').margin({ left: 12 });
      }
    }
    .width('100%').backgroundColor($r('app.color.card_background'))
    .borderRadius({ topLeft: 0, topRight: 0, bottomLeft: this.isLast ? 12 : 0, bottomRight: this.isLast ? 12 : 0 })
    .clip(true).transition(TransitionEffect.OPACITY.animation({ duration: 200 }))
    .onClick(() => this.isEditing ? this.onSelect(this.message.id) : this.onOpen(this.message));
  }
}
