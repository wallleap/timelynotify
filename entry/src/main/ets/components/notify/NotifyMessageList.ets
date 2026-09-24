import { NotifyMessage } from '../../model/NotifyMessage';
import { buildNotifySections, NotifySection } from './NotifyViewTypes';
import { NotifyMessageCard } from './NotifyMessageCard';
import { NotifyGroupCard } from './NotifyGroupCard';
import { NotifyGroupExpandedHeader } from './NotifyGroupExpandedHeader';
import { NotifyGroupMessageRow } from './NotifyGroupMessageRow';
import { NotifySwipeDelete } from './NotifySwipeDelete';
import {
  buildNotifyListRows,
  NOTIFY_LIST_ROW_GROUP_CARD,
  NOTIFY_LIST_ROW_GROUP_HEADER,
  NOTIFY_LIST_ROW_GROUP_MESSAGE,
  NOTIFY_LIST_ROW_GROUP_MORE,
  NOTIFY_LIST_ROW_MESSAGE,
  NotifyListDataSource,
  NotifyListRow
} from './NotifyListDataSource';
import { SUPPORTS_IMMERSIVE_MATERIAL } from '../../utils/ImmersiveUtil';

// 「跳到底部」长距离穿越时，先无动画定位到距末项多少个 ListItem 的位置，再做这一小段平滑滚动。
const SCROLL_TO_BOTTOM_SMOOTH_RANGE: number = 5;
// 列表左右内边距；两种标题栏布局下方均沿用同一间距，保持卡片四周留白一致。
const LIST_EDGE_SPACING: number = 16;

// 「跳到底部」自动滚动状态机：idle=无进行中的自动滚动；jumping=已无动画瞬跳到末段附近，
// 等待 onScrollIndex 确认后再平滑收尾；smoothing=正在执行最终短程平滑滚动，onScrollStop 后结束。
const AUTO_SCROLL_IDLE: number = 0;
const AUTO_SCROLL_JUMPING: number = 1;
const AUTO_SCROLL_SMOOTHING: number = 2;

