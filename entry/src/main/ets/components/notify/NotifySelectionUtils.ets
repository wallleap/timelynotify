import { NotifyMessage } from '../../model/NotifyMessage';
import { notifyIdentity } from '../../utils/NotifyIdentity';

/** 返回指定消息是否处于多选集合中。 */
export function hasSelectedMessage(selectedIds: string[], id: string): boolean {
  return selectedIds.indexOf(id) >= 0;
}

/** 不可变地切换单条消息的选中状态。 */
export function toggleSelectedMessage(selectedIds: string[], id: string): string[] {
  const index: number = selectedIds.indexOf(id);
  if (index < 0) {
    return [...selectedIds, id];
  }
  const next: string[] = [...selectedIds];
  next.splice(index, 1);
  return next;
}

/** 按 Checkbox 给出的目标状态设置单条消息；重复回显不产生新状态。 */
export function setSelectedMessage(selectedIds: string[], id: string, selected: boolean): string[] {
  return hasSelectedMessage(selectedIds, id) === selected ? selectedIds : toggleSelectedMessage(selectedIds, id);
}

/** 判断一组消息是否已全部选中。 */
export function areGroupMessagesSelected(selectedIds: string[], messages: NotifyMessage[]): boolean {
  if (messages.length === 0) {
    return false;
  }
  for (let i = 0; i < messages.length; i++) {
    if (!hasSelectedMessage(selectedIds, notifyIdentity(messages[i]))) {
      return false;
    }
  }
  return true;
}

/** 不可变地切换整组消息的选择状态。 */
export function toggleGroupMessages(selectedIds: string[], messages: NotifyMessage[]): string[] {
  if (areGroupMessagesSelected(selectedIds, messages)) {
    const groupIds: Set<string> = new Set<string>();
    for (let i = 0; i < messages.length; i++) {
      groupIds.add(notifyIdentity(messages[i]));
    }
    return selectedIds.filter((id: string) => !groupIds.has(id));
  }
  const next: string[] = [...selectedIds];
  for (let i = 0; i < messages.length; i++) {
    const id: string = notifyIdentity(messages[i]);
    if (!hasSelectedMessage(next, id)) {
      next.push(id);
    }
  }
  return next;
}

/** 按 Checkbox 的目标状态设置已加载组内消息；重复回显不再反向切换。 */
export function setGroupMessagesSelection(selectedIds: string[], messages: NotifyMessage[], selected: boolean): string[] {
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
