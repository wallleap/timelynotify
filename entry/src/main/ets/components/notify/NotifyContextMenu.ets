import { KEY_HOME_TAB_INDEX, KEY_INDEX_PAGE_VISIBLE } from '../../common/Constant';
import { NotifyMessage } from '../../model/NotifyMessage';
import { KEY_ANTI_PEEP_BLUR } from '../../services/AntiPeepService';
import { notifyIdentity } from '../../utils/NotifyIdentity';
import { resolveBlurStyle } from '../../utils/ImmersiveUtil';
import { formatNotifyTime } from './NotifyViewTypes';

/** 长按操作只描述意图，实际复制、选择和删除仍由通知页处理。 */
export enum NotifyContextAction {
  Select,
  CopyAll,
  CopyContent,
  CopyUrl,
  OpenUrl,
  Delete,
  ExpandGroup,
  SelectGroup,
  DeleteGroup,
  // 单条通知的详情入口，与访问消息中的链接区分。
  ViewDetail
}

/** 固定本次长按的消息身份和分组范围，避免列表刷新后操作到其它行。 */
export interface NotifyContextTarget {
  message: NotifyMessage;
  grouped: boolean;
  groupKey: string;
  groupTotal: number;
}

/** 卡片长按入口：同层浮层固定预览位置，保留原列表节点和既有操作意图。 */
@Component
export struct NotifyContextMenu {
  @StorageProp(KEY_ANTI_PEEP_BLUR) @Watch('onAvailabilityChanged') antiPeepBlur: boolean = false;
  @StorageProp(KEY_HOME_TAB_INDEX) @Watch('onAvailabilityChanged') homeTabIndex: number = 0;
  @StorageProp(KEY_INDEX_PAGE_VISIBLE) @Watch('onAvailabilityChanged') pageVisible: boolean = true;
  @StorageProp('statusBarHeight') statusBarHeight: number = 36;
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  @Prop @Watch('onTargetChanged') message: NotifyMessage = new NotifyMessage();
  // 切换服务器范围即取消当前预览，不向新范围交付旧操作。
  @Prop @Watch('cancelMenu') scope: string = '';
  @Prop grouped: boolean = false;
  @Prop groupKey: string = '';
  @Prop groupTotal: number = 0;
  @Prop @Watch('onAvailabilityChanged') disabled: boolean = false;
  @State overlayWidth: number = 400;
  @State overlayHeight: number = 800;
  @State previewHeight: number = 0;
  @State motionProgress: number = 0;
  @State backdropProgress: number = 0;
  @State menuProgress: number = 0;
  @State acceptingActions: boolean = false;
  @State pinned: NotifyContextTarget | null = null;
  @State menuShown: boolean = false;
  @BuilderParam content: () => void = this.emptyContent;
  onAction: (action: NotifyContextAction, target: NotifyContextTarget) => void = () => {};
  // 窗口坐标用于跨列表与浮层换算；动画不改变底层卡片布局和滚动偏移。
  private sourceX: number = 0;
  private sourceY: number = 0;
  private sourceWidth: number = 0;
  private overlayOriginX: number = 0;
  private overlayOriginY: number = 0;
  private animationGeneration: number = 0;
  private animationFrame: number = -1;
  private menuDelay: number = -1;
  private opening: boolean = false;
  private closing: boolean = false;
  // 整个浮层退场后才交付操作，避免动画期间卸载仍在响应事件的 ListItem。
  private pendingAction: NotifyContextAction | null = null;
  private dispatchTimer: number = -1;
  private menuOpen: boolean = false;
  private mounted: boolean = false;

  @Builder
  private emptyContent() {}

  aboutToAppear(): void {
    this.mounted = true;
  }

  aboutToDisappear(): void {
    this.mounted = false;
    this.cancelMenu();
  }

