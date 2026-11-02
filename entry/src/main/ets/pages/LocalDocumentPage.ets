import { resourceManager } from '@kit.LocalizationKit';
import { Markdown, MarkdownController } from '@luvi/lv-markdown-in';
import { hdsMaterial, HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit';
import { AppContextStore } from '../common/AppContextStore';
import showToast from '../components/showToast';
import { ClipboardService } from '../services/ClipboardService';
import { ExternalLinkService, USE_DOCS_URL } from '../services/ExternalLinkService';
import {
  LocalDocumentInfo,
  LocalDocumentSection,
  LocalDocumentService,
  LocalDocumentTarget
} from '../services/LocalDocumentService';
import { KEY_IMMERSIVE_LIGHT_ENABLED, resolveBlurStyle, shouldUseSystemMaterialPath } from '../utils/ImmersiveUtil';

/** 文档内历史不占路由栈；返回同时恢复原文档及阅读位置。 */
interface DocumentHistory {
  target: LocalDocumentTarget;
  offset: number;
}

/** 随包文档的原生阅读页，不使用 WebView 或在线文档回退。 */
@Entry
@Component
struct LocalDocumentPage {
  @StorageProp('statusBarHeight') statusBarHeight: number = 36;
  @StorageProp('navBarHeight') navBarHeight: number = 24;
  @StorageProp(KEY_IMMERSIVE_LIGHT_ENABLED) immersiveLightEnabled: boolean = true;
  @State pageTitle: string = '文档';
  @State loading: boolean = true;
  @State loadFailed: boolean = false;
  @State renderFailed: boolean = false;
  @State sections: LocalDocumentSection[] = [];
  // 文档切换使用稳定代次重建 Markdown 节点，旧读取和渲染回调不得覆盖新文档。
  @State renderVersion: number = 0;
  // 和 SharePage 一样让正文铺到悬浮标题栏背后，首屏按实测重叠高度避让。
  @State titleBarBottom: number = -1;
  @State scrollTop: number = -1;
  @State titleVisible: boolean = true;
  private loadSequence: number = 0;
  private documents: LocalDocumentInfo[] = [];
  private currentTarget: LocalDocumentTarget | null = null;
  private history: DocumentHistory[] = [];
  private initialUrl: string = USE_DOCS_URL;
  private scroller: Scroller = new Scroller();
  private controller: MarkdownController = new MarkdownController();
  // 章节布局会随本地图片解码更新；用户开始拖动后不再自动调整定位。
  private offsets: Map<string, number> = new Map();
  private pendingAnchor: string = '';
  private pendingOffset: number = 0;

  aboutToAppear(): void {
    this.configureMarkdown();
    const params = this.getUIContext().getRouter().getParams() as Record<string, string> | undefined;
    if (params && params['url']) {
      this.initialUrl = params['url'];
    }
    this.initialize();
  }

  aboutToDisappear(): void {
    this.loadSequence++;
    this.controller.clearTextSelection();
  }

  onWillApplyTheme(_theme: CustomTheme): void {
    this.configureMarkdown();
  }

  /** 所有内容从资源包读取；失败保留明确的重试入口，不跳在线网页。 */
  private async initialize(): Promise<void> {
    const sequence: number = ++this.loadSequence;
    this.loading = true;
    this.loadFailed = false;
    try {
      const documents: LocalDocumentInfo[] = await LocalDocumentService.getDocuments();
      if (sequence !== this.loadSequence) {
        return;
      }
      this.documents = documents;
      const target = this.currentTarget ?? LocalDocumentService.resolveLink(documents, 'index.md', this.initialUrl);
      if (!target) {
        throw new Error('文档未内置');
      }
      await this.loadDocument(target, 0);
    } catch (_err) {
      if (sequence === this.loadSequence) {
        this.loading = false;
        this.loadFailed = true;
      }
    }
  }

  /** 完整读取后再交接内容；读取失败不丢失原文档和历史。 */
  private async loadDocument(target: LocalDocumentTarget, offset: number, remember: boolean = false): Promise<void> {
    const previous: DocumentHistory | null = remember && this.currentTarget
      ? { target: this.currentTarget, offset: this.scroller.currentOffset().yOffset } : null;
    const sequence: number = ++this.loadSequence;
    this.loading = true;
    this.loadFailed = false;
    try {
      const sections: LocalDocumentSection[] = await LocalDocumentService.getSections(target.document);
      if (sequence !== this.loadSequence) {
        return;
      }
      if (previous) {
        this.history.push(previous);
      }
      this.controller.clearTextSelection();
      this.currentTarget = target;
      this.pageTitle = target.document.title;
      this.titleVisible = true;
      this.offsets.clear();
      this.pendingAnchor = target.anchor;
      this.pendingOffset = offset;
      if (target.anchor && !sections.some(section => section.anchor === target.anchor)) {
        this.pendingAnchor = '';
        showToast(this.getUIContext(), '未找到对应章节，已打开文档');
      }
      this.renderFailed = false;
      this.renderVersion++;
      this.sections = sections;
      this.loading = false;
    } catch (_err) {
      if (sequence === this.loadSequence) {
        this.loading = false;
        if (this.sections.length > 0) {
          showToast(this.getUIContext(), '无法读取文档，请重试');
        } else {
          this.loadFailed = true;
        }
      }
    }
  }

  /** 原生 Markdown 共用通知详情的安全设置；本地图片由构建脚本生成 rawfile 引用。 */
  private configureMarkdown(): void {
    this.controller.setThreadRenderEnable(false)
      .setMermaidEnable(false)
      .setHtmlPreviewEnable(false)
      .setHtmlPreviewJavaScriptEnable(false)
      .setWebPreviewPoolEnable(false)
      .setTextSize(16)
      .setTextLineHeight(27)
      .setTextColor($r('app.color.color_text_secondary'))
      .setTitleColor($r('app.color.color_text_primary'))
      .setHyperlinkTextColor($r('app.color.color_link'))
      // 文档链接同时用下划线区分，亮暗主题沿用现有链接颜色。
      .setHyperlinkUnderlineState(true)
      // 行内代码沿用主题色和淡橙底，无描边；由原生文本继续处理自然换行。
      .setInlineCodeColor($r('app.color.color_brand'))
      .setInlineCodeBackgroundColor($r('app.color.color_doc_code_background'))
      .setInlineCodeBackgroundRadius(6)
      .setQuoteTextColor($r('app.color.color_text_secondary'))
      .setQuoteBackgroundColor($r('app.color.color_bg_action'))
      .setTableBackgroundColor($r('app.color.color_bg_surface'))
      .setTableTitleBackgroundColor($r('app.color.color_bg_action'))
      .setTableInterleaveBackgroundColor($r('app.color.color_bg_action'))
      .setTableTitleTextColor($r('app.color.color_text_primary'))
      .setImageMaxWidth('100%')
      .setImageBorderRadius(12)
      .setTextSelectionEnable(true)
      .setTextSelectionCopyListener((text: string): void => { this.copyText(text); })
      .setCodeCopyListener((text: string): void => { this.copyText(text); })
      .setHyperlinkClickListener((_title: string, url: string): boolean => {
        this.openLink(url);
        return true;
      })
      // 网络图片仍被阻断；本地图片点击交给组件内置预览，便于放大查看。
      .setImageLoadProxy((_url: string): string => '')
      .setImageClickListener((): boolean => false);
    // 表格正文和交替行独立于 textColor，需单独覆盖库的浅色默认值。
    this.controller.setTableNormalTextColor($r('app.color.color_text_secondary'));
    this.controller.setTableInterleaveTextColor($r('app.color.color_text_secondary'));
    const context = AppContextStore.getInstance().getContext();
    if (context) {
      const dark: boolean = context.resourceManager.getConfigurationSync().colorMode === resourceManager.ColorMode.DARK;
      this.controller.setCodeBlockTheme(dark ? 'dark' : 'light');
    }
  }

  private async copyText(text: string): Promise<void> {
    const copied: boolean = await ClipboardService.copyText(text);
    showToast(this.getUIContext(), copied ? '已复制' : '复制失败');
  }

  /** 文档链接本地消化；只有用户主动点击的外部 HTTP(S) 链接才进入网页。 */
  private openLink(url: string): void {
    if (!this.currentTarget || this.loading) {
      return;
    }
    const target = LocalDocumentService.resolveLink(this.documents, this.currentTarget.document.path, url);
    if (target) {
      if (target.document.path === this.currentTarget.document.path) {
        if (target.anchor && !this.sections.some(section => section.anchor === target.anchor)) {
          showToast(this.getUIContext(), '未找到对应章节');
          return;
        }
        this.history.push({ target: this.currentTarget, offset: this.scroller.currentOffset().yOffset });
        this.currentTarget = target;
        this.pendingAnchor = target.anchor;
        this.pendingOffset = 0;
        this.applyPosition();
      } else {
        this.loadDocument(target, 0, true);
      }
    } else if (/^https?:\/\//i.test(url) && !LocalDocumentService.isDocumentUrl(url)) {
      ExternalLinkService.openSharePage(this.getUIContext(), url, '网页');
    } else {
      showToast(this.getUIContext(), '此链接未内置或暂不支持');
    }
  }

  /** 章节坐标来自同一内容 Column；不用网页注入或延时猜测图片高度。 */
  private applyPosition(): void {
    const offset: number | undefined = this.pendingAnchor ? this.offsets.get(this.pendingAnchor) : this.pendingOffset;
    if (offset !== undefined && offset >= 0 && !this.loading) {
      // 章节应停在标题栏下沿；历史保存的是实际滚动偏移，不重复扣除安全区。
      const target: number = this.pendingAnchor ? Math.max(0, offset - this.contentTopInset()) : offset;
      this.scroller.scrollTo({ xOffset: 0, yOffset: target, animation: false });
    }
  }

  /** 两个标题栏分支共用真实遮挡高度，避免硬编码状态栏及系统标题栏尺寸。 */
  private contentTopInset(): number {
    return this.titleBarBottom >= 0 && this.scrollTop >= 0
      ? Math.max(0, this.titleBarBottom - this.scrollTop) : 0;
  }

  private updateTitleBarBottom(bottom: number): void {
    if (bottom >= 0 && bottom !== this.titleBarBottom) {
      this.titleBarBottom = bottom;
    }
  }

  /** Hds 原生标题栏保持系统布局，只用不可点击的透明节点测量边界。 */
  @Builder
  hdsTitleBarProbe() {
    Row().width('100%').height('100%').hitTestBehavior(HitTestMode.None)
      .onAreaChange((_old: Area, area: Area) => {
        this.updateTitleBarBottom((area.globalPosition.y as number) + (area.height as number));
      });
  }

  /** 降级分支沿用 SharePage 的悬浮玻璃顶栏；右侧留白让标题居中。 */
  @Builder
  fallbackTitleBar() {
    Row() {
      Image($r('app.media.arrow_left')).width(32).height(32).padding(4)
        .fillColor($r('app.color.color_text_primary')).draggable(false)
        .onClick(() => { this.goBack(); });
      Text(this.pageTitle).fontSize(18).fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.color_text_primary')).layoutWeight(1)
        .textAlign(TextAlign.Center).opacity(this.titleVisible ? 1 : 0);
      Row().width(32).height(32).hitTestBehavior(HitTestMode.None);
    }
    .width('100%').padding({ left: 8, right: 8, top: 12 + this.statusBarHeight, bottom: 12 })
    .backgroundBlurStyle(resolveBlurStyle('bar')!).backgroundColor($r('app.color.color_bg_glass'))
    .onAreaChange((_old: Area, area: Area) => {
      this.updateTitleBarBottom((area.globalPosition.y as number) + (area.height as number));
    });
  }

  private goBack(): void {
    if (this.loading) {
      this.loadSequence++;
      this.loading = false;
      if (this.sections.length > 0) {
        return;
      }
    }
    const previous: DocumentHistory | undefined = this.history.pop();
    if (previous) {
      // 精确恢复偏移优先于该历史目标之前的锚点。
      const target: LocalDocumentTarget = { document: previous.target.document, anchor: '' };
      if (this.currentTarget?.document.path === target.document.path) {
        // 同篇章节回退复用已渲染节点，避免整篇 Markdown 闪回加载态。
        this.currentTarget = target;
        this.pendingAnchor = '';
        this.pendingOffset = previous.offset;
        this.applyPosition();
      } else {
        this.loadDocument(target, previous.offset);
      }
    } else {
      this.getUIContext().getRouter().back();
    }
  }

  onBackPress(): boolean {
    this.goBack();
    return true;
  }

  @Builder
  documentBody() {
    if (this.loading) {
      Column({ space: 12 }) {
        LoadingProgress().width(28).height(28).color($r('app.color.color_brand'));
        Text('正在打开文档').fontColor($r('app.color.color_text_tertiary')).fontSize(14);
      }.width('100%').height('100%').justifyContent(FlexAlign.Center);
    } else if (this.loadFailed) {
      Column({ space: 16 }) {
        Text('无法读取内置文档').fontColor($r('app.color.color_text_secondary')).fontSize(16);
        Button('重试').fontColor($r('app.color.color_brand')).backgroundColor(Color.Transparent)
          .onClick(() => { this.initialize(); });
      }.width('100%').height('100%').justifyContent(FlexAlign.Center);
    } else {
      Scroll(this.scroller) {
        Column({ space: 12 }) {
          ForEach(this.sections, (section: LocalDocumentSection) => {
            Column() {
              if (this.renderFailed) {
                Text(section.text).fontSize(16).lineHeight(27)
                  .fontColor($r('app.color.color_text_secondary')).copyOption(CopyOptions.LocalDevice);
              } else {
                Markdown({
                  text: section.text,
                  controller: this.controller,
                  context: AppContextStore.getInstance().getContext() ?? undefined,
                  callback: { fail: (): void => { this.renderFailed = true; } }
                }).width('100%');
              }
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .onAreaChange((_old: Area, area: Area) => {
              this.offsets.set(section.anchor, area.position.y as number);
              this.applyPosition();
            });
          }, (section: LocalDocumentSection): string => this.renderVersion + ':' + section.anchor);
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 16 + this.contentTopInset(), bottom: 24 + this.navBarHeight })
        .clip(false)
        .onAreaChange(() => { this.applyPosition(); });
      }
      .width('100%')
      .height('100%')
      .align(Alignment.TopStart)
      .scrollBar(BarState.Auto)
      .edgeEffect(EdgeEffect.Spring)
      // 与 SharePage 的 Web/Refresh 一样不裁剪，使滚入顶栏背后的正文参与材质采样。
      .clip(false)
      .onAreaChange((_old: Area, area: Area) => {
        const top: number = area.globalPosition.y as number;
        if (top !== this.scrollTop) {
          this.scrollTop = top;
        }
      })
      .onDidScroll(() => {
        // 使用原生滚动绝对位置复现 SharePage 的下滑隐藏、回顶恢复标题。
        this.titleVisible = this.scroller.currentOffset().yOffset < 64;
      })
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Down) {
          this.pendingAnchor = '';
          this.pendingOffset = -1;
        }
      });
    }
  }

  build() {
    if (shouldUseSystemMaterialPath(this.immersiveLightEnabled)) {
      HdsNavigation() {
        this.documentBody();
      }
      .titleBar({
        // 与 SharePage 一致：正文不避让标题栏，标题槽位自身仍避让系统安全区。
        enableComponentSafeArea: false,
        avoidLayoutSafeArea: true,
        content: {
          stackBuilder: (): void => { this.hdsTitleBarProbe(); },
          title: { mainTitle: this.titleVisible ? this.pageTitle : '' },
          backIcon: { icon: $r('app.media.arrow_left'), action: (): void => { this.goBack(); } }
        },
        style: {
          // Scroll 绑定默认启用 COMMON_BLUR，会形成整块色带；显式关闭以匹配 SharePage 的透明悬浮外观。
          scrollEffectOpts: { enableScrollEffect: false },
          systemMaterialEffect: {
            materialType: hdsMaterial.MaterialType.ADAPTIVE,
            materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
          }
        }
      })
      .hideBackButton(false)
      .titleMode(HdsNavigationTitleMode.MINI)
      // 原生 Scroll 保留导航绑定，但不启用默认滚动背景；标题显隐由 onDidScroll 单独控制。
      .bindToScrollable([this.scroller])
      .width('100%').height('100%').backgroundColor($r('app.color.color_bg_page'));
    } else {
      Stack({ alignContent: Alignment.Top }) {
        this.documentBody();
        this.fallbackTitleBar();
      }.width('100%').height('100%').backgroundColor($r('app.color.color_bg_page'));
    }
  }
}