/** 通知列表渲染层：只接收状态快照并通过回调将用户操作交还页面。 */
@Component
export struct NotifyMessageList {
  @Prop @Watch('reloadDataSource') messages: NotifyMessage[] = [];
  @Prop isEditing: boolean = false;
  @Prop @Watch('reloadDataSource') selectedIds: number[] = [];
  @Prop @Watch('reloadDataSource') expandedGroups: string[] = [];
  @Prop groupCardHeights: Map<string, number> = new Map<string, number>();
  @Prop @Watch('reloadDataSource') groupTotals: Map<string, number> = new Map<string, number>();
  @Prop groupLoadingMore: Set<string> = new Set<string>();
  // 是否启用分组显示（false 时所有消息平铺）
  @Prop @Watch('reloadDataSource') groupEnabled: boolean = true;
  @Prop statusBarHeight: number = 0;
  @Prop navBarHeight: number = 0;
  @Prop topInset: number = 0;
  @Prop immersiveLightEnabled: boolean = true;
  // 「跳到底部」触发信号：页面每次自增，Watch 到变化后执行两段式定位滚动。
  @Prop @Watch('onScrollToBottomRequested') scrollToBottomSignal: number = 0;
  listScroller: Scroller = new Scroller();
  onListTopChange: (top: number) => void = (_top: number) => {};
  // 主 List 唯一的数据源；分组内消息删除时可直接发送 onDataDelete。
  private dataSource: NotifyListDataSource = new NotifyListDataSource();
  // 当前可视区最后一个 ListItem 的绝对索引（由 onScrollIndex 维护），用于估算距末尾的剩余行数。
  private visibleEndIndex: number = 0;
  // 「跳到底部」自动滚动当前阶段；见顶部 AUTO_SCROLL_* 常量的状态机说明。
  private autoScrollState: number = AUTO_SCROLL_IDLE;
  // 本次自动滚动请求的目标末项绝对索引，供状态机判断瞬跳是否到位。
  private autoScrollTargetIndex: number = -1;
  // 平滑滚动兜底定时器：无位移时 onScrollStop 可能不触发，到期强制收尾，避免标记卡死。
  private autoScrollTimeoutId: number = -1;
  onLoadMoreInGroup: (groupKey: string) => void = (_groupKey: string) => {
  };
  onToggleSelect: (id: number) => void = (_id: number) => {
  };
  onSetSelected: (id: number, selected: boolean) => void = (_id: number, _selected: boolean) => {
  };
  onToggleGroupSelection: (messages: NotifyMessage[]) => void = (_messages: NotifyMessage[]) => {
  };
  onSetGroupSelection: (messages: NotifyMessage[], selected: boolean) => void =
    (_messages: NotifyMessage[], _selected: boolean) => {
    };
  onToggleGroupExpanded: (groupKey: string) => void = (_groupKey: string) => {
  };
  onOpenMessage: (message: NotifyMessage) => void = (_message: NotifyMessage) => {
  };
  onOpenGroup: (section: NotifySection) => void = (_section: NotifySection) => {
  };
  onHeightChange: (groupKey: string, height: number) => void = (_groupKey: string, _height: number) => {
  };
  onDeleteOne: (message: NotifyMessage) => void = (_message: NotifyMessage) => {
  };
  onDeleteGroup: (section: NotifySection) => void = (_section: NotifySection) => {
  };
  onOpenUrl: (url: string) => void = (_url: string) => {
  };
  onCopyCode: (code: string) => void = (_code: string) => {
  };
  onCopyUrl: (url: string) => void = (_url: string) => {
  };
  // 列表滚动事件回调：把 scrollOffset 与 scrollState 交还页面，由页面决定「跳到底部」按钮显隐。
  // scrollOffset > 0 表示列表向上滚动（手指上滑），< 0 表示列表向下滚动（手指下滑）。
  onListScroll: (scrollOffset: number, scrollState: ScrollState) => void =
    (_scrollOffset: number, _scrollState: ScrollState) => {
    };
  // 列表到达起点（顶部）回调：双击状态栏等编程式滚动回到顶部时 onDidScroll 可能不触发，
  // 通过 onReachStart 兜底确保「跳到底部」按钮隐藏。
  onListReachStart: () => void = () => {
  };
  // 一次自动定位滚动（含两段式的最终平滑段）真正结束时回调，供页面解除 isAutoScrolling 屏蔽。
  // 普通手指滚动停止同样会触发，页面侧仅幂等清标记，无副作用。
  onAutoScrollEnd: () => void = () => {
  };

  aboutToAppear(): void {
    this.reloadDataSource();
  }

