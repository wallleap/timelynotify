export const DOMAIN: number = 0x0000;

/** AppStorage 键：主页当前选中 Tab 索引（Index 写入，NotifyView 监听以在切走时退出多选模式） */
export const KEY_HOME_TAB_INDEX: string = 'homeTabIndex';

/** AppStorage 键：通知页多选编辑态（NotifyView 持有并同步，Index onBackPress 读取以拦截返回退出编辑） */
export const KEY_NOTIFY_EDITING: string = 'notifyIsEditing';

/** AppStorage 键：通知列表刷新信号（EntryAbility 回前台/点击通知拉起时自增，NotifyView 监听变化后刷新列表） */
export const KEY_NOTIFY_REFRESH_SIGNAL: string = 'notifyRefreshSignal';

/** 系统通知点击请求：[实例 ID, 消息 ID 字符串, 唯一序号]，none 另带第四项。 */
export const KEY_NOTIFY_OPEN_REQUEST: string = 'notifyOpenRequest';

/** AppStorage 键：主页页面可见状态（Index onPageShow/onPageHide 写入，NotifyView 监听以启停前台轮询） */
export const KEY_INDEX_PAGE_VISIBLE: string = 'indexPageVisible';

/** 应用级通知同步状态：任意页面均可观察进度，通知页按 revision 刷新本地列表。 */
export const KEY_NOTIFY_SYNC_PROGRESS: string = 'notifySyncProgress';
export const KEY_NOTIFY_SYNC_FEEDBACK: string = 'notifySyncFeedback';
export const KEY_NOTIFY_SYNC_REVISION: string = 'notifySyncRevision';
