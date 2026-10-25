import { resourceManager } from '@kit.LocalizationKit';
import { LongPressMenuInfo, Markdown, MarkdownController, TextSelectionActionItem } from '@luvi/lv-markdown-in';
import { AppContextStore } from '../../common/AppContextStore';
import { KEY_ANTI_PEEP_BLUR } from '../../services/AntiPeepService';
import { NotifyMessage } from '../../model/NotifyMessage';
import {
  buildNotifyCopyText,
  formatNotifyTime,
  formatExpiryDescription,
  NOTIFY_SEGMENT_CODE,
  NOTIFY_SEGMENT_URL,
  NotifyTextSegment,
  parseNotifyTextSegments
} from './NotifyViewTypes';
import { NotifyEncryptionBadge } from './NotifyGroupVisuals';

const DETAIL_EDGE_SPACING: number = 16;
const DETAIL_BOTTOM_SPACING: number = 32;
const DETAIL_DELETE_BUTTON_HEIGHT: number = 44;
const DETAIL_ACTION_MAX_WIDTH: number = 420;
const DETAIL_ACTION_SCROLL_THRESHOLD: number = 16;
// 原生返回会先发取消选择、再发 Sheet 关闭；保留一帧供同次返回确认已消费。
const DETAIL_SELECTION_CLEAR_DELAY: number = 16;

/** 将详情内部的文字选择清理交给外层 Sheet 返回回调，不暴露组件状态。 */
export class NotifyDetailSelectionController {
  private handler: (() => boolean) | null = null;

  /** 当前详情挂载时接管返回；旧实例卸载时不能解除新实例的处理函数。 */
  attach(handler: () => boolean): void {
    this.handler = handler;
  }

  detach(handler: () => boolean): void {
    if (this.handler === handler) {
      this.handler = null;
    }
  }

  /** 返回 true 表示已清理文字选择，本次返回不应继续关闭详情。 */
  clearSelection(): boolean {
    return this.handler ? this.handler() : false;
  }
}

/** 通知详情半模态内容；页面仅传入数据与交互回调，状态仍由 NotifyView 持有。 */
@Component
export struct NotifyMessageDetail {
  @StorageProp(KEY_ANTI_PEEP_BLUR) @Watch('onPrivacyChanged') antiPeepBlur: boolean = false;
  @State private actionsVisible: boolean = true;
  @State private markdownFailed: boolean = false;
  // 每个详情实例独立控制选区，避免库的跨段落选择泄露到下一条通知。
  private markdownController: MarkdownController = new MarkdownController();
  private markdownSelecting: boolean = false;
  private detailMounted: boolean = false;
  private actionScrollDistance: number = 0;
  // 与页面共用实测导航条高度，让滚动末尾的卡片避开底部手势区域。
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  @Prop @Watch('resetTextSelection') message: NotifyMessage | null = null;
  @Prop useImmersiveMaterial: boolean = false;
  // 滚动控制器由页面持有并传入，供 Sheet 内 HdsNavigation.bindToScrollable 绑定标题栏动态模糊。
  detailScroller: Scroller = new Scroller();
  // 标题、副标题、正文及每条收件箱文字各自绑定控制器，返回只清理当前有效选择。
  selectionController: NotifyDetailSelectionController = new NotifyDetailSelectionController();
  private titleTextController: TextController = new TextController();
  private subtitleTextController: TextController = new TextController();
  private bodyTextController: TextController = new TextController();
  private inboxTextControllers: Map<number, TextController> = new Map<number, TextController>();
  private selectedTextController: TextController | null = null;
  private selectionClearTimer: number = -1;
  private selectionBackHandler: () => boolean = (): boolean => this.clearTextSelection();
  onOpenUrl: (url: string) => void = (_url: string) => {};
  onCopyCode: (code: string) => void = (_code: string) => {};
  onCopyUrl: (url: string) => void = (_url: string) => {};
  // 非链接、非验证码文本点击时复制对应原文，便于直接复用通知内容。
  onCopyText: (text: string, label: string) => void = (_text: string, _label: string) => {};
  // 待复制文本（extras.copy）的专用复制回调；与验证码逻辑一致，文案由调用方决定。
  onCopyContent: (text: string) => void = (_text: string) => {};
  // 删除动作交给列表页复用现有确认弹窗和本地删除流程。
  onDelete: () => void = () => {};