  build() {
    Column() {
      this.content();
    }
    .width('100%')
    .onAreaChange((_old: Area, area: Area) => {
      this.sourceX = Number(area.globalPosition.x);
      this.sourceY = Number(area.globalPosition.y);
      this.sourceWidth = Number(area.width);
    })
    .opacity(this.menuShown ? 0 : 1)
    // 高优先级长按阻止短按详情；滑动失败仍由 List 接管滚动。
    .priorityGesture(LongPressGesture({ repeat: false }).onAction(() => {
      if (this.isAvailable() && !this.menuShown) {
        this.prepareMenu();
        this.menuShown = true;
      }
    }))
    .bindContentCover(this.menuShown, this.previewOverlay(), {
      modalTransition: ModalTransition.NONE,
      backgroundColor: Color.Transparent,
      onWillDismiss: () => this.closeMenu(),
      onDisappear: () => this.finishMenu()
    });
  }

  /** 全屏只提供透明坐标平面，背景、预览、操作区分别播放动画。 */
  @Builder
  private previewOverlay() {
    Stack({ alignContent: Alignment.TopStart }) {
      Row()
        .width('100%').height('100%')
        .backgroundColor('#26000000')
        .backdropBlur(22 * this.backdropProgress)
        .opacity(this.backdropProgress)
        .onClick(() => this.closeMenu());
      this.preview();
      this.menu();
    }
    .width('100%').height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .onAreaChange((_old: Area, area: Area) => {
      const width: number = Number(area.width);
      const height: number = Number(area.height);
      if (width <= 0 || height <= 0) return;
      this.overlayWidth = width;
      this.overlayHeight = height;
      this.overlayOriginX = Number(area.globalPosition.x);
      this.overlayOriginY = Number(area.globalPosition.y);
      this.queueEntrance();
    })
    .accessibilityLevel(this.antiPeepBlur ? 'no-hide-descendants' : 'auto');
  }

  /** 顶边固定在中上部；长正文在预览内部滚动，操作区不随正文滚动。 */
  @Builder
  private preview() {
    Scroll() {
      Column({ space: 10 }) {
        if (this.getTarget().grouped) {
          Text(`${this.getTarget().groupKey || '默认'} · ${this.getTarget().groupTotal} 条通知`)
            .fontSize(13).fontColor($r('app.color.color_brand')).width('100%').maxLines(2)
            .blur(this.antiPeepBlur ? 22 : 0);
        }
        if (this.getTarget().message.title.length > 0) {
          Text(this.getTarget().message.title).fontSize(18).fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.color_text_primary')).width('100%').maxLines(3)
            .textOverflow({ overflow: TextOverflow.Ellipsis }).blur(this.antiPeepBlur ? 22 : 0);
        }
        if (this.getTarget().message.subtitle.length > 0) {
          Text(this.getTarget().message.subtitle).fontSize(14).fontColor($r('app.color.color_brand'))
            .width('100%').maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
            .blur(this.antiPeepBlur ? 22 : 0);
        }
        Text(this.getTarget().message.inboxContent.length > 0 ?
          this.getTarget().message.inboxContent.join('\n') : this.getTarget().message.body)
          .fontSize(14).lineHeight(22).fontColor($r('app.color.color_text_secondary'))
          .width('100%').blur(this.antiPeepBlur ? 22 : 0);
        Text(formatNotifyTime(this.getTarget().message.timestamp)).fontSize(11)
          .fontColor($r('app.color.color_text_hint')).width('100%').textAlign(TextAlign.End)
          .blur(this.antiPeepBlur ? 22 : 0);
      }.width('100%').padding(20).alignItems(HorizontalAlign.Start);
    }
    .width(this.targetWidth())
    .constraintSize({ maxHeight: this.maxPreviewHeight() })
    .scrollBar(BarState.Auto)
    .backgroundColor($r('app.color.color_bg_surface'))
    .borderRadius(20).clip(true)
    .position({ x: (this.overlayWidth - this.targetWidth()) / 2, y: this.targetTop() })
    .scale({ x: 0.94 + 0.06 * this.motionProgress, y: 0.94 + 0.06 * this.motionProgress,
      centerX: '50%', centerY: 0 })
    .translate({
      x: (this.sourceX + this.sourceWidth / 2 - this.overlayOriginX - this.overlayWidth / 2) *
        (1 - this.motionProgress),
      y: (this.sourceY - this.overlayOriginY - this.targetTop()) * (1 - this.motionProgress)
    })
    .onAreaChange((_old: Area, area: Area) => {
      const height: number = Number(area.height);
      if (height > 0 && this.previewHeight !== height) this.previewHeight = height;
      this.queueEntrance();
    })
    .accessibilityLevel(this.antiPeepBlur ? 'no-hide-descendants' : 'auto');
  }

