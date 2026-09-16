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
  // 非链接、非验证码文本点击时复制对应原文，便于直接复用通知内容。
  onCopyText: (text: string) => void = (_text: string) => {};

  @Builder
  private textSpans(text: string) {
    ForEach(parseNotifyTextSegments(text), (segment: NotifyTextSegment, index: number) => {
      if (segment.type === NOTIFY_SEGMENT_URL) {
        Span(segment.text).fontColor($r('app.color.color_link')).fontSize(15)
          .onClick(() => this.onOpenUrl(segment.text));
      } else if (segment.type === NOTIFY_SEGMENT_CODE) {
        Span(segment.text).fontColor($r('app.color.color_brand')).fontSize(15)
          .onClick(() => this.onCopyCode(segment.text));
      } else {
        // 普通文本可直接复制该连续片段；空白区域由外层 Text 复制整段内容。
        Span(segment.text).fontColor($r('app.color.color_text_secondary')).fontSize(15)
          .onClick(() => this.onCopyText(segment.text));
      }
    }, (segment: NotifyTextSegment, index: number) => `${index}_${segment.type}_${segment.text}`)
  }

  @Builder
  private body(text: string) {
    Text() { this.textSpans(text) }
      .width('100%').lineHeight(24).copyOption(CopyOptions.InApp)
      .onClick(() => this.onCopyText(text));
  }

  @Builder
  private inbox(items: string[]) {
    Column({ space: 8 }) {
      ForEach(items, (line: string, index: number) => {
        // 点击每一条收件箱内容的非识别区域时，复制该条完整文本。
        Text() { this.textSpans(line) }.width('100%').lineHeight(24).copyOption(CopyOptions.InApp)
          .onClick(() => this.onCopyText(line));
      }, (line: string, index: number) => `${index}_${line}`)
    }.width('100%').alignItems(HorizontalAlign.Start);
  }

  /** 收集正文中所有可交互的链接和验证码，去重后在正文下方以图标化操作项展示。 */
  private recognizedSegments(): NotifyTextSegment[] {
    if (!this.message) {
      return [];
    }
    const sourceTexts: string[] = [];
    if (this.message.inboxContent.length > 0) {
      for (let i = 0; i < this.message.inboxContent.length; i++) {
        sourceTexts.push(this.message.inboxContent[i]);
      }
    } else if (this.message.body.length > 0) {
      sourceTexts.push(this.message.body);
    }
    const result: NotifyTextSegment[] = [];
    for (let i = 0; i < sourceTexts.length; i++) {
      const segments: NotifyTextSegment[] = parseNotifyTextSegments(sourceTexts[i]);
      for (let j = 0; j < segments.length; j++) {
        if (segments[j].type !== NOTIFY_SEGMENT_URL && segments[j].type !== NOTIFY_SEGMENT_CODE) {
          continue;
        }
        let duplicated: boolean = false;
        for (let k = 0; k < result.length; k++) {
          if (result[k].type === segments[j].type && result[k].text === segments[j].text) {
            duplicated = true;
            break;
          }
        }
        if (!duplicated) {
          result.push(segments[j]);
        }
      }
    }
    return result;
  }

  /** 识别结果类型判断，供 ArkUI 构建闭包复用，避免闭包内声明局部变量。 */
  private isUrlSegment(segment: NotifyTextSegment): boolean {
    return segment.type === NOTIFY_SEGMENT_URL;
  }

  /** 链接优先展示域名和路径，避免窄屏省略后只剩无辨识度的“https://…”。 */
  private displayRecognizedText(segment: NotifyTextSegment): string {
    if (!this.isUrlSegment(segment)) {
      return segment.text;
    }
    return segment.text.replace(/^https?:\/\//i, '');
  }

  /** 正文识别结果：信息在左、按钮在右；仅按钮可触发打开或复制，避免误触。 */
  @Builder
  private recognizedActions(segments: NotifyTextSegment[]) {
    if (segments.length > 0) {
      Column({ space: 8 }) {
        ForEach(segments, (segment: NotifyTextSegment, index: number) => {
          Row({ space: 12 }) {
            Column({ space: 2 }) {
              Text(this.isUrlSegment(segment) ? '识别到链接' : '识别到验证码').fontSize(12)
                .fontColor($r('app.color.color_text_tertiary')).width('100%');
              Text(this.displayRecognizedText(segment)).fontSize(14).fontWeight(FontWeight.Medium)
                .fontColor(this.isUrlSegment(segment) ? $r('app.color.color_link') : $r('app.color.color_text_primary'))
                .width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
            }
            .layoutWeight(1).alignItems(HorizontalAlign.Start);
            // 右侧图标和文案用于说明整张识别卡片的动作。
            Row({ space: 4 }) {
              Image(this.isUrlSegment(segment) ? $r('app.media.url') : $r('app.media.copy'))
                .width(14).height(14).objectFit(ImageFit.Contain).draggable(false)
                .fillColor(this.isUrlSegment(segment) ? $r('app.color.color_link') : $r('app.color.color_brand'));
              Text(this.isUrlSegment(segment) ? '访问' : '复制').fontSize(13).fontWeight(FontWeight.Medium)
                .fontColor(this.isUrlSegment(segment) ? $r('app.color.color_link') : $r('app.color.color_brand'));
            }
            .padding({ left: 10, right: 10, top: 8, bottom: 8 }).borderRadius(16)
            .alignItems(VerticalAlign.Center);
          }
          .width('100%').padding(10).borderRadius(12).backgroundColor($r('app.color.color_bg_action'))
          // 整条识别结果均可操作，降低窄屏下仅点小按钮的误触成本。
          .stateStyles({ pressed: {
            backgroundColor: this.isUrlSegment(segment) ? $r('app.color.color_state_link_pressed') :
              $r('app.color.color_state_selected')
          } })
          .alignItems(VerticalAlign.Center).onClick(() => {
            if (this.isUrlSegment(segment)) {
              this.onOpenUrl(segment.text);
            } else {
              this.onCopyCode(segment.text);
            }
          });
        }, (segment: NotifyTextSegment, index: number) => `${index}_${segment.type}_${segment.text}`)
      }
      .width('100%').margin({ top: 14 });
    }
  }

  /** 系统通知风格卡片底栏：复制/访问两项等宽排列，与正文共享同一张卡片。 */
  @Builder
  private linkActions(url: string) {
    if (url.length > 0) {
      Column() {
        Divider().width('100%').strokeWidth(0.5).color($r('app.color.color_border_subtle'));
        Row() {
          Row({ space: 4 }) {
            Image($r('app.media.copy')).width(13).height(13).fillColor($r('app.color.color_text_secondary')).draggable(false)
              .objectFit(ImageFit.Contain).flexShrink(0);
            Text('复制链接').fontSize(13).fontColor($r('app.color.color_text_secondary'));
          }
          .layoutWeight(1).justifyContent(FlexAlign.Center).onClick(() => this.onCopyUrl(url));
          Divider().vertical(true).strokeWidth(1).color($r('app.color.color_text_hint')).height(16).opacity(0.35);
          Row({ space: 4 }) {
            Image($r('app.media.url')).width(13).height(13).fillColor($r('app.color.color_brand')).draggable(false)
              .objectFit(ImageFit.Contain).flexShrink(0);
            Text('访问链接').fontSize(13).fontColor($r('app.color.color_brand'));
          }
          .layoutWeight(1).justifyContent(FlexAlign.Center).onClick(() => this.onOpenUrl(url));
        }
        .width('100%').height(42).backgroundColor($r('app.color.color_bg_action_bar')).alignItems(VerticalAlign.Center);
      }.width('100%');
    }
  }

  @Builder
  private titleBar() {
    Column() {
      Row() {
        Text('消息详情').fontSize(18).fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.color_text_primary')).layoutWeight(1);
        Row() {
          Image($r('app.media.close')).width(22).height(22).objectFit(ImageFit.Contain).draggable(false)
            .fillColor($r('app.color.color_text_tertiary'));
        }
        .width(40).height(40).borderRadius(20).justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center)
        .onClick(() => this.onDismiss());
      }.width('100%').height(64).padding({ left: 20, right: 12 }).alignItems(VerticalAlign.Center);
    }
    .width('100%').padding({ top: this.statusBarHeight }).backgroundBlurStyle(resolveBlurStyle('bar')!)
    .backgroundColor($r('app.color.color_bg_glass'));
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      Scroll() {
        Column() {
          // 为悬浮顶栏预留高度，使内容卡片从顶栏下自然开始。
          Row().width('100%').height(this.statusBarHeight + 76);
          if (this.message) {
            // 外层统一裁剪圆角，正文与贴底 action 形成同一张分区卡片。
            Column() {
              Column() {
                // 保留原详情布局：标题和头像同行，副标题位于标题下方。
              Row({ space: 10 }) {
                Column() {
                  if (this.message.title.length > 0) {
                    Text(this.message.title).fontSize(18).fontWeight(FontWeight.Medium).lineHeight(25)
                      .fontColor($r('app.color.color_text_primary')).width('100%').copyOption(CopyOptions.InApp)
                      .onClick(() => this.onCopyText(this.message ? this.message.title : ''));
                  }
                  if (this.message.subtitle.length > 0) {
                    Text(this.message.subtitle).fontSize(13).fontColor($r('app.color.color_brand'))
                      .width('100%').maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
                      .margin({ top: this.message.title.length > 0 ? 6 : 0 }).copyOption(CopyOptions.InApp)
                      .onClick(() => this.onCopyText(this.message ? this.message.subtitle : ''));
                  }
                }
                .layoutWeight(1).alignItems(HorizontalAlign.Start);
                if (this.message.image.length > 0) {
                  Image(this.message.image).width(38).height(38).borderRadius(12).objectFit(ImageFit.Cover)
                    .draggable(false).flexShrink(0).alt($r('app.media.app_icon'));
                }
              }
              .width('100%').alignItems(VerticalAlign.Top).margin({ bottom: 14 });
              if (this.message.inboxContent.length > 0) {
                this.inbox(this.message.inboxContent);
              } else if (this.message.body.length > 0) {
                this.body(this.message.body);
              }
              // 时间作为正文元信息的收尾；识别结果紧随其后，避免打断内容阅读。
              Text(formatNotifyTime(this.message.timestamp)).fontSize(12).fontColor($r('app.color.color_text_hint'))
                .width('100%').maxLines(1).textAlign(TextAlign.End).margin({ top: 14 });
              this.recognizedActions(this.recognizedSegments());
              }
              .width('100%').padding(20);
              if (this.message.url.length > 0) {
                this.linkActions(this.message.url);
              }
            }
            .width('100%').borderRadius(20).clip(true).backgroundColor($r('app.color.color_bg_surface'))
            .border({ width: 1, color: $r('app.color.color_border_subtle') });
          }
        }.width('100%').padding({ left: 16, right: 16, bottom: 24 + this.navBarHeight });
      }
      .align(Alignment.TopStart).width('100%').height('100%').edgeEffect(EdgeEffect.Spring).scrollBar(BarState.Off);
      this.titleBar();
    }
    .width('100%').height('100%').backgroundColor($r('app.color.color_bg_page'));
  }
}