  aboutToAppear(): void {
    this.detailMounted = true;
    this.configureMarkdown();
    this.selectionController.attach(this.selectionBackHandler);
  }

  aboutToDisappear(): void {
    this.detailMounted = false;
    this.clearMarkdownSelection();
    this.selectionController.detach(this.selectionBackHandler);
    this.cancelSelectionClearTimer();
    this.selectedTextController = null;
    this.inboxTextControllers.clear();
  }

  /** 收件箱行复用同一控制器，避免渲染更新时丢失当前选择的归属。 */
  private getInboxTextController(index: number): TextController {
    let controller: TextController | undefined = this.inboxTextControllers.get(index);
    if (!controller) {
      controller = new TextController();
      this.inboxTextControllers.set(index, controller);
    }
    return controller;
  }

  /** 旧文字的取消回调可能晚于新文字选中到达，只允许它清理自己的记录。 */
  private onTextSelectionChanged(controller: TextController, start: number, end: number): void {
    if (start >= 0 && end > start) {
      this.clearMarkdownSelection();
      this.cancelSelectionClearTimer();
      this.selectedTextController = controller;
    } else if (this.selectedTextController === controller) {
      this.cancelSelectionClearTimer();
      // 模拟器实测：系统返回的 -1/-1 回调早于 onWillDismiss，不能在此同步丢掉归属。
      this.selectionClearTimer = setTimeout(() => {
        this.selectionClearTimer = -1;
        if (this.selectedTextController === controller) {
          this.selectedTextController = null;
        }
      }, DETAIL_SELECTION_CLEAR_DELAY);
    }
  }

  /** 新选择、主动清理或卸载都会使上一帧的取消选择回调失效。 */
  private cancelSelectionClearTimer(): void {
    if (this.selectionClearTimer >= 0) {
      clearTimeout(this.selectionClearTimer);
      this.selectionClearTimer = -1;
    }
  }

  /** 关闭菜单本身可能保留高亮；同时清空选择范围以完整退出文字选择。 */
  private clearTextSelection(): boolean {
    const markdownSelected: boolean = this.clearMarkdownSelection();
    const controller: TextController | null = this.selectedTextController;
    this.cancelSelectionClearTimer();
    if (!controller) {
      return markdownSelected;
    }
    this.selectedTextController = null;
    controller.setTextSelection(0, 0, { menuPolicy: MenuPolicy.HIDE });
    controller.closeSelectionMenu();
    return true;
  }

  /** 同一详情承接另一条通知时不沿用前一条的高亮、手柄或控制器。 */
  private resetTextSelection(): void {
    this.clearTextSelection();
    this.markdownFailed = false;
    this.inboxTextControllers.clear();
  }

  /** 防窥时卸载富文本，只模糊普通 Text 回退，卡片、代码底色等表面不整体模糊。 */
  private onPrivacyChanged(): void {
    if (this.antiPeepBlur) this.clearTextSelection();
  }

  /** 主题变化时同步代码块，其余颜色使用应用资源自动切换。 */
  onWillApplyTheme(): void {
    const context = AppContextStore.getInstance().getContext();
    if (context) {
      const dark: boolean = context.resourceManager.getConfigurationSync().colorMode ===
        resourceManager.ColorMode.DARK;
      this.markdownController.setCodeBlockTheme(dark ? 'dark' : 'light');
    }
  }

  /** Markdown 的所有复制入口都经应用回调，迟到事件必须重新检查保护状态。 */
  private copyMarkdownText(text: string): void {
    if (this.detailMounted && !this.antiPeepBlur) this.onCopyText(text, '内容');
  }

  private clearMarkdownSelection(): boolean {
    const selected: boolean = this.markdownSelecting;
    this.markdownSelecting = false;
    this.markdownController.clearTextSelection();
    return selected;
  }

