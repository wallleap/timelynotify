import { NotifyMessage } from '../../model/NotifyMessage';
import { NotifySection, buildNotifySections } from './NotifyViewTypes';
import { NotifyMessageCard } from './NotifyMessageCard';
import { NotifyGroupCard } from './NotifyGroupCard';
import { NotifyGroupExpandedHeader } from './NotifyGroupExpandedHeader';
import { NotifyGroupMessageRow } from './NotifyGroupMessageRow';
import { NotifySwipeDelete } from './NotifySwipeDelete';
import { SUPPORTS_IMMERSIVE_MATERIAL } from '../../utils/ImmersiveUtil';

/** 通知列表渲染层：只接收状态快照并通过回调将用户操作交还页面。 */
@Component
export struct NotifyMessageList {
  @Prop messages: NotifyMessage[] = [];
  @Prop isEditing: boolean = false;
  @Prop selectedIds: number[] = [];
  @Prop expandedGroups: string[] = [];
  @Prop groupCardHeights: Map<string, number> = new Map<string, number>();
  @Prop groupTotals: Map<string, number> = new Map<string, number>();
  @Prop groupLoadingMore: Set<string> = new Set<string>();
  // 是否启用分组显示（false 时所有消息平铺）
  @Prop groupEnabled: boolean = true;
  @Prop statusBarHeight: number = 0;
  @Prop navBarHeight: number = 0;
  @Prop immersiveLightEnabled: boolean = true;
  listScroller: Scroller = new Scroller();
  onLoadMoreInGroup: (groupKey: string) => void = (_groupKey: string) => {};
  onToggleSelect: (id: number) => void = (_id: number) => {};
  onToggleGroupSelection: (messages: NotifyMessage[]) => void = (_messages: NotifyMessage[]) => {};
  onToggleGroupExpanded: (groupKey: string) => void = (_groupKey: string) => {};
  onOpenMessage: (message: NotifyMessage) => void = (_message: NotifyMessage) => {};
  onOpenGroup: (section: NotifySection) => void = (_section: NotifySection) => {};
  onHeightChange: (groupKey: string, height: number) => void = (_groupKey: string, _height: number) => {};
  onDeleteOne: (message: NotifyMessage) => void = (_message: NotifyMessage) => {};
  onDeleteGroup: (section: NotifySection) => void = (_section: NotifySection) => {};
  onOpenUrl: (url: string) => void = (_url: string) => {};
  onCopyCode: (code: string) => void = (_code: string) => {};
  onCopyUrl: (url: string) => void = (_url: string) => {};

  private isSelected(id: number): boolean { return this.selectedIds.indexOf(id) >= 0; }
  private isExpanded(groupKey: string): boolean { return this.expandedGroups.indexOf(groupKey) >= 0; }
  private groupSelected(messages: NotifyMessage[]): boolean {
    return messages.length > 0 && messages.every((message: NotifyMessage) => this.isSelected(message.id));
  }
  // 组内是否还有更多未加载的消息（内存数量 < 真实总数）
  private groupHasMore(section: NotifySection): boolean {
    return section.grouped && section.total > section.messages.length;
  }
  // 组内是否正在加载更多
  private groupLoading(section: NotifySection): boolean {
    return this.groupLoadingMore.has(section.groupKey);
  }

  @Builder
  private deleteOne(message: NotifyMessage) { NotifySwipeDelete({ onDelete: () => this.onDeleteOne(message) }); }
  @Builder
  private deleteGroup(section: NotifySection) { NotifySwipeDelete({ onDelete: () => this.onDeleteGroup(section) }); }

