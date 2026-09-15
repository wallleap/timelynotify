/** 分组通知展开态与卡片高度的不可变状态计算。 */
export class NotifyGroupStateUtils {
  /** 指定分组是否展开。 */
  static isExpanded(expandedGroups: string[], groupKey: string): boolean {
    return expandedGroups.indexOf(groupKey) >= 0;
  }

  /** 返回切换后的展开分组集合。 */
  static toggleExpanded(expandedGroups: string[], groupKey: string): string[] {
    if (NotifyGroupStateUtils.isExpanded(expandedGroups, groupKey)) {
      return expandedGroups.filter((key: string) => key !== groupKey);
    }
    return [...expandedGroups, groupKey];
  }

  /** 更新实测高度；抖动小于半 vp 时复用旧 Map，避免额外重渲染。 */
  static updateCardHeight(heights: Map<string, number>, groupKey: string, heightVp: number): Map<string, number> {
    if (heightVp <= 0 || Math.abs((heights.get(groupKey) ?? 0) - heightVp) < 0.5) {
      return heights;
    }
    const next: Map<string, number> = new Map<string, number>(heights);
    next.set(groupKey, heightVp);
    return next;
  }
}
