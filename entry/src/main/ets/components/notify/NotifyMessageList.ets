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
  @Prop loadingMore: boolean = false;
  @Prop hasMore: boolean = true;
  @Prop statusBarHeight: number = 0;
  @Prop navBarHeight: number = 0;
  @Prop immersiveLightEnabled: boolean = true;
  listScroller: Scroller = new Scroller();
  onLoadMore: () => void = () => {};
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

  private isSelected(id: number): boolean { return this.selectedIds.indexOf(id) >= 0; }
  private isExpanded(groupKey: string): boolean { return this.expandedGroups.indexOf(groupKey) >= 0; }
  private groupSelected(messages: NotifyMessage[]): boolean {
    return messages.length > 0 && messages.every((message: NotifyMessage) => this.isSelected(message.id));
  }

  @Builder
  private deleteOne(message: NotifyMessage) { NotifySwipeDelete({ onDelete: () => this.onDeleteOne(message) }); }
  @Builder
  private deleteGroup(section: NotifySection) { NotifySwipeDelete({ onDelete: () => this.onDeleteGroup(section) }); }

  build() {
    List({ space: 10, scroller: this.listScroller }) {
      ListItem() { Row().width('100%').height(SUPPORTS_IMMERSIVE_MATERIAL && this.immersiveLightEnabled ? 4 : this.statusBarHeight + 78); }
      ForEach(buildNotifySections(this.messages), (section: NotifySection) => {
        if (!section.grouped) {
          ListItem() {
            NotifyMessageCard({ message: section.messages[0], isEditing: this.isEditing, selected: this.isSelected(section.messages[0].id),
              onSelect: (id: number) => this.onToggleSelect(id), onOpen: (message: NotifyMessage) => this.onOpenMessage(message),
              onOpenUrl: (url: string) => this.onOpenUrl(url), onCopyCode: (code: string) => this.onCopyCode(code) });
          }.swipeAction({ end: { builder: () => { this.deleteOne(section.messages[0]); } } });
        } else if (this.isExpanded(section.groupKey)) {
          ListItemGroup({ space: 0, header: this.expandedHeader(section) }) {
            ForEach(section.messages, (message: NotifyMessage, index: number) => {
              ListItem() {
                NotifyGroupMessageRow({ message: message, isLast: index === section.messages.length - 1, isEditing: this.isEditing,
                  selected: this.isSelected(message.id), contentTransitionId: index === 0 ? `gmc:${section.groupKey}` : '',
                  onSelect: (id: number) => this.onToggleSelect(id), onOpen: (item: NotifyMessage) => this.onOpenMessage(item),
                  onOpenUrl: (url: string) => this.onOpenUrl(url), onCopyCode: (code: string) => this.onCopyCode(code) });
              }.swipeAction({ end: { builder: () => { this.deleteOne(message); } } });
            }, (message: NotifyMessage) => `group-child:${section.groupKey}:${message.id}`);
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
      if (this.loadingMore) {
        ListItem() { LoadingProgress().width(18).height(18).color($r('app.color.text_accent_color')); }.height(44);
      } else if (!this.hasMore && this.messages.length > 0) {
        ListItem() { Text('没有更多了').fontSize(12).fontColor($r('app.color.text_quinary_color')).width('100%').textAlign(TextAlign.Center); }.height(40);
      }
      ListItem() { Row().width('100%').height(this.navBarHeight + (SUPPORTS_IMMERSIVE_MATERIAL && this.immersiveLightEnabled ? 72 : 64)); }
    }
    .width('100%').height('100%').padding({ left: 16, right: 16 }).align(Alignment.Top).clip(false).onReachEnd(() => this.onLoadMore());
  }

  @Builder
  private expandedHeader(section: NotifySection) {
    NotifyGroupExpandedHeader({ section: section, isEditing: this.isEditing, groupSelected: this.groupSelected(section.messages),
      onToggle: () => this.isEditing ? this.onToggleGroupSelection(section.messages) : this.onToggleGroupExpanded(section.groupKey) });
  }
}