  @Builder
  private menu() {
    Menu() {
      if (this.getTarget().grouped) {
        MenuItem({ content: '展开分组' })
          .onClick(() => this.choose(NotifyContextAction.ExpandGroup));
        MenuItem({ content: '多选分组' })
          .onClick(() => this.choose(NotifyContextAction.SelectGroup));
        MenuItem({ content: '删除分组' })
          .contentFontColor($r('app.color.color_error'))
          .onClick(() => this.choose(NotifyContextAction.DeleteGroup));
      } else {
        MenuItem({ content: '查看详情' })
          .onClick(() => this.choose(NotifyContextAction.ViewDetail));
        MenuItem({ content: '多选' })
          .onClick(() => this.choose(NotifyContextAction.Select));
        MenuItem({ content: '复制全文' })
          .onClick(() => this.choose(NotifyContextAction.CopyAll));
        if (this.getTarget().message.copy.length > 0) {
          MenuItem({ content: '复制 Copy 参数内容' })
            .onClick(() => this.choose(NotifyContextAction.CopyContent));
        }
        if (this.getTarget().message.url.length > 0) {
          MenuItem({ content: '复制链接' })
            .onClick(() => this.choose(NotifyContextAction.CopyUrl));
          MenuItem({ content: '访问链接' })
            .onClick(() => this.choose(NotifyContextAction.OpenUrl));
        }
        MenuItem({ content: '删除' })
          .contentFontColor($r('app.color.color_error'))
          .onClick(() => this.choose(NotifyContextAction.Delete));
      }
    }
    .width(Math.min(this.targetWidth(), 260))
    .constraintSize({ maxHeight: Math.max(80, this.overlayHeight - this.targetTop() -
      this.previewHeight - 24 - this.navBarHeight) })
    // 自绘移动浮层沿用材质工具的毛玻璃降级，避免跨层位移中系统材质中断绘制。
    .backgroundColor($r('app.color.color_bg_glass_control'))
    .backgroundBlurStyle(resolveBlurStyle('card'))
    .border({ width: 1, color: $r('app.color.color_border_glass') })
    .borderRadius(20).clip(true)
    .position({ x: (this.overlayWidth - this.targetWidth()) / 2,
      y: this.targetTop() + this.previewHeight + 12 })
    .opacity(this.menuProgress)
    .translate({ y: 8 * (1 - this.menuProgress) })
    .hitTestBehavior(this.acceptingActions ? HitTestMode.Default : HitTestMode.None);
  }

  /** 固定本轮消息对象；实际操作仍由通知页按复合身份重新查库。 */
  private getTarget(): NotifyContextTarget {
    return this.pinned ?? { message: this.message, grouped: this.grouped,
      groupKey: this.groupKey, groupTotal: this.groupTotal };
  }

  private isAvailable(): boolean {
    return !this.disabled && !this.antiPeepBlur && this.pageVisible && this.homeTabIndex === 0;
  }

  private prepareMenu(): void {
    // 搜索输入中的键盘不能遮住固定预览和菜单；只清焦点，不退出搜索或清空关键词。
    this.getUIContext().getFocusController().clearFocus();
    this.stopAnimation();
    this.closing = false;
    this.opening = false;
    this.acceptingActions = false;
    this.motionProgress = 0;
    this.backdropProgress = 0;
    this.menuProgress = 0;
    this.previewHeight = 0;
    this.pinned = { message: this.message, grouped: this.grouped, groupKey: this.groupKey, groupTotal: this.groupTotal };
    this.pendingAction = null;
    this.menuOpen = true;
  }

  private choose(action: NotifyContextAction): void {
    if (!this.menuOpen || !this.acceptingActions || !this.isAvailable() || this.pendingAction !== null) return;
    this.pendingAction = action;
    this.closeMenu();
  }