  build() {
    List({ space: 0, scroller: this.listScroller }) {
      // 自绘标题栏按实际遮挡距离避让，再留出与列表左右边距相同的间距。
      // 沉浸光感下 HDS 自行避让标题栏，仅保留与左右边距相同的视觉间距。
      ListItem() {
        Row()
          .width('100%')
          .height(SUPPORTS_IMMERSIVE_MATERIAL && this.immersiveLightEnabled
            ? LIST_EDGE_SPACING
            : this.topInset + LIST_EDGE_SPACING);
      }

      LazyForEach(this.dataSource, (row: NotifyListRow) => {
        if (row.type === NOTIFY_LIST_ROW_MESSAGE && row.message !== null) {
          ListItem() {
            NotifyMessageCard({
              message: row.message,
              isEditing: this.isEditing,
              selected: this.isSelected(row.message.id),
              onSelect: (id: number) => this.onToggleSelect(id),
              onSelectionChange: (id: number, selected: boolean) => this.onSetSelected(id, selected),
              onOpen: (message: NotifyMessage) => this.onOpenMessage(message),
              onOpenUrl: (url: string) => this.onOpenUrl(url),
              onCopyCode: (code: string) => this.onCopyCode(code),
              onCopyUrl: (url: string) => this.onCopyUrl(url)
            });
          }.margin({ bottom: row.spaceAfter }).swipeAction({
            end: {
              builder: () => {
                this.deleteOne(row.message!);
              }
            }
          });
        } else if (row.type === NOTIFY_LIST_ROW_GROUP_CARD && row.section !== null) {
          ListItem() {
            NotifyGroupCard({
              section: row.section,
              isEditing: this.isEditing,
              groupSelected: this.groupSelected(row.section.messages),
              selectedCount: this.groupSelectedCount(row.section.messages),
              cardHeight: this.groupCardHeights.get(row.section.groupKey) ?? 0,
              onToggleSelection: () => this.onToggleGroupSelection(row.section!.messages),
              onSelectionChange: (selected: boolean) => this.onSetGroupSelection(row.section!.messages, selected),
              onOpen: () => this.onOpenGroup(row.section!),
              onHeightChange: (height: number) => this.onHeightChange(row.section!.groupKey, height),
              onOpenUrl: (url: string) => this.onOpenUrl(url),
              onCopyCode: (code: string) => this.onCopyCode(code)
            });
          }.margin({ bottom: row.spaceAfter }).swipeAction({
            end: {
              builder: () => {
                this.deleteGroup(row.section!);
              }
            }
          });
        } else if (row.type === NOTIFY_LIST_ROW_GROUP_HEADER && row.section !== null) {
          ListItem() {
            this.expandedHeader(row.section);
          }.margin({ bottom: row.spaceAfter })
        } else if (row.type === NOTIFY_LIST_ROW_GROUP_MESSAGE && row.message !== null && row.section !== null) {
          ListItem() {
            NotifyGroupMessageRow({
              message: row.message,
              isLast: row.indexInGroup === row.section.messages.length - 1 && !this.groupHasMore(row.section),
              isEditing: this.isEditing,
              selected: this.isSelected(row.message.id),
              contentTransitionId: row.indexInGroup === 0 ? `gmc:${row.section.groupKey}` : '',
              onSelect: (id: number) => this.onToggleSelect(id),
              onSelectionChange: (id: number, selected: boolean) => this.onSetSelected(id, selected),
              onOpen: (item: NotifyMessage) => this.onOpenMessage(item),
              onOpenUrl: (url: string) => this.onOpenUrl(url),
              onCopyCode: (code: string) => this.onCopyCode(code),
              onCopyUrl: (url: string) => this.onCopyUrl(url)
            });
            // 外层 ListItem 不绘制卡片背景，避免复用后旧的方角背景遮住新末条的圆角；
            // NotifyGroupMessageRow 自身依据 isLast 负责背景、裁剪和圆角。
          }
          .margin({ bottom: row.spaceAfter })
          .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseOut }))
          .swipeAction({
            end: {
              builder: () => {
                this.deleteOne(row.message!);
              }
            }
          });
        } else if (row.type === NOTIFY_LIST_ROW_GROUP_MORE && row.section !== null) {
          ListItem() {
            this.groupLoadMoreFooter(row.section);
          }
          .backgroundColor($r('app.color.color_bg_surface'))
          .borderRadius({
            topLeft: 0,
            topRight: 0,
            bottomLeft: 12,
            bottomRight: 12
          })
          .clip(true)
          .margin({ bottom: row.spaceAfter })
          .onClick(() => {
            if (!this.groupLoading(row.section!)) {
              this.onLoadMoreInGroup(row.section!.groupKey);
            }
          });
        }
      }, (row: NotifyListRow) => row.key);
      ListItem() {
        Row() {
          Text('没有更多了').fontSize(13).fontColor($r('app.color.color_text_hint'));
        }.width('100%').height(40).justifyContent(FlexAlign.Center);
      }

      ListItem() {
        Row()
          .width('100%')
          .height(this.navBarHeight + (SUPPORTS_IMMERSIVE_MATERIAL && this.immersiveLightEnabled ? 72 : 64));
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: LIST_EDGE_SPACING, right: LIST_EDGE_SPACING })
    .align(Alignment.Top)
    .clip(false)
    .onAreaChange((_old: Area, area: Area) => {
      this.onListTopChange(area.globalPosition.y as number);
    })
    .onDidScroll((scrollOffset: number, scrollState: ScrollState) => {
      this.onListScroll(scrollOffset, scrollState);
    })
    .onReachStart(() => {
      this.onListReachStart();
    })
    .onTouch((event: TouchEvent) => {
      // onScrollStart 也会在 Scroller 发起的带动画滚动开始时触发，不能识别用户输入；
      // 用 onTouch 的 Down 事件：仅真实手指按下时中断自动滚动，避免第二段 scrollToIndex(true)
      // 启动瞬间被误判为用户手势而提前清状态。
      if (event.type === TouchType.Down) {
        this.interruptAutoScroll();
      }
    })
    .onScrollIndex((firstVisibleIndex: number, lastVisibleIndex: number, _centerIndex: number) => {
      // 记录可视区末尾 ListItem 绝对索引，供「跳到底部」判断剩余行数与驱动瞬跳后的第二段。
      this.visibleEndIndex = lastVisibleIndex;
      this.advanceAutoScrollAfterJump(lastVisibleIndex);
    })
    .onScrollStop(() => {
      // 仅平滑滚动态（smoothing）结束后清除；瞬跳态（jumping）的 stop 事件不可靠，
      // 统一忽略，由 onScrollIndex 驱动下一阶段，避免依赖定时器或吞事件。
      if (this.autoScrollState === AUTO_SCROLL_SMOOTHING) {
        this.finishAutoScroll();
      }
    });
  }

  /**
   * 执行「跳到底部」：按剩余行数进入状态机的 jumping 或 smoothing 阶段。
   * - 剩余行数 ≤ SCROLL_TO_BOTTOM_SMOOTH_RANGE：直接进入平滑滚动贴底（smoothing）；
   * - 剩余行数更远：先无动画瞬跳到末段前几行（jumping），由 onScrollIndex 确认到位后再平滑收尾。
   * 无论距离多近，最终都发起 scrollToIndex(lastIndex, true, END) 由 List 精确对齐到真实末尾；
   * 不依赖“末项可见”这类部分可见的近似判断，避免占位项只露一角时未真正贴底。
   * List 内绝对索引：0=顶部占位；1..dataCount=数据行；dataCount+1=“没有更多了”；dataCount+2=底部占位。
   */
  private onScrollToBottomRequested(): void {
    if (this.scrollToBottomSignal <= 0) {
      return;
    }
    const dataCount: number = this.dataSource.totalCount();
    if (dataCount <= 0) {
      this.finishAutoScroll();
      return;
    }
    const lastIndex: number = dataCount + 2;
    this.autoScrollTargetIndex = lastIndex;
    const remaining: number = lastIndex - this.visibleEndIndex;
    if (remaining <= SCROLL_TO_BOTTOM_SMOOTH_RANGE) {
      this.startSmoothing(lastIndex);
      return;
    }
    // 长距离：先无动画瞬跳到末段起点，交给 onScrollIndex 驱动下一阶段。
    this.autoScrollState = AUTO_SCROLL_JUMPING;
    this.listScroller.scrollToIndex(lastIndex - SCROLL_TO_BOTTOM_SMOOTH_RANGE, false, ScrollAlign.END);
  }

  /**
   * 由 onScrollIndex 驱动：瞬跳（jumping）到位后启动最终平滑段（smoothing）。
   * 不再以 lastVisibleIndex >= lastIndex 早退——瞬跳后即使已接近底部，仍交 List 平滑对齐到真实末尾。
   */
  private advanceAutoScrollAfterJump(lastVisibleIndex: number): void {
    if (this.autoScrollState !== AUTO_SCROLL_JUMPING) {
      return;
    }
    if (lastVisibleIndex < this.autoScrollTargetIndex - SCROLL_TO_BOTTOM_SMOOTH_RANGE) {
      return;
    }
    this.startSmoothing(this.autoScrollTargetIndex);
  }

  /** 进入最终平滑滚动段，并启动兜底定时器，确保无位移（onScrollStop 不触发）时也能收尾。 */
  private startSmoothing(lastIndex: number): void {
    this.autoScrollState = AUTO_SCROLL_SMOOTHING;
    this.clearAutoScrollTimeout();
    this.autoScrollTimeoutId = setTimeout(() => {
      // 安全网而非主驱动：无位移滚动不触发 onScrollStop 时，超时强制收尾。
      if (this.autoScrollState === AUTO_SCROLL_SMOOTHING) {
        this.finishAutoScroll();
      }
    }, 1200);
    this.listScroller.scrollToIndex(lastIndex, true, ScrollAlign.END);
  }

  /** 结束自动滚动：复位状态机、清除兜底定时器并通知页面解除 isAutoScrolling 屏蔽。 */
  private finishAutoScroll(): void {
    this.autoScrollState = AUTO_SCROLL_IDLE;
    this.autoScrollTargetIndex = -1;
    this.clearAutoScrollTimeout();
    this.onAutoScrollEnd();
  }

  private clearAutoScrollTimeout(): void {
    if (this.autoScrollTimeoutId >= 0) {
      clearTimeout(this.autoScrollTimeoutId);
      this.autoScrollTimeoutId = -1;
    }
  }

  /**
   * 中断进行中的自动滚动：用户物理触摸列表、或数据源结构变化时调用，
   * 使瞬跳/平滑阶段失效，避免两段之间强制拉底或目标索引失效。
   * 幂等：idle 状态下不做任何事，不额外回调页面。
   */
  private interruptAutoScroll(): void {
    if (this.autoScrollState !== AUTO_SCROLL_IDLE) {
      this.finishAutoScroll();
    }
  }

  private isSelected(id: number): boolean {
    return this.selectedIds.indexOf(id) >= 0;
  }

  private isExpanded(groupKey: string): boolean {
    return this.expandedGroups.indexOf(groupKey) >= 0;
  }

  private groupSelected(messages: NotifyMessage[]): boolean {
    return messages.length > 0 && messages.every((message: NotifyMessage) => this.isSelected(message.id));
  }

  /** 返回当前已加载的分组消息中已选数量；真实总数由 section.total 单独展示。 */
  private groupSelectedCount(messages: NotifyMessage[]): number {
    let count: number = 0;
    for (let i = 0; i < messages.length; i++) {
      if (this.isSelected(messages[i].id)) {
        count++;
      }
    }
    return count;
  }

  /** 组内是否还有更多未加载的消息（内存数量 < 真实总数）。 */
  private groupHasMore(section: NotifySection): boolean {
    return section.grouped && section.total > section.messages.length;
  }

  /** 组内是否正在加载更多。 */
  private groupLoading(section: NotifySection): boolean {
    return this.groupLoadingMore.has(section.groupKey);
  }

  /** 由输入状态生成主 List 的平铺行；展开/收起或刷新时完整重载。 */
  private reloadDataSource(): void {
    // 数据结构变化（删除、展开/收起、刷新）会使「跳到底部」的目标索引失效，先中断在途自动滚动。
    this.interruptAutoScroll();
    this.dataSource.sync(buildNotifyListRows(
      buildNotifySections(this.messages, this.groupTotals, this.groupEnabled), this.expandedGroups));
  }

  @Builder
  private deleteOne(message: NotifyMessage) {
    NotifySwipeDelete({ onDelete: () => this.onDeleteOne(message) });
  }

  @Builder
  private deleteGroup(section: NotifySection) {
    NotifySwipeDelete({ onDelete: () => this.onDeleteGroup(section) });
  }

  @Builder
  private groupLoadMoreFooter(section: NotifySection) {
    Row() {
      if (this.groupLoading(section)) {
        LoadingProgress().width(16).height(16).color($r('app.color.color_brand'));
        Text('加载中...').fontSize(13).fontColor($r('app.color.color_text_hint')).margin({ left: 6 });
      } else {
        Text('加载更多').fontSize(13).fontColor($r('app.color.color_brand'));
      }
    }
    .width('100%').height(44).justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center);
  }

  @Builder
  private expandedHeader(section: NotifySection) {
    NotifyGroupExpandedHeader({
      section: section,
      isEditing: this.isEditing,
      groupSelected: this.groupSelected(section.messages),
      selectedCount: this.groupSelectedCount(section.messages),
      onToggle: () => this.isEditing ? this.onToggleGroupSelection(section.messages) :
        this.onToggleGroupExpanded(section.groupKey),
      onSelectionChange: (selected: boolean) => this.onSetGroupSelection(section.messages, selected)
    });
  }
}
