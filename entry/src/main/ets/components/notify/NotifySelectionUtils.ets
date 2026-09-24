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

/** 按 Checkbox 给出的目标状态设置单条消息；重复回显不产生新状态。 */
export function setSelectedMessage(selectedIds: number[], id: number, selected: boolean): number[] {
  return hasSelectedMessage(selectedIds, id) === selected ? selectedIds : toggleSelectedMessage(selectedIds, id);
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

/** 按 Checkbox 的目标状态设置已加载组内消息；重复回显不再反向切换。 */
export function setGroupMessagesSelection(selectedIds: number[], messages: NotifyMessage[], selected: boolean): number[] {
  if (messages.length === 0 || areGroupMessagesSelected(selectedIds, messages) === selected) {
    return selectedIds;
  }
  return toggleGroupMessages(selectedIds, messages);
}

/**
 * 删除消息后，仅保留仍是“多条分组”的展开状态（空 group_key 对应“默认”分组，也需纳入统计）：
 * - 真实总数（含尚未加载到内存的历史）只剩 1 条时自动收起，让该条回到普通卡片；
 * - 总数仍大于 1（例如大分组只加载了部分消息）时保留展开，避免收起后看不到“加载更多”入口。
 * totals 缺省或缺少对应分组时，回退为内存中的消息计数。
 */
export function retainExpandableGroups(messages: NotifyMessage[], expandedGroups: string[],
  totals?: Map<string, number>): string[] {
  const counts: Map<string, number> = new Map<string, number>();
  for (let i = 0; i < messages.length; i++) {
    const groupKey: string = messages[i].group;
    counts.set(groupKey, (counts.get(groupKey) ?? 0) + 1);
  }
  return expandedGroups.filter((groupKey: string) => {
    const memoryCount: number = counts.get(groupKey) ?? 0;
    const total: number = totals ? (totals.get(groupKey) ?? memoryCount) : memoryCount;
    return total > 1;
  });
}
