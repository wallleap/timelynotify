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
  @Prop immersiveLightEnabled: boolean = true;
  listScroller: Scroller = new Scroller();
  // 主 List 唯一的数据源；分组内消息删除时可直接发送 onDataDelete。
  private dataSource: NotifyListDataSource = new NotifyListDataSource();
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

  aboutToAppear(): void {
    this.reloadDataSource();
  }

  build() {
    List({ space: 0, scroller: this.listScroller }) {
      // 非 HDS 标题栏高度为状态栏加 70vp，额外保留 16vp 使首张卡片自然分隔。
      // 沉浸光感下标题栏透明，18vp 让首张卡片与状态栏图标自然分隔。
      ListItem() {
        Row()
          .width('100%')
          .height(SUPPORTS_IMMERSIVE_MATERIAL && this.immersiveLightEnabled ? 18 :
            this.statusBarHeight + 86);
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
    .padding({ left: 16, right: 16 })
    .align(Alignment.Top)
    .clip(false)
    .onDidScroll((scrollOffset: number, scrollState: ScrollState) => {
      this.onListScroll(scrollOffset, scrollState);
    })
    .onReachStart(() => {
      this.onListReachStart();
    });
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
