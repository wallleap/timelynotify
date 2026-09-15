import { NotifyMessage } from '../../model/NotifyMessage';
import {
  formatNotifyTime,
  NOTIFY_SEGMENT_CODE,
  NOTIFY_SEGMENT_URL,
  NotifyTextSegment,
  parseNotifyTextSegments
} from './NotifyViewTypes';
import { resolveBlurStyle } from '../../utils/ImmersiveUtil';

/** 通知详情全屏内容；页面仅传入数据与交互回调，状态仍由 NotifyView 持有。 */
@Component
export struct NotifyMessageDetail {
  @Prop message: NotifyMessage | null = null;
  @Prop statusBarHeight: number = 0;
  @Prop navBarHeight: number = 0;
  onDismiss: () => void = () => {};
  onOpenUrl: (url: string) => void = (_url: string) => {};
  onCopyCode: (code: string) => void = (_code: string) => {};
  onCopyUrl: (url: string) => void = (_url: string) => {};

  @Builder
  private textSpans(text: string) {
    ForEach(parseNotifyTextSegments(text), (segment: NotifyTextSegment, index: number) => {
      if (segment.type === NOTIFY_SEGMENT_URL) {
        Span(segment.text).fontColor($r('app.color.text_accent_color')).fontSize(15)
          .onClick(() => this.onOpenUrl(segment.text));
      } else if (segment.type === NOTIFY_SEGMENT_CODE) {
        Span(segment.text).fontColor($r('app.color.text_accent_color')).fontSize(15)
          .onClick(() => this.onCopyCode(segment.text));
      } else {
        Span(segment.text).fontColor($r('app.color.text_secondary_color')).fontSize(15);
      }
    }, (segment: NotifyTextSegment, index: number) => `${index}_${segment.type}_${segment.text}`)
  }

  @Builder
  private body(text: string) {
    Text() { this.textSpans(text) }
      .width('100%').lineHeight(22.5);
  }

  @Builder
  private inbox(items: string[]) {
    Column({ space: 8 }) {
      ForEach(items, (line: string, index: number) => {
        Text() { this.textSpans(line) }.width('100%').lineHeight(22.5);
      }, (line: string, index: number) => `${index}_${line}`)
    }.width('100%').alignItems(HorizontalAlign.Start);
  }

  /** 提取链接主机名，用作链接卡片的易读主标题。 */
  private linkHost(url: string): string {
    const protocolIndex: number = url.indexOf('://');
    const hostStart: number = protocolIndex >= 0 ? protocolIndex + 3 : 0;
    const pathIndex: number = url.indexOf('/', hostStart);
    return pathIndex >= 0 ? url.substring(hostStart, pathIndex) : url.substring(hostStart);
  }

  /** extras.url 链接信息卡：点击卡片打开，右侧按钮复制完整 URL。 */
  @Builder
  private linkRow(url: string) {
    if (url.length > 0) {
      Row({ space: 10 }) {
        Image($r('app.media.url')).width(20).height(20).fillColor($r('app.color.text_accent_color')).draggable(false)
          .objectFit(ImageFit.Contain).flexShrink(0);
        Column({ space: 3 }) {
          Text(this.linkHost(url)).fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary_color'))
            .width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
          Text(url).fontSize(12).fontColor($r('app.color.text_tertiary_color')).width('100%').maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis });
        }.layoutWeight(1).alignItems(HorizontalAlign.Start);
        Row() {
          Image($r('app.media.copy')).width(17).height(17).fillColor($r('app.color.text_secondary_color')).draggable(false)
            .objectFit(ImageFit.Contain);
        }
        .width(36).height(36).borderRadius(18).justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center)
        .backgroundColor($r('app.color.index_page_body_background')).onClick(() => this.onCopyUrl(url));
      }
      .width('100%').padding(12).borderRadius(12).backgroundColor($r('app.color.card_background'))
      .border({ width: 1, color: $r('app.color.divider_color') }).alignItems(VerticalAlign.Center)
      .onClick(() => this.onOpenUrl(url));
    }
  }

  @Builder
  private titleBar() {
    Column() {
      Row() {
        Text('消息详情').fontSize(18).fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary_color')).layoutWeight(1);
        Image($r('app.media.close')).width(28).height(28).objectFit(ImageFit.Contain).draggable(false)
          .fillColor($r('app.color.text_tertiary_color')).padding(2).onClick(() => this.onDismiss());
      }.width('100%').padding(16).alignItems(VerticalAlign.Center);
    }
    .width('100%').padding({ top: this.statusBarHeight }).backgroundBlurStyle(resolveBlurStyle('bar')!)
    .backgroundColor($r('app.color.index_page_top_glass_background'));
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      Scroll() {
        Column({ space: 12 }) {
          Row().width('100%').height(this.statusBarHeight + 72);
          if (this.message) {
            Row({ space: 8 }) {
              if (this.message.title.length > 0) {
                Text(this.message.title).fontSize(18).fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.text_primary_color')).layoutWeight(1);
              }
              if (this.message.image.length > 0) {
                Image(this.message.image).width(38).height(38).borderRadius(12).objectFit(ImageFit.Cover)
                  .flexShrink(0).alt($r('app.media.app_icon'));
              }
            }.width('100%').alignItems(VerticalAlign.Top);
            if (this.message.subtitle.length > 0) {
              Text(this.message.subtitle).fontSize(14).fontColor($r('app.color.text_accent_color')).width('100%');
            }
            if (this.message.inboxContent.length > 0) {
              this.inbox(this.message.inboxContent);
            } else if (this.message.body.length > 0) {
              this.body(this.message.body);
            }
            this.linkRow(this.message.url);
            Text(formatNotifyTime(this.message.timestamp)).fontSize(12).fontColor($r('app.color.text_quinary_color'))
              .width('100%').textAlign(TextAlign.End);
          }
        }.width('100%').padding({ left: 16, right: 16, bottom: 24 + this.navBarHeight });
      }
      .align(Alignment.TopStart).width('100%').height('100%').edgeEffect(EdgeEffect.Spring).scrollBar(BarState.Off);
      this.titleBar();
    }
    .width('100%').height('100%').backgroundColor($r('app.color.index_page_body_background'));
  }
}
