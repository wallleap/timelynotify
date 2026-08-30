export const DOMAIN: number = 0x0000;

/** AppStorage 键：主页当前选中 Tab 索引（Index 写入，NotifyView 监听以在切走时退出多选模式） */
export const KEY_HOME_TAB_INDEX: string = 'homeTabIndex';

/** AppStorage 键：通知页多选编辑态（NotifyView 持有并同步，Index onBackPress 读取以拦截返回退出编辑） */
export const KEY_NOTIFY_EDITING: string = 'notifyIsEditing';
