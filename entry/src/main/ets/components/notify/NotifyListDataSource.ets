import { NotifyMessage } from '../../model/NotifyMessage';
import { NotifySection } from './NotifyViewTypes';

/** 主通知列表的渲染行类型：所有行都直接作为 List 的子项。 */
export const NOTIFY_LIST_ROW_MESSAGE: number = 0;
export const NOTIFY_LIST_ROW_GROUP_CARD: number = 1;
export const NOTIFY_LIST_ROW_GROUP_HEADER: number = 2;
export const NOTIFY_LIST_ROW_GROUP_MESSAGE: number = 3;
export const NOTIFY_LIST_ROW_GROUP_MORE: number = 4;

/** 可被 IDataSource 精确增删的通知列表行。 */
export class NotifyListRow {
  key: string = '';
  type: number = NOTIFY_LIST_ROW_MESSAGE;
  message: NotifyMessage | null = null;
  section: NotifySection | null = null;
  indexInGroup: number = 0;
  // 主 List 统一 space=0；仅分组边界的末行保留 10vp 间距。
  spaceAfter: number = 0;
}

/** 将当前分组快照扁平为主 List 的直接子项，供 LazyForEach 渲染。 */
export function buildNotifyListRows(sections: NotifySection[], expandedGroups: string[]): NotifyListRow[] {
  const rows: NotifyListRow[] = [];
  for (let i = 0; i < sections.length; i++) {
    const section: NotifySection = sections[i];
    const expanded: boolean = expandedGroups.indexOf(section.groupKey) >= 0;
    if (!section.grouped && !expanded) {
      const row: NotifyListRow = new NotifyListRow();
      row.key = `message:${section.messages[0].id}`;
      row.type = NOTIFY_LIST_ROW_MESSAGE;
      row.message = section.messages[0];
      row.section = section;
      row.spaceAfter = 10;
      rows.push(row);
      continue;
    }
    if (!expanded) {
      const row: NotifyListRow = new NotifyListRow();
      // 计数和预览内容会随删除变化；将总数与内存条数纳入卡片 key，确保徽标和首条预览同步刷新。
      row.key = `group-card:${section.groupKey}:${section.total}:${section.messages.length}`;
      row.type = NOTIFY_LIST_ROW_GROUP_CARD;
      row.section = section;
      row.spaceAfter = 10;
      rows.push(row);
      continue;
    }
    const header: NotifyListRow = new NotifyListRow();
    // 展开态只重建分组头以刷新“共 N 条”，组内未变化的消息行仍保持稳定 key。
    header.key = `group-header:${section.groupKey}:${section.total}`;
    header.type = NOTIFY_LIST_ROW_GROUP_HEADER;
    header.section = section;
    rows.push(header);
    for (let j = 0; j < section.messages.length; j++) {
      const row: NotifyListRow = new NotifyListRow();
      const isGroupTail: boolean = j === section.messages.length - 1 && section.total <= section.messages.length;
      // 末项状态影响圆角和裁剪。仅在某条消息变为末项时变更其 key，强制重建该行；
      // 其余消息继续使用稳定 key，删除时不会引入整组重建或滚动位置跳动。
      row.key = `group-message:${section.groupKey}:${section.messages[j].id}:${isGroupTail ? 'tail' : 'body'}`;
      row.type = NOTIFY_LIST_ROW_GROUP_MESSAGE;
      row.message = section.messages[j];
      row.section = section;
      row.indexInGroup = j;
      row.spaceAfter = isGroupTail ? 10 : 0;
      rows.push(row);
    }
    if (section.total > section.messages.length) {
      const row: NotifyListRow = new NotifyListRow();
      row.key = `group-more:${section.groupKey}`;
      row.type = NOTIFY_LIST_ROW_GROUP_MORE;
      row.section = section;
      row.spaceAfter = 10;
      rows.push(row);
    }
  }
  return rows;
}

/** LazyForEach 的通知数据源，提供精确删除和完整重载通知。 */
export class NotifyListDataSource implements IDataSource {
  private rows: NotifyListRow[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number { return this.rows.length; }
  getData(index: number): NotifyListRow { return this.rows[index]; }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const index: number = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
    }
  }

  /** 以新渲染行完整重载；用于刷新、切换服务和展开/收起。 */
  replace(rows: NotifyListRow[]): void {
    this.rows = rows;
    this.listeners.forEach((listener: DataChangeListener) => listener.onDataReloaded());
  }

  /**
   * 同步最新行快照。所有结构变化均以精确增删通知交给 LazyForEach，避免展开收起时
   * onDataReloaded 先销毁折叠卡片，导致 geometryTransition 丢失共享元素源节点。
   */
  sync(rows: NotifyListRow[]): void {
    if (this.rows.length === 0) {
      this.replace(rows);
      return;
    }
    const nextKeys: Set<string> = new Set<string>();
    for (let i = 0; i < rows.length; i++) {
      nextKeys.add(rows[i].key);
    }
    // 先剔除不再存在的行，例如折叠态 group-card；不要全量重载，以保留转场源节点。
    for (let i = this.rows.length - 1; i >= 0; i--) {
      if (!nextKeys.has(this.rows[i].key)) {
        this.rows.splice(i, 1);
        this.listeners.forEach((listener: DataChangeListener) => listener.onDataDelete(i));
      }
    }
    // 再在目标位置补入新行，例如展开态的分组头和组内消息行。
    for (let i = 0; i < rows.length; i++) {
      if (i >= this.rows.length || this.rows[i].key !== rows[i].key) {
        this.rows.splice(i, 0, rows[i]);
        this.listeners.forEach((listener: DataChangeListener) => listener.onDataAdd(i));
      } else {
        this.rows[i] = rows[i];
        this.listeners.forEach((listener: DataChangeListener) => listener.onDataChange(i));
      }
    }
    // 防御性清理：目标快照比现有行短时，移除末尾冗余行。
    for (let i = this.rows.length - 1; i >= rows.length; i--) {
      this.rows.splice(i, 1);
      this.listeners.forEach((listener: DataChangeListener) => listener.onDataDelete(i));
    }
  }

  /** 删除指定消息对应的当前行，并精确通知 LazyForEach。 */
  removeMessage(id: number): boolean {
    for (let i = 0; i < this.rows.length; i++) {
      const message: NotifyMessage | null = this.rows[i].message;
      if (message && message.id === id) {
        this.rows.splice(i, 1);
        this.listeners.forEach((listener: DataChangeListener) => listener.onDataDelete(i));
        return true;
      }
    }
    return false;
  }
}