  @Builder
  private groupLoadMoreFooter(section: NotifySection) {
    Row() {
      if (this.groupLoading(section)) {
        LoadingProgress().width(16).height(16).color($r('app.color.text_accent_color'));
        Text('加载中...').fontSize(13).fontColor($r('app.color.text_quinary_color')).margin({ left: 6 });
      } else {
        Text('加载更多').fontSize(13).fontColor($r('app.color.text_accent_color'));
      }
    }
    .width('100%').height(44).justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center);
  }

  build() {
    List({ space: 10, scroller: this.listScroller }) {
      ListItem() { Row().width('100%').height(SUPPORTS_IMMERSIVE_MATERIAL && this.immersiveLightEnabled ? 4 : this.statusBarHeight + 78); }
      ForEach(buildNotifySections(this.messages, this.groupTotals, this.groupEnabled), (section: NotifySection) => {
        if (!section.grouped) {
          ListItem() {
            NotifyMessageCard({ message: section.messages[0], isEditing: this.isEditing, selected: this.isSelected(section.messages[0].id),
              onSelect: (id: number) => this.onToggleSelect(id), onOpen: (message: NotifyMessage) => this.onOpenMessage(message),
              onOpenUrl: (url: string) => this.onOpenUrl(url), onCopyCode: (code: string) => this.onCopyCode(code),
              onCopyUrl: (url: string) => this.onCopyUrl(url) });
          }.swipeAction({ end: { builder: () => { this.deleteOne(section.messages[0]); } } });
        } else if (this.isExpanded(section.groupKey)) {
          ListItemGroup({ space: 0, header: this.expandedHeader(section) }) {
            ForEach(section.messages, (message: NotifyMessage, index: number) => {
              ListItem() {
                NotifyGroupMessageRow({ message: message, isLast: index === section.messages.length - 1 && !this.groupHasMore(section),
                  isEditing: this.isEditing,
                  selected: this.isSelected(message.id), contentTransitionId: index === 0 ? `gmc:${section.groupKey}` : '',
                  onSelect: (id: number) => this.onToggleSelect(id), onOpen: (item: NotifyMessage) => this.onOpenMessage(item),
                  onOpenUrl: (url: string) => this.onOpenUrl(url), onCopyCode: (code: string) => this.onCopyCode(code),
                  onCopyUrl: (url: string) => this.onCopyUrl(url) });
              }
              .backgroundColor($r('app.color.card_background'))
              .borderRadius({ topLeft: 0, topRight: 0,
                bottomLeft: (index === section.messages.length - 1 && !this.groupHasMore(section)) ? 12 : 0,
                bottomRight: (index === section.messages.length - 1 && !this.groupHasMore(section)) ? 12 : 0 })
              .clip(true)
              .swipeAction({ end: { builder: () => { this.deleteOne(message); } } });
            }, (message: NotifyMessage) => `group-child:${section.groupKey}:${message.id}`);

            // 组内"加载更多"按钮：组内末尾子 ListItem，与消息行同级（消息行点击可正常触发）
            if (this.groupHasMore(section)) {
              ListItem() {
                this.groupLoadMoreFooter(section);
              }.backgroundColor($r('app.color.card_background'))
               .borderRadius({ topLeft: 0, topRight: 0, bottomLeft: 12, bottomRight: 12 })
               .clip(true)
               .onClick(() => {
                 if (!this.groupLoading(section)) {
                   this.onLoadMoreInGroup(section.groupKey);
                 }
               });
            }
          }
        } else {
          ListItem() {
            NotifyGroupCard({ section: section, isEditing: this.isEditing, groupSelected: this.groupSelected(section.messages),
              cardHeight: this.groupCardHeights.get(section.groupKey) ?? 0, onToggleSelection: () => this.onToggleGroupSelection(section.messages),
              onOpen: () => this.onOpenGroup(section), onHeightChange: (height: number) => this.onHeightChange(section.groupKey, height),
              onOpenUrl: (url: string) => this.onOpenUrl(url), onCopyCode: (code: string) => this.onCopyCode(code) });
          }.swipeAction({ end: { builder: () => { this.deleteGroup(section); } } });
        }
      }, (section: NotifySection) => section.key);
      // 列表底部"没有更多了"提示（有消息时显示）
      ListItem() {
        Row() {
          Text('没有更多了')
            .fontSize(13)
            .fontColor($r('app.color.text_quinary_color'));
        }
        .width('100%')
        .height(40)
        .justifyContent(FlexAlign.Center);
      }
      ListItem() { Row().width('100%').height(this.navBarHeight + (SUPPORTS_IMMERSIVE_MATERIAL && this.immersiveLightEnabled ? 72 : 64)); }
    }
    .width('100%').height('100%').padding({ left: 16, right: 16 }).align(Alignment.Top).clip(false);
  }

  @Builder
  private expandedHeader(section: NotifySection) {
    NotifyGroupExpandedHeader({ section: section, isEditing: this.isEditing, groupSelected: this.groupSelected(section.messages),
      onToggle: () => this.isEditing ? this.onToggleGroupSelection(section.messages) : this.onToggleGroupExpanded(section.groupKey) });
  }
}
