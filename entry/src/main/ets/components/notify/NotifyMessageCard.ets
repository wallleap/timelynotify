import { NotifyMessage } from '../../model/NotifyMessage';
import {
  formatNotifyTime,
  isExpiringSoon,
  NOTIFY_SEGMENT_CODE,
  NOTIFY_SEGMENT_URL,
  NotifyTextSegment,
  parseNotifyTextSegments
} from './NotifyViewTypes';
import { NotifyEncryptionBadge, NotifyExpiryBadge } from './NotifyGroupVisuals';

/** 单条通知卡片；详情、选择与富文本交互通过页面回调处理。 */
@Component
export struct NotifyMessageCard {
  @Prop message: NotifyMessage = new NotifyMessage();
  @Prop isEditing: boolean = false;
  @Prop selected: boolean = false;
  onSelect: (id: number) => void = (_id: number) => {
  };
  onSelectionChange: (id: number, selected: boolean) => void = (_id: number, _selected: boolean) => {
  };
  onOpen: (message: NotifyMessage) => void = (_message: NotifyMessage) => {
  };
  onOpenUrl: (url: string) => void = (_url: string) => {
  };
  onCopyCode: (code: string) => void = (_code: string) => {
  };
  onCopyUrl: (url: string) => void = (_url: string) => {
  };

  build() {
    Column() {
      Row({ space: 12 }) {
        if (this.isEditing) {
          Checkbox().select(this.selected).selectedColor($r('app.color.color_brand')).shape(CheckBoxShape.CIRCLE)
            .onChange((selected: boolean) => this.onSelectionChange(this.message.id, selected));
        }
        if (this.message.icon.length > 0) {
          Image(this.message.icon)
            .width(40)
            .height(40)
            .borderRadius(40)
            .objectFit(ImageFit.Cover)
            .flexShrink(0)
            .alt($r('app.media.app_icon'));
        }
        Column({ space: 6 }) {
          // 首行固定为标题与时间，便于快速扫描通知来源和发生时间。
          Row({ space: 8 }) {
            if (this.message.title.length > 0) {
              Text(this.message.title)
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.color_text_primary'))
                .layoutWeight(1)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis });
            } else {
              Blank().layoutWeight(1);
            }
            if (isExpiringSoon(this.message.expiresAt)) {
              NotifyExpiryBadge();
            }
            Text(formatNotifyTime(this.message.timestamp))
              .fontSize(11)
              .fontColor($r('app.color.color_text_hint'))
              .flexShrink(0);
          }.width('100%').alignItems(VerticalAlign.Center);

          // 第二行正文与内容图并列；副标题作为正文的语义补充保留在左侧。
          Row({ space: 8 }) {
            Column() {
              if (this.message.subtitle.length > 0) {
                Text(this.message.subtitle)
                  .fontSize(13)
                  .fontColor($r('app.color.color_brand'))
                  .width('100%')
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis });
              }
              this.body();
            }.layoutWeight(1).alignItems(HorizontalAlign.Start);

            if (this.message.image.length > 0) {
              Image(this.message.image)
                .width(38)
                .height(38)
                .borderRadius(12)
                .objectFit(ImageFit.Cover)
                .flexShrink(0)
                .alt($r('app.media.app_icon'));
            }
          }.width('100%').alignItems(VerticalAlign.Top);

          if (this.message.encrypted) {
            NotifyEncryptionBadge();
          }
        }.layoutWeight(1).alignItems(HorizontalAlign.Start);
      }
      .width('100%')
      .padding({
        left: 14,
        right: 14,
        top: 16,
        bottom: 16
      })
      .alignItems(VerticalAlign.Top);

      if (this.message.url.length > 0) {
        this.linkActions(this.message.url);
      }
    }
    .width('100%')
    .backgroundColor($r('app.color.color_bg_surface'))
    .borderRadius(12)
    .clip(true)
    .onClick(() => this.isEditing ? this.onSelect(this.message.id) : this.onOpen(this.message));
  }

  @Builder
  private spans(text: string) {
    ForEach(parseNotifyTextSegments(text), (segment: NotifyTextSegment, index: number) => {
      if (segment.type === NOTIFY_SEGMENT_URL) {
        Span(segment.text)
          .fontSize(14)
          .fontColor($r('app.color.color_link'))
          .onClick(() => this.onOpenUrl(segment.text));
      } else if (segment.type === NOTIFY_SEGMENT_CODE) {
        Span(segment.text)
          .fontSize(14)
          .fontColor($r('app.color.color_brand'))
          .onClick(() => this.onCopyCode(segment.text));
      } else {
        Span(segment.text).fontSize(14).fontColor($r('app.color.color_text_secondary'));
      }
    }, (segment: NotifyTextSegment, index: number) => `${index}_${segment.type}_${segment.text}`)
  }

  @Builder
  private linkActions(url: string) {
    if (url.length > 0) {
      // 系统通知风格的卡片底栏：顶部分界线和轻背景使操作归属卡片而非独立色带。
      Column() {
        Divider().width('100%').strokeWidth(0.5).color($r('app.color.color_border_subtle'));
        Row() {
          Row({ space: 4 }) {
            Image($r('app.media.copy'))
              .width(13)
              .height(13)
              .fillColor($r('app.color.color_text_secondary'))
              .draggable(false)
              .objectFit(ImageFit.Contain)
              .flexShrink(0);
            Text('复制链接').fontSize(13).fontColor($r('app.color.color_text_secondary'));
          }.layoutWeight(1).justifyContent(FlexAlign.Center)
          .onClick(() => this.onCopyUrl(url));

          Divider()
            .vertical(true)
            .strokeWidth(1)
            .color($r('app.color.color_text_hint'))
            .height(16)
            .opacity(0.35);
          Row({ space: 4 }) {
            Image($r('app.media.url'))
              .width(13)
              .height(13)
              .fillColor($r('app.color.color_brand'))
              .draggable(false)
              .objectFit(ImageFit.Contain)
              .flexShrink(0);
            Text('访问链接').fontSize(13).fontColor($r('app.color.color_brand'));
          }.layoutWeight(1).justifyContent(FlexAlign.Center)
          .onClick(() => this.onOpenUrl(url));
        }
        .width('100%').height(42).backgroundColor($r('app.color.color_bg_action_bar')).alignItems(VerticalAlign.Center);
      }.width('100%');
    }
  }

  @Builder
  private body() {
    if (this.message.inboxContent.length > 0) {
      Column() {
        ForEach(this.message.inboxContent, (line: string, index: number) => {
          if (index < 4) {
            Text() {
              this.spans(line)
            }.width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).lineHeight(21);
          }
        }, (line: string, index: number) => `${index}_${line}`)
      }.width('100%').alignItems(HorizontalAlign.Start).margin({ top: 4 });
    } else if (this.message.body.length > 0) {
      Text() {
        this.spans(this.message.body)
      }
      .width('100%')
      .maxLines(4)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .lineHeight(21)
      .margin({ top: 4 });
    }
  }
}
