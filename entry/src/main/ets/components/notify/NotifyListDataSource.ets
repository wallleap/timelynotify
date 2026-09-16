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
      row.key = `group-card:${section.groupKey}`;
      row.type = NOTIFY_LIST_ROW_GROUP_CARD;
      row.section = section;
      row.spaceAfter = 10;
      rows.push(row);
      continue;
    }
    const header: NotifyListRow = new NotifyListRow();
    header.key = `group-header:${section.groupKey}`;
    header.type = NOTIFY_LIST_ROW_GROUP_HEADER;
    header.section = section;
    rows.push(header);
    for (let j = 0; j < section.messages.length; j++) {
      const row: NotifyListRow = new NotifyListRow();
      row.key = `group-message:${section.groupKey}:${section.messages[j].id}`;
      row.type = NOTIFY_LIST_ROW_GROUP_MESSAGE;
      row.message = section.messages[j];
      row.section = section;
      row.indexInGroup = j;
      row.spaceAfter = j === section.messages.length - 1 && section.total <= section.messages.length ? 10 : 0;
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
   * 同步最新行快照。仅发生消息行删除时，逐项发送 onDataDelete，避免整组重载；
   * 新增、展开收起及其它结构变化回退到 onDataReloaded，以保证列表结构正确。
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
    let hasAdded: boolean = false;
    for (let i = 0; i < rows.length; i++) {
      let found: boolean = false;
      for (let j = 0; j < this.rows.length; j++) {
        if (rows[i].key === this.rows[j].key) {
          found = true;
          break;
        }
      }
      if (!found) {
        hasAdded = true;
        break;
      }
    }
    if (hasAdded) {
      this.replace(rows);
      return;
    }
    for (let i = this.rows.length - 1; i >= 0; i--) {
      if (!nextKeys.has(this.rows[i].key)) {
        this.rows.splice(i, 1);
        this.listeners.forEach((listener: DataChangeListener) => listener.onDataDelete(i));
      }
    }
    for (let i = 0; i < rows.length; i++) {
      this.rows[i] = rows[i];
      this.listeners.forEach((listener: DataChangeListener) => listener.onDataChange(i));
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
