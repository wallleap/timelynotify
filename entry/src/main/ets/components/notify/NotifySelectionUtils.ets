import { NotifyMessage } from '../../model/NotifyMessage';

/** 返回指定消息是否处于多选集合中。 */
export function hasSelectedMessage(selectedIds: number[], id: number): boolean {
  return selectedIds.indexOf(id) >= 0;
}

/** 不可变地切换单条消息的选中状态。 */
export function toggleSelectedMessage(selectedIds: number[], id: number): number[] {
  const index: number = selectedIds.indexOf(id);
  if (index < 0) {
    return [...selectedIds, id];
  }
  const next: number[] = [...selectedIds];
  next.splice(index, 1);
  return next;
}

/** 判断一组消息是否已全部选中。 */
export function areGroupMessagesSelected(selectedIds: number[], messages: NotifyMessage[]): boolean {
  if (messages.length === 0) {
    return false;
  }
  for (let i = 0; i < messages.length; i++) {
    if (!hasSelectedMessage(selectedIds, messages[i].id)) {
      return false;
    }
  }
  return true;
}

/** 不可变地切换整组消息的选择状态。 */
export function toggleGroupMessages(selectedIds: number[], messages: NotifyMessage[]): number[] {
  if (areGroupMessagesSelected(selectedIds, messages)) {
    const groupIds: Set<number> = new Set<number>();
    for (let i = 0; i < messages.length; i++) {
      groupIds.add(messages[i].id);
    }
    return selectedIds.filter((id: number) => !groupIds.has(id));
  }
  const next: number[] = [...selectedIds];
  for (let i = 0; i < messages.length; i++) {
    if (!hasSelectedMessage(next, messages[i].id)) {
      next.push(messages[i].id);
    }
  }
  return next;
}

/** 删除消息后，保留仍拥有至少两条消息的分组展开状态。 */
export function retainExpandableGroups(messages: NotifyMessage[], expandedGroups: string[]): string[] {
  const counts: Map<string, number> = new Map<string, number>();
  for (let i = 0; i < messages.length; i++) {
    const groupKey: string = messages[i].group;
    if (groupKey.length > 0) {
      counts.set(groupKey, (counts.get(groupKey) ?? 0) + 1);
    }
  }
  return expandedGroups.filter((groupKey: string) => (counts.get(groupKey) ?? 0) >= 2);
}