  /** 点空白或返回只退场；只有点选操作才向通知页交付意图。 */
  private finishMenu(): void {
    const action: NotifyContextAction | null = this.pendingAction;
    const target: NotifyContextTarget | null = this.pinned;
    this.stopAnimation();
    this.menuOpen = false;
    this.menuShown = false;
    this.closing = false;
    this.acceptingActions = false;
    this.pendingAction = null;
    this.pinned = null;
    if (action === null || target === null) return;
    this.dispatchTimer = setTimeout(() => {
      this.dispatchTimer = -1;
      if (this.mounted && this.isAvailable()) this.onAction(action, target);
    }, 0);
  }

  /** 固定窗口相对顶边；消息高度和长按位置均不改变最终位置。 */
  private targetTop(): number {
    return this.statusBarHeight + Math.min(104, Math.max(32, (this.overlayHeight - this.statusBarHeight) * 0.14));
  }

  private targetWidth(): number {
    return Math.max(160, Math.min(this.overlayWidth - 32, 420));
  }

  /** 最多七个菜单行，预留其高度；小屏优先缩短可滚动预览。 */
  private maxPreviewHeight(): number {
    const target: NotifyContextTarget = this.getTarget();
    const rows: number = target.grouped ? 3 : 4 + (target.message.copy ? 1 : 0) + (target.message.url ? 2 : 0);
    return Math.max(80, Math.min(320, this.overlayHeight - this.targetTop() - rows * 48 - 40 - this.navBarHeight));
  }

  /** 浮层与预览都测量完成后，再从原卡片窗口坐标启动动画。 */
  private queueEntrance(): void {
    if (!this.menuShown || !this.mounted || this.opening || this.closing ||
      this.animationFrame >= 0 || this.previewHeight <= 0) return;
    const generation: number = this.animationGeneration;
    this.animationFrame = setTimeout(() => {
      this.animationFrame = -1;
      if (generation !== this.animationGeneration || !this.menuShown || this.closing || !this.isAvailable()) return;
      this.opening = true;
      this.getUIContext().animateTo({ duration: 300, curve: Curve.EaseOut, onFinish: () => {
        if (generation === this.animationGeneration && !this.closing) this.acceptingActions = true;
      } }, () => {
        this.motionProgress = 1;
        this.backdropProgress = 1;
      });
      this.menuDelay = setTimeout(() => {
        this.menuDelay = -1;
        if (generation !== this.animationGeneration || this.closing) return;
        this.getUIContext().animateTo({ duration: 160, curve: Curve.EaseOut }, () => { this.menuProgress = 1; });
      }, 100);
    }, 32);
  }

  /** 返回、空白和操作共享反向动画；连点合并，退场完成才卸载浮层。 */
  private closeMenu(): void {
    if (!this.menuShown || this.closing) return;
    this.stopAnimation();
    this.closing = true;
    this.acceptingActions = false;
    const generation: number = this.animationGeneration;
    this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseInOut, onFinish: () => {
      if (generation === this.animationGeneration) this.menuShown = false;
    } }, () => {
      this.motionProgress = 0;
      this.menuProgress = 0;
      this.backdropProgress = 0;
    });
  }

  /** 离页、防窥与销毁废弃整轮动画，迟到回调不能重新展示浮层。 */
  private stopAnimation(): void {
    this.animationGeneration++;
    if (this.animationFrame >= 0) {
      clearTimeout(this.animationFrame);
      this.animationFrame = -1;
    }
    if (this.menuDelay >= 0) {
      clearTimeout(this.menuDelay);
      this.menuDelay = -1;
    }
  }

  private onAvailabilityChanged(): void {
    if (!this.isAvailable()) this.cancelMenu();
  }

  private onTargetChanged(): void {
    if (this.pinned && notifyIdentity(this.pinned.message) !== notifyIdentity(this.message)) this.cancelMenu();
  }

  /** 不可用时立即取消浮层与待执行操作，不等待动画暴露旧内容。 */
  private cancelMenu(): void {
    this.pendingAction = null;
    if (this.dispatchTimer >= 0) {
      clearTimeout(this.dispatchTimer);
      this.dispatchTimer = -1;
    }
    this.stopAnimation();
    this.acceptingActions = false;
    if (this.menuOpen) this.menuShown = false;
  }
}
