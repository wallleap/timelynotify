import { NotifyMessage } from '../../model/NotifyMessage';
import {
  formatNotifyTime,
  formatExpiryDescription,
  NOTIFY_SEGMENT_CODE,
  NOTIFY_SEGMENT_URL,
  NotifyTextSegment,
  parseNotifyTextSegments
} from './NotifyViewTypes';
import { NotifyEncryptionBadge } from './NotifyGroupVisuals';
import { getSystemMaterial, resolveBlurStyle } from '../../utils/ImmersiveUtil';

const DETAIL_EDGE_SPACING: number = 16;
const DETAIL_BOTTOM_SPACING: number = 32;
const DETAIL_DELETE_BUTTON_HEIGHT: number = 44;

/** 通知详情半模态内容；页面仅传入数据与交互回调，状态仍由 NotifyView 持有。 */
@Component
export struct NotifyMessageDetail {
  // 与页面共用实测导航条高度，让滚动末尾的卡片避开底部手势区域。
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  @Prop message: NotifyMessage | null = null;
  @Prop useImmersiveMaterial: boolean = false;
  // 滚动控制器由页面持有并传入，供 Sheet 内 HdsNavigation.bindToScrollable 绑定标题栏动态模糊。
  detailScroller: Scroller = new Scroller();
  onOpenUrl: (url: string) => void = (_url: string) => {};
  onCopyCode: (code: string) => void = (_code: string) => {};
  onCopyUrl: (url: string) => void = (_url: string) => {};
  // 非链接、非验证码文本点击时复制对应原文，便于直接复用通知内容。
  onCopyText: (text: string) => void = (_text: string) => {};
  // 待复制文本（extras.copy）的专用复制回调；与验证码逻辑一致，文案由调用方决定。
  onCopyContent: (text: string) => void = (_text: string) => {};
  // 删除动作交给列表页复用现有确认弹窗和本地删除流程。
  onDelete: () => void = () => {};

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