  /** 不启用网页或 Worker 分支；选择、复制与链接继续由通知详情管理。 */
  private configureMarkdown(): void {
    this.markdownController
      .setThreadRenderEnable(false)
      .setMermaidEnable(false)
      .setHtmlPreviewEnable(false)
      .setHtmlPreviewJavaScriptEnable(false)
      .setWebPreviewPoolEnable(false)
      .setTextSize(15).setTextLineHeight(24)
      .setTextColor($r('app.color.color_text_secondary'))
      .setTitleColor($r('app.color.color_text_primary'))
      .setHyperlinkTextColor($r('app.color.color_link'))
      .setInlineCodeColor($r('app.color.color_brand'))
      .setInlineCodeBackgroundColor($r('app.color.color_bg_action'))
      .setQuoteTextColor($r('app.color.color_text_secondary'))
      .setQuoteBackgroundColor($r('app.color.color_bg_action'))
      .setTableBackgroundColor($r('app.color.color_bg_surface'))
      .setTableTitleBackgroundColor($r('app.color.color_bg_action'))
      .setTableTitleTextColor($r('app.color.color_text_primary'))
      .setTextSelectionEnable(true)
      .setLongPressMenuEnable(true)
      .setLongPressMenuListener((info: LongPressMenuInfo) => {
        if (!this.detailMounted || this.antiPeepBlur) return;
        this.clearTextSelection();
        this.markdownSelecting = true;
        info.selectWholeBlock();
      })
      .setTextSelectionCopyListener((text: string) => this.copyMarkdownText(text))
      .setCodeCopyListener((text: string) => this.copyMarkdownText(text))
      .setHyperlinkClickListener((_title: string, url: string): boolean => {
        // 仅放行常用网络/邮件协议；锚点和其它 scheme 不交由库启动页面。
        if (this.detailMounted && !this.antiPeepBlur && /^(https?:\/\/|mailto:)/i.test(url)) {
          this.onOpenUrl(url.replace(/^mailto:/i, ''));
        }
        return true;
      })
      .setImageClickListener((): boolean => true)
      // 通知内图片只加载网络地址，不让外部正文访问应用或设备本地文件。
      .setImageLoadProxy((url: string): string => /^https?:\/\//i.test(url) ? url : '')
      .setTextSelectionActionItems([
        new TextSelectionActionItem('复制', (selection) => {
          this.copyMarkdownText(selection.selectedText);
          this.clearMarkdownSelection();
        }),
        new TextSelectionActionItem('全选', (selection) => {
          if (this.detailMounted && !this.antiPeepBlur) {
            this.markdownSelecting = true;
            selection.selectAll();
          }
        }),
        new TextSelectionActionItem('取消', () => { this.clearMarkdownSelection(); })
      ]);
    this.markdownController.setTableNormalTextColor($r('app.color.color_text_secondary'));
    this.markdownController.setTableInterleaveTextColor($r('app.color.color_text_secondary'));
    this.markdownController.setTableCopyClickListener((text: string) => this.copyMarkdownText(text));
    // 未提供回调时库会隐藏对应按钮；仅保留表格复制，不增加导出/全屏入口。
    this.markdownController.setTableDownloadClickListener();
    this.markdownController.setTableExpandClickListener();
    this.onWillApplyTheme();
  }

  /** 只在显式传入 Markdown 时渲染；失败和防窥回退都保留原文且不修改存储。 */
  @Builder
  private markdownBody(text: string) {
    if (this.antiPeepBlur || this.markdownFailed) {
      this.body(this.message && this.message.body.length > 0 ? this.message.body : text);
    } else {
      Markdown({
        text: text,
        controller: this.markdownController,
        callback: {
          fail: () => {
            if (this.detailMounted && this.message?.markdown === text) this.markdownFailed = true;
          }
        }
      }).width('100%');
    }
  }

  /** 只在用户明显改变滚动方向后切换按钮行，避免回弹和微小位移造成闪烁。 */
  private handleDetailScroll(scrollOffset: number, scrollState: ScrollState): void {
    if (scrollState === ScrollState.Idle) {
      return;
    }
    if (this.detailScroller.currentOffset().yOffset <= 0) {
      this.actionScrollDistance = 0;
      this.actionsVisible = true;
      return;
    }
    if (this.actionScrollDistance * scrollOffset < 0) {
      this.actionScrollDistance = 0;
    }
    this.actionScrollDistance += scrollOffset;
    if (this.actionScrollDistance >= DETAIL_ACTION_SCROLL_THRESHOLD && this.actionsVisible) {
      this.actionsVisible = false;
      this.actionScrollDistance = 0;
    } else if (this.actionScrollDistance <= -DETAIL_ACTION_SCROLL_THRESHOLD && !this.actionsVisible) {
      this.actionsVisible = true;
      this.actionScrollDistance = 0;
    }
  }

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
          .onClick(() => this.onCopyText(segment.text, '内容'));
      }
    }, (segment: NotifyTextSegment, index: number) => `${index}_${segment.type}_${segment.text}`)
  }

  @Builder
  private body(text: string) {
    Text(undefined, { controller: this.bodyTextController }) { this.textSpans(text) }
      .blur(this.antiPeepBlur ? 22 : 0)
      .width('100%').lineHeight(24).copyOption(CopyOptions.InApp)
      .onTextSelectionChange((start: number, end: number) => {
        this.onTextSelectionChanged(this.bodyTextController, start, end);
      })
      .onClick(() => this.onCopyText(text, '内容'));
  }

  @Builder
  private inbox(items: string[]) {
    Column({ space: 8 }) {
      ForEach(items, (line: string, index: number) => {
        // 点击每一条收件箱内容的非识别区域时，复制该条完整文本。
        Text(undefined, { controller: this.getInboxTextController(index) }) { this.textSpans(line) }
          .blur(this.antiPeepBlur ? 22 : 0).width('100%').lineHeight(24).copyOption(CopyOptions.InApp)
          .onTextSelectionChange((start: number, end: number) => {
            this.onTextSelectionChanged(this.getInboxTextController(index), start, end);
          })
          .onClick(() => this.onCopyText(line, '内容'));
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
              Text(this.displayRecognizedText(segment)).blur(this.antiPeepBlur ? 22 : 0).fontSize(14).fontWeight(FontWeight.Medium)
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
          // Copy 参数内容使用独立文案，copy 非空时显示在最左边。
          if (copy.length > 0) {
            Row({ space: 4 }) {
              Image($r('app.media.copy')).width(13).height(13).fillColor($r('app.color.color_text_secondary')).draggable(false)
                .objectFit(ImageFit.Contain).flexShrink(0);
              Text('复制 Copy 参数内容').fontSize(13).fontColor($r('app.color.color_text_secondary'));
            }
            .layoutWeight(1).height('100%').justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center)
            .onClick(() => this.onCopyContent(copy));
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
            .layoutWeight(1).height('100%').justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center)
            .onClick(() => this.onCopyUrl(url));
            Divider().vertical(true).strokeWidth(1).color($r('app.color.color_text_hint')).height(16).opacity(0.35);
            Row({ space: 4 }) {
              Image($r('app.media.url')).width(13).height(13).fillColor($r('app.color.color_brand')).draggable(false)
                .objectFit(ImageFit.Contain).flexShrink(0);
              Text('访问链接').fontSize(13).fontColor($r('app.color.color_brand'));
            }
            .layoutWeight(1).height('100%').justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center)
            .onClick(() => this.onOpenUrl(url));
          }
        }
        .width('100%').height(42).backgroundColor($r('app.color.color_bg_action_bar')).alignItems(VerticalAlign.Center);
      }.width('100%');
    }
  }

  /** Sheet 底部固定操作区：删除保持普通按钮外观，复制全文使用品牌色主按钮。 */
  @Builder
  private bottomActions() {
    Row({ space: 12 }) {
      Button('删除')
        .layoutWeight(1).height(DETAIL_DELETE_BUTTON_HEIGHT)
        .buttonStyle(ButtonStyleMode.NORMAL)
        .backgroundColor($r('app.color.color_bg_action'))
        .fontSize(16).fontColor($r('app.color.color_error'))
        .borderRadius(DETAIL_DELETE_BUTTON_HEIGHT / 2)
        .onClick(() => this.onDelete());
      Button('复制全文')
        .layoutWeight(1).height(DETAIL_DELETE_BUTTON_HEIGHT)
        .backgroundColor($r('app.color.color_brand'))
        .fontSize(16).fontColor(Color.White)
        .borderRadius(DETAIL_DELETE_BUTTON_HEIGHT / 2)
        .enabled(this.message ? buildNotifyCopyText(this.message).length > 0 : false)
        .onClick(() => {
          if (this.message) {
            this.onCopyText(buildNotifyCopyText(this.message), '全文');
          }
        });
    }
    .width('100%')
    .constraintSize({ maxWidth: DETAIL_ACTION_MAX_WIDTH })
    .padding({ left: DETAIL_EDGE_SPACING, right: DETAIL_EDGE_SPACING,
      bottom: this.navBarHeight + DETAIL_EDGE_SPACING })
    .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 24 }))
      .animation({ duration: 220, curve: Curve.EaseOut }));
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
                    Text(this.message.title, { controller: this.titleTextController })
                      .blur(this.antiPeepBlur ? 22 : 0).fontSize(18).fontWeight(FontWeight.Medium).lineHeight(25)
                      .fontColor($r('app.color.color_text_primary')).width('100%').copyOption(CopyOptions.InApp)
                      .onTextSelectionChange((start: number, end: number) => {
                        this.onTextSelectionChanged(this.titleTextController, start, end);
                      })
                      .onClick(() => this.onCopyText(this.message ? this.message.title : '', '标题'));
                  }
                  if (this.message.subtitle.length > 0) {
                    Text(this.message.subtitle, { controller: this.subtitleTextController })
                      .blur(this.antiPeepBlur ? 22 : 0).fontSize(13).fontColor($r('app.color.color_brand'))
                      .width('100%').maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
                      .margin({ top: this.message.title.length > 0 ? 6 : 0 }).copyOption(CopyOptions.InApp)
                      .onTextSelectionChange((start: number, end: number) => {
                        this.onTextSelectionChanged(this.subtitleTextController, start, end);
                      })
                      .onClick(() => this.onCopyText(this.message ? this.message.subtitle : '', '副标题'));
                  }
                }
                .layoutWeight(1).alignItems(HorizontalAlign.Start);
              }
              .width('100%').alignItems(VerticalAlign.Top).margin({ bottom: 14 });
              if (this.message.hasMarkdown()) {
                this.markdownBody(this.message.markdown);
              } else if (this.message.inboxContent.length > 0) {
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
                Text(formatNotifyTime(this.message.timestamp)).blur(this.antiPeepBlur ? 22 : 0)
                  .fontSize(12)
                  .fontColor($r('app.color.color_text_hint'))
                  .maxLines(1);
              }
              .width('100%').margin({ top: 14 }).alignItems(VerticalAlign.Center);
              if (formatExpiryDescription(this.message.expiresAt).length > 0) {
                Text(formatExpiryDescription(this.message.expiresAt)).blur(this.antiPeepBlur ? 22 : 0)
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
        // 提示与卡片相邻；固定删除按钮所需的底部留白放在下一项。
        .width('100%').padding({ left: DETAIL_EDGE_SPACING, right: DETAIL_EDGE_SPACING,
          top: DETAIL_EDGE_SPACING });
        ListItem() {
          if (this.message) {
            Text(this.message.hasMarkdown() ? '长按正文可选择复制' : '点按标题或内容，可分别复制')
              .width('100%').textAlign(TextAlign.Center)
              .fontSize(12).fontColor($r('app.color.color_text_hint'));
          }
        }
        // 长通知滚到末尾时，提示和卡片都能完整露出固定按钮上方。
        .width('100%').padding({ left: DETAIL_EDGE_SPACING, right: DETAIL_EDGE_SPACING, top: 10,
          bottom: DETAIL_BOTTOM_SPACING + this.navBarHeight + DETAIL_DELETE_BUTTON_HEIGHT + DETAIL_EDGE_SPACING });
      }
      // Sheet 的系统材质绘制在内容后方；仅材质模式让外层透出。
      .width('100%').height('100%')
      // 不裁剪超出 List 边界的内容，使卡片上滚时穿入 MODAL 标题栏下方，供其动态模糊取色。
      .clip(false)
      .edgeEffect(EdgeEffect.Spring).scrollBar(BarState.Off)
      .onDidScroll((scrollOffset: number, scrollState: ScrollState) => {
        this.handleDetailScroll(scrollOffset, scrollState);
      })
      .onReachStart(() => {
        this.actionScrollDistance = 0;
        this.actionsVisible = true;
      })
      // 内容区域只滚动自身；内容不足一屏时不将滑动手势交给 Sheet。
      .nestedScroll({ scrollForward: NestedScrollMode.SELF_ONLY, scrollBackward: NestedScrollMode.SELF_ONLY })
      .backgroundColor(this.useImmersiveMaterial ? Color.Transparent : $r('app.color.color_bg_page'));

      if (this.message && this.actionsVisible) {
        this.bottomActions();
      }
    }
    .width('100%').height('100%')
    // 各文本独立模糊，卡片和图片保持清晰；保护期间禁用操作及无障碍朗读。
    .enabled(!this.antiPeepBlur)
    .accessibilityLevel(this.antiPeepBlur ? 'no-hide-descendants' : 'auto');
  }
}