  /**
   * 系统通知风格卡片底栏：copy 与 url 的复制/访问项等宽排列，与正文共享同一张卡片。
   * copy 在最左边；只有 copy 没有 url 时独占整行；同时存在时三项等宽。
   */
  @Builder
  private linkActions(url: string, copy: string) {
    if (url.length > 0 || copy.length > 0) {
      Column() {
        Divider().width('100%').strokeWidth(0.5).color($r('app.color.color_border_subtle'));
        Row() {
          // 待复制文本：copy 非空时显示在最左边
          if (copy.length > 0) {
            Row({ space: 4 }) {
              Image($r('app.media.copy')).width(13).height(13).fillColor($r('app.color.color_text_secondary')).draggable(false)
                .objectFit(ImageFit.Contain).flexShrink(0);
              Text('复制').fontSize(13).fontColor($r('app.color.color_text_secondary'));
            }
            .layoutWeight(1).justifyContent(FlexAlign.Center).onClick(() => this.onCopyContent(copy));
            // copy 与 url 同时存在时中间画分隔线；只有 copy 时不画，让其独占整行
            if (url.length > 0) {
              Divider().vertical(true).strokeWidth(1).color($r('app.color.color_text_hint')).height(16).opacity(0.35);
            }
          }
          if (url.length > 0) {
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
        }
        .width('100%').height(42).backgroundColor($r('app.color.color_bg_action_bar')).alignItems(VerticalAlign.Center);
      }.width('100%');
    }
  }

  /** 固定在 Sheet 底部的纯文字删除按钮；非材质模式沿用现有毛玻璃样式。 */
  @Builder
  private floatingDeleteButton() {
    if (this.useImmersiveMaterial) {
      Button('删除')
        .width(120).height(DETAIL_DELETE_BUTTON_HEIGHT)
        // 本分支仅在 API 26+ 材质就绪时渲染，可直接链式调用 API 26 的 systemMaterial。
        // 必须显式 NORMAL：Button 默认 EMPHASIZED 会渲染蓝色强调样式。
        // 官方「纯色 + 质感」：materialColor 给高端材质档赋纯色；
        // 同时必须保留同名 backgroundColor——中/低算力设备无材质滤镜，
        // 材质由 backgroundColor/border/shadow 模拟，缺了它按钮完全没有背板。
        // 高端档下该 backgroundColor 会被系统自动还原为透明，不会覆盖材质。
        .buttonStyle(ButtonStyleMode.NORMAL)
        .systemMaterial(getSystemMaterial('action'))
        .backgroundColor($r('app.color.color_bg_action'))
        .fontSize(16).fontColor($r('app.color.color_error'))
        .margin({ bottom: this.navBarHeight + DETAIL_EDGE_SPACING })
        .onClick(() => this.onDelete());
    } else {
      Row() {
        Text('删除').fontSize(16).fontColor($r('app.color.color_error'));
      }
        .width(120).height(DETAIL_DELETE_BUTTON_HEIGHT).borderRadius(22)
        .justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center)
        // 降级路径不区分深浅色：固定纯白半透 + Thin 模糊 + 玻璃描边。
        .backgroundColor('#8CFFFFFF')
        .backgroundBlurStyle(resolveBlurStyle('card')!)
        .border({ width: 1, color: $r('app.color.color_border_glass') })
        .margin({ bottom: this.navBarHeight + DETAIL_EDGE_SPACING })
        .onClick(() => this.onDelete());
    }
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      List({ scroller: this.detailScroller }) {
        ListItem() {
          if (this.message) {
            // 外层统一裁剪圆角，正文与贴底 action 形成同一张分区卡片。
            Column() {
              Column() {
                // icon 位于标题区左侧，副标题位于标题下方。
              Row({ space: 10 }) {
                if (this.message.icon.length > 0) {
                  Image(this.message.icon)
                    .width(40)
                    .height(40)
                    .borderRadius(40)
                    .objectFit(ImageFit.Cover)
                    .flexShrink(0)
                    .alt($r('app.media.app_icon'));
                }
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
              }
              .width('100%').alignItems(VerticalAlign.Top).margin({ bottom: 14 });
              if (this.message.inboxContent.length > 0) {
                this.inbox(this.message.inboxContent);
              } else if (this.message.body.length > 0) {
                this.body(this.message.body);
              }
              if (this.message.image.length > 0) {
                Image(this.message.image).width('100%').height(240).borderRadius(14).objectFit(ImageFit.Contain)
                  .backgroundColor($r('app.color.color_bg_page')).draggable(false)
                  .alt($r('app.media.app_icon')).margin({ top: 14 });
              }
              // 加密状态与时间共用正文元信息行；识别结果紧随其后，避免打断内容阅读。
              Row() {
                if (this.message.encrypted) {
                  NotifyEncryptionBadge();
                }
                Blank();
                Text(formatNotifyTime(this.message.timestamp))
                  .fontSize(12)
                  .fontColor($r('app.color.color_text_hint'))
                  .maxLines(1);
              }
              .width('100%').margin({ top: 14 }).alignItems(VerticalAlign.Center);
              if (formatExpiryDescription(this.message.expiresAt).length > 0) {
                Text(formatExpiryDescription(this.message.expiresAt))
                  .fontSize(12)
                  .fontColor($r('app.color.color_warning'))
                  .width('100%')
                  .textAlign(TextAlign.End)
                  .margin({ top: 6 });
              }
              this.recognizedActions(this.recognizedSegments());
              }
              .width('100%').padding({ left: 14, right: 14, top: 16, bottom: 16 });
              if (this.message.url.length > 0 || this.message.copy.length > 0) {
                this.linkActions(this.message.url, this.message.copy);
              }
            }
            // 仅详情 Sheet 的材质模式透出底层光感；普通模式维持实色卡片。
            .width('100%').borderRadius(20).clip(true)
            .backgroundColor(this.useImmersiveMaterial ? $r('app.color.color_bg_surface_glass') :
              $r('app.color.color_bg_surface'))
            .border({ width: 1, color: $r('app.color.color_border_subtle') });
          }
        }
        // 底部额外留白随内容滚动，长通知滚到末尾时也能完整露出卡片边缘。
        .width('100%').padding({ left: DETAIL_EDGE_SPACING, right: DETAIL_EDGE_SPACING,
          top: DETAIL_EDGE_SPACING,
          bottom: DETAIL_BOTTOM_SPACING + this.navBarHeight + DETAIL_DELETE_BUTTON_HEIGHT + DETAIL_EDGE_SPACING });
      }
      // Sheet 的系统材质绘制在内容后方；仅材质模式让外层透出。
      .width('100%').height('100%')
      // 不裁剪超出 List 边界的内容，使卡片上滚时穿入 MODAL 标题栏下方，供其动态模糊取色。
      .clip(false)
      .edgeEffect(EdgeEffect.Spring).scrollBar(BarState.Off)
      // 内容区域只滚动自身；内容不足一屏时不将滑动手势交给 Sheet。
      .nestedScroll({ scrollForward: NestedScrollMode.SELF_ONLY, scrollBackward: NestedScrollMode.SELF_ONLY })
      .backgroundColor(this.useImmersiveMaterial ? Color.Transparent : $r('app.color.color_bg_page'));

      if (this.message) {
        this.floatingDeleteButton();
      }
    }
    .width('100%').height('100%');
  }
}
