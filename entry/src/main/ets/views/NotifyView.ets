import { hilog } from '@kit.PerformanceAnalysisKit';
import { promptAction, UIContext } from '@kit.ArkUI';
import { BusinessError, pasteboard } from '@kit.BasicServicesKit';
import { common, Want } from '@kit.AbilityKit';
import { ServerEntry } from '../model/ServerEntry';
import { ServerManager } from '../services/ServerManager';
import { NotifyMessage } from '../model/NotifyMessage';
import { NotifyMessageService } from '../services/NotifyMessageService';
import { MessageCacheStore } from '../services/MessageCacheStore';
import { DecryptedNotificationService } from '../services/DecryptedNotificationService';
import { DeviceIdPair } from '../services/MessageCacheStore';
import { PreferencesUtil } from '../utils/PreferencesUtil';
import { ServerSettingsDialog } from '../components/ServerSettingsDialog';
import {
  KEY_IMMERSIVE_LIGHT_ENABLED,
  SUPPORTS_IMMERSIVE_MATERIAL,
  resolveBlurStyle
} from '../utils/ImmersiveUtil';
import { hdsMaterial, HdsNavigation, HdsNavigationTitleMode, ScrollEffectType, TextStyleMode } from '@kit.UIDesignKit';
import {
  DOMAIN,
  KEY_HOME_TAB_INDEX,
  KEY_INDEX_PAGE_VISIBLE,
  KEY_NOTIFY_EDITING,
  KEY_NOTIFY_REFRESH_SIGNAL
} from '../common/Constant';
import showToast from '../components/showToast';
import { NotifySection } from '../components/notify/NotifyViewTypes';
import {
  areGroupMessagesSelected,
  hasSelectedMessage,
  retainExpandableGroups,
  setGroupMessagesSelection,
  setSelectedMessage,
  toggleGroupMessages,
  toggleSelectedMessage
} from '../components/notify/NotifySelectionUtils';
import { NotifyMessageDetail } from '../components/notify/NotifyMessageDetail';
import { NotifyTitleBar } from '../components/notify/NotifyTitleBar';
import { NotifyEditActionBar } from '../components/notify/NotifyEditActionBar';
import { NotifyContentState } from '../components/notify/NotifyContentState';
import { NotifyRefreshHeader } from '../components/notify/NotifyRefreshHeader';
import { NotifyGroupStateUtils } from '../components/notify/NotifyGroupStateUtils';
import { NotifyMessageList } from '../components/notify/NotifyMessageList';
import { NotifyExportService } from '../services/NotifyExportService';

const TAG: string = 'NotifyView';

// 补齐"用户停留列表页时新消息不及时出现"的场景
const POLL_INTERVAL_MS: number = 15000;
// 服务端单页上限；首次历史播种持续分页，直到服务端明确返回 hasMore=false。
const SYNC_PAGE_SIZE: number = 100;
// 远程迁移清理采用小批量并发，避免首次历史较多时同时发出 100 个 DELETE 请求。
const REMOTE_DELETE_CONCURRENCY: number = 6;


// 通知页 - 展示接收到的 HTTP 推送消息列表
@Component
export struct NotifyView {
  @State title: string = '';
  @State @Watch('restoreVisibleExpandedGroups') messages: NotifyMessage[] = [];
  @State loading: boolean = false;
  @State errorMsg: string = '';
  @State refreshing: boolean = false;
  @State hasClientToken: boolean = false;
  // 点击查看的消息详情（bindContentCover 全屏模态）
  @State showDetail: boolean = false;
  @State selectedMessage: NotifyMessage | null = null;
  @StorageLink(KEY_NOTIFY_EDITING) @Watch('onIsEditingChanged') isEditing: boolean = false;
  @State selectedIds: number[] = [];
  // 导出选中消息：防重复触发
  @State exportingSelected: boolean = false;
  @State expandedGroups: string[] = [];
  @State groupCardHeights: Map<string, number> = new Map<string, number>();
  // 每个 group_key 的真实总数（含未加载到内存的部分），用于徽标显示和"加载更多"按钮
  @State groupTotals: Map<string, number> = new Map<string, number>();
  // 组内加载更多进行中的 group_key 集合，用于按钮显示 loading 态
  @State groupLoadingMore: Set<string> = new Set<string>();
  // 是否启用分组显示（右下角浮动按钮切换，持久化到 Preferences）
  @State groupEnabled: boolean = true;
  // 视图模式：true=显示所有服务器的通知，false=只显示当前服务器
  @State viewAll: boolean = true;
  // 左滑互斥：当前展开左滑的消息 ID（-1 表示无）
  @StorageProp('statusBarHeight') statusBarHeight: number = 36;
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  @StorageProp(KEY_IMMERSIVE_LIGHT_ENABLED) immersiveLightEnabled: boolean = true;
  // 切回「通知」Tab（值为 0）时自动刷新列表
  @StorageProp(KEY_HOME_TAB_INDEX) @Watch('onHomeTabIndexChanged') homeTabIndex: number = 0;
  @StorageProp(KEY_NOTIFY_REFRESH_SIGNAL) @Watch('onRefreshSignalChanged') refreshSignal: number = 0;
  @StorageProp(KEY_INDEX_PAGE_VISIBLE) @Watch('onPageVisibleChanged') indexPageVisible: boolean = true;
  @State refreshState: RefreshStatus = RefreshStatus.Inactive;
  private dialogController: CustomDialogController = new CustomDialogController({
    builder: ServerSettingsDialog(),
    alignment: DialogAlignment.Center,
    autoCancel: true,
    offset: { dx: 0, dy: 0 },
  });
  private onChange: ((list: ServerEntry[], curId: string) => void) | null = null;
  private loadSeq: number = 0;
  private loadQueued: boolean = false;
  private scroller: Scroller = new Scroller();
  private pollTimer: number = -1;
  // 当前列表对应的 device_key 快照；key 切换时需清空内存中的旧设备消息，即使处于“全部”模式。
  private visibleDeviceKeys: string = '';
  // 防止飞行中的轮询请求在切走 Tab 后又重启循环
  private pollingEnabled: boolean = false;
  // 轮询请求进行中标记：防止慢网络下请求堆积
  private pollInFlight: boolean = false;
  // 持久化的全局展开记录；仅在切换展开/收起时变更，避免切换服务器时误删不可见分组。
  private savedExpandedGroups: string[] = [];
  // Preferences 异步读取完成前不恢复，避免把默认空数组误写回磁盘。
  private expandedGroupsLoaded: boolean = false;

  aboutToAppear() {
    this.initAfterServerManagerReady();
    // 读取分组显示开关（默认开启分组）
    PreferencesUtil.getString(null, PreferencesUtil.KEY_GROUP_ENABLED, 'true')
      .then((value: string) => {
        this.groupEnabled = value === 'true';
      });
    this.loadExpandedGroups();
    this.onChange = (_list: ServerEntry[], _curId: string): void => {
      this.exitEditMode();
      // 从 ServerManager 同步视图模式（ServerSettingsContent 切换全部/单服务器时触发）
      const newViewAll: boolean = ServerManager.getInstance().getViewAllMode();
      const viewModeChanged: boolean = this.viewAll !== newViewAll;
      this.viewAll = newViewAll;
      const nextDeviceKeys: string = this.getAllDeviceKeys().join('|');
      const deviceKeysChanged: boolean = nextDeviceKeys !== this.visibleDeviceKeys;
      this.visibleDeviceKeys = nextDeviceKeys;
      this.refresh();
      // 视图模式变化、单服务器切换或 device_key 变更时，清空内存中的旧数据后重建。
      if (viewModeChanged || !this.viewAll || deviceKeysChanged) {
        this.messages = [];
        this.expandedGroups = [];
        this.groupCardHeights = new Map<string, number>();
        this.groupTotals = new Map<string, number>();
        this.groupLoadingMore = new Set<string>();
      }
      this.loadSeq++;
      this.loadMessages();
    };
    ServerManager.getInstance().addChangeListener(this.onChange);
    if (this.homeTabIndex === 0) {
      this.startPolling();
    }
  }

  aboutToDisappear() {
    if (this.onChange) {
      ServerManager.getInstance().removeChangeListener(this.onChange);
    }
    // 组件销毁时停止轮询，避免定时器泄漏
    this.stopPolling();
  }

  @Builder
  fallbackTitleBar() {
    NotifyTitleBar({ title: this.title, isEditing: this.isEditing, statusBarHeight: this.statusBarHeight,
      onOpenSettings: () => this.handleMoreClicked(), onToggleSelection: () => this.handleMultiSelectClicked(),
      onDelete: () => this.handleDeletePillClicked() });
  }

  @Builder
  customTitleContent() {
    NotifyTitleBar({ title: this.title, isEditing: this.isEditing, useHdsLayout: true,
      onOpenSettings: () => this.handleMoreClicked() });
  }

  @Builder
  refreshContentBody() {
    Refresh({ refreshing: this.refreshing, builder: this.refreshHeaderBuilder() }) {
      if (this.needGuideToConfig()) {
        NotifyContentState({ mode: 'guide' });
      } else if (this.loading && this.messages.length === 0) {
        NotifyContentState({ mode: 'loading' });
      } else if (this.errorMsg.length > 0 && this.messages.length === 0) {
        NotifyContentState({ mode: 'error', errorMsg: this.errorMsg, onRetry: () => this.loadMessages() });
      } else if (this.messages.length === 0) {
        NotifyContentState({ mode: 'empty' });
      } else {
        this.listView();
      }
    }
    .clip(false)
    .width('100%')
    .height('100%')
    .onStateChange((state: RefreshStatus) => {
      // 同步刷新状态给自定义指示器，控制其显隐
      this.refreshState = state === RefreshStatus.Done ? RefreshStatus.Inactive : state;
    })
    .onRefreshing(() => {
      this.refreshing = true;
      this.loadMessages();
    });
  }

  @Builder
  viewportBody() {
    Column() {
      Stack({ alignContent: Alignment.BottomEnd }) {
        Column() {
          this.refreshContentBody();
        }
        .width('100%')
        .layoutWeight(1);

        // 右下角"分组/平铺"模式切换浮动按钮
        // 仅在非编辑模式、有消息时显示
        if (!this.isEditing && this.messages.length > 0) {
          this.groupModeToggleFab();
        }
      }
      .width('100%')
      .layoutWeight(1);

      // 多选模式底部操作栏
      if (this.isEditing && this.messages.length > 0) {
        this.editActionBar();
      }
    }
    .width('100%')
    .height('100%');
  }

  /**
   * 右下角分组模式切换按钮：
   * - 当前分组模式：显示 group_expand 图标，点击切为平铺
   * - 当前平铺模式：显示 group_collapse 图标，点击切为分组
   */
  @Builder
  private groupModeToggleFab() {
    Row() {
      Image(this.groupEnabled ? $r('app.media.group_expand') : $r('app.media.group_collapse'))
        .width(20).height(20).objectFit(ImageFit.Contain)
        .fillColor($r('app.color.color_text_primary'))
        .draggable(false);
    }
    .width(44).height(44).borderRadius(22)
    .justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center)
    .backgroundColor($r('app.color.color_bg_glass_control'))
    .backgroundBlurStyle(resolveBlurStyle('card')!)
    .border({ width: 1, color: $r('app.color.color_border_glass') })
    .margin({ right: 16, bottom: this.navBarHeight + 56 + 16 })
    .onClick(() => {
      this.toggleGroupEnabled();
    });
  }

  build() {
    if (SUPPORTS_IMMERSIVE_MATERIAL && this.immersiveLightEnabled) {
      HdsNavigation() {
        this.viewportBody();
      }
      .titleBar({
        enableComponentSafeArea: true,
        avoidLayoutSafeArea: true,
        content: {
          stackBuilder: (): void => {
            this.customTitleContent();
          },
          menu: {
            value: [
              {
                content: {
                  label: this.isEditing ? '取消' : '多选',
                  type: TextStyleMode.NORMAL,
                  action: (): void => {
                    this.handleMultiSelectClicked();
                  }
                }
              },
              {
                content: {
                  icon: $r('app.media.delete'),
                  action: (): void => {
                    this.handleDeletePillClicked();
                  }
                }
              }
            ]
          },
        },
        style: {
          scrollEffectOpts: {
            enableScrollEffect: true,
            scrollEffectType: ScrollEffectType.GRADIENT_BLUR
          },
          systemMaterialEffect: {
            materialType: hdsMaterial.MaterialType.ADAPTIVE,
            materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
          },
        }
      })
      .hideBackButton(true)
      .titleMode(HdsNavigationTitleMode.MINI)
      .bindToScrollable([this.scroller])
      .width('100%')
      .height('100%')
      .bindContentCover(this.showDetail, this.detailBuilder(), {
        onDisappear: () => {
          this.showDetail = false;
        }
      })
      .backgroundColor($r('app.color.color_bg_page'));
    } else {
      Column() {
        Stack({ alignContent: Alignment.BottomEnd }) {
          Stack({ alignContent: Alignment.Top }) {
            this.refreshContentBody();
            this.fallbackTitleBar();
          }
          .width('100%')
          .height('100%')

          // 非沉浸式分支的右下角分组模式切换按钮
          if (!this.isEditing && this.messages.length > 0) {
            this.groupModeToggleFab();
          }
        }
        .width('100%')
        .layoutWeight(1);

        // 多选模式底部操作栏
        if (this.isEditing && this.messages.length > 0) {
          this.editActionBar();
        }
      }
      .width('100%')
      .height('100%')
      .bindContentCover(this.showDetail, this.detailBuilder(), {
        onDisappear: () => {
          this.showDetail = false;
        }
      })
      .backgroundColor($r('app.color.color_bg_page'));
    }
  }

  @Builder
  refreshHeaderBuilder() {
    NotifyRefreshHeader({ refreshState: this.refreshState, statusBarHeight: this.statusBarHeight,
      immersiveEnabled: SUPPORTS_IMMERSIVE_MATERIAL && this.immersiveLightEnabled });
  }

  @Builder
  listView() {
    NotifyMessageList({ messages: this.messages, isEditing: this.isEditing, selectedIds: this.selectedIds,
      expandedGroups: this.expandedGroups, groupCardHeights: this.groupCardHeights,
      groupTotals: this.groupTotals, groupLoadingMore: this.groupLoadingMore,
      groupEnabled: this.groupEnabled,
      statusBarHeight: this.statusBarHeight, navBarHeight: this.navBarHeight,
      immersiveLightEnabled: this.immersiveLightEnabled, listScroller: this.scroller,
      onLoadMoreInGroup: (groupKey: string) => this.loadMoreInGroup(groupKey),
      onToggleSelect: (id: number) => this.toggleSelect(id),
      onSetSelected: (id: number, selected: boolean) => this.setSelected(id, selected),
      onToggleGroupSelection: (messages: NotifyMessage[]) => this.toggleGroupSelection(messages),
      onSetGroupSelection: (messages: NotifyMessage[], selected: boolean) => this.setGroupSelection(messages, selected),
      onToggleGroupExpanded: (groupKey: string) => this.toggleGroupExpanded(groupKey),
      onOpenMessage: (message: NotifyMessage) => this.openMessageDetail(message),
      onOpenGroup: (section: NotifySection) => this.handleGroupHeaderClick(section),
      onHeightChange: (groupKey: string, height: number) => this.updateGroupCardHeight(groupKey, height),
      onDeleteOne: (message: NotifyMessage) => this.confirmDeleteOne(message),
      onDeleteGroup: (section: NotifySection) => this.confirmDeleteGroup(section),
      onOpenUrl: (url: string) => this.openUrl(url), onCopyCode: (code: string) => this.copyCode(code),
      onCopyUrl: (url: string) => this.copyUrl(url) });
  }

  /** 打开消息详情，供列表卡片统一回调。 */
  private openMessageDetail(message: NotifyMessage): void {
    this.selectedMessage = message;
    this.showDetail = true;
  }

  // 多选模式底部操作栏（需要加在 Refresh 外面）
  @Builder
  editActionBar() {
    NotifyEditActionBar({ selectedCount: this.selectedIds.length, messageCount: this.messages.length,
      exporting: this.exportingSelected, navBarHeight: this.navBarHeight,
      immersiveLightEnabled: this.immersiveLightEnabled,
      onCancel: () => this.exitEditMode(),
      onToggleAll: () => this.toggleAllSelection(),
      onExport: () => this.handleExportSelected(),
      onDelete: () => this.handleDeleteSelected() });
  }

  /** 切换当前列表的全选状态，供多选底栏回调使用。 */
  private toggleAllSelection(): void {
    if (this.selectedIds.length === this.messages.length) {
      this.selectedIds = [];
      return;
    }
    const ids: number[] = [];
    for (let i = 0; i < this.messages.length; i++) {
      ids.push(this.messages[i].id);
    }
    this.selectedIds = ids;
  }

  /** 处理导出入口，保留空选择和重复点击提示。 */
  private handleExportSelected(): void {
    if (this.exportingSelected) {
      return;
    }
    if (this.selectedIds.length === 0) {
      showToast(this.getUIContext(), '请先选择要导出的通知');
      return;
    }
    this.exportSelectedMessages();
  }

  /** 处理删除入口，保留空选择提示。 */
  private handleDeleteSelected(): void {
    if (this.selectedIds.length === 0) {
      showToast(this.getUIContext(), '请先选择要删除的通知');
      return;
    }
    this.confirmDeleteSelected();
  }

  @Builder
  detailBuilder() {
    NotifyMessageDetail({
      message: this.selectedMessage,
      statusBarHeight: this.statusBarHeight,
      navBarHeight: this.navBarHeight,
      onDismiss: () => { this.showDetail = false; },
      onOpenUrl: (url: string) => { this.openUrl(url); },
      onCopyCode: (code: string) => { this.copyCode(code); },
      onCopyUrl: (url: string) => { this.copyUrl(url); },
      onCopyText: (text: string) => { this.copyText(text); }
    });
  }

  /** aboutToAppear 是同步签名，这里 fire-and-forget 初始化链 */
  private async initAfterServerManagerReady(): Promise<void> {
    try {
      await ServerManager.getInstance().ensureLoaded();
      // 从 ServerManager 同步初始视图模式
      this.viewAll = ServerManager.getInstance().getViewAllMode();
      this.visibleDeviceKeys = this.getAllDeviceKeys().join('|');
      this.refresh();
      const seq: number = ++this.loadSeq;
      if (this.viewAll) {
        // 全部模式：先从本地缓存加载所有服务器的消息
        const deviceKeys: string[] = this.getAllDeviceKeys();
        if (deviceKeys.length > 0) {
          const grouped = await MessageCacheStore.loadAllGroupedLatest(deviceKeys, 100);
          if (grouped.messages.length > 0) {
            this.messages = grouped.messages;
            this.groupTotals = grouped.totals;
          }
        }
        await this.syncAllServers(seq);
      } else {
        const cur: ServerEntry | null = ServerManager.getInstance().getCurrentServer();
        if (cur && cur.deviceKey && cur.deviceKey.length > 0) {
          const grouped = await MessageCacheStore.loadGroupedLatest(cur.deviceKey, 100);
          if (grouped.messages.length > 0) {
            this.messages = grouped.messages;
            this.groupTotals = grouped.totals;
          }
        }
        if (cur) {
          const changed: boolean = await this.syncSingleServer(cur, false, seq);
          if (changed || this.messages.length === 0) {
            const deviceKey: string = cur.deviceKey;
            if (deviceKey && deviceKey.length > 0) {
              const refreshed = await MessageCacheStore.loadGroupedLatest(deviceKey, 100);
              this.messages = refreshed.messages;
              this.groupTotals = refreshed.totals;
            }
          }
        }
      }
      this.hasClientToken = await NotifyMessageService.getInstance().hasEffectiveClientToken();
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, TAG, '初始化失败：%{public}s', msg);
    }
  }

  private openUrl(url: string): void {
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      // 正文识别允许无协议域名和邮箱：前者补 HTTPS，后者交由系统邮件应用处理。
      const isEmail: boolean = /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(url);
      const targetUrl: string = isEmail ? `mailto:${url}` : (url.indexOf('://') >= 0 ? url : `https://${url}`);
      const want: Want = {
        action: 'ohos.want.action.viewData',
        uri: targetUrl,
      };
      ctx.startAbility(want).catch((err: BusinessError) => {
        hilog.warn(DOMAIN, TAG, '打开链接失败：code=%{public}d msg=%{public}s', err.code, err.message);
        showToast(this.getUIContext(), '无法打开链接');
      });
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, TAG, 'openUrl 异常：%{public}s', msg);
      showToast(this.getUIContext(), '无法打开链接');
    }
  }

  // ====== 正文富文本：验证码点击复制到剪贴板 ======
  private async copyCode(code: string): Promise<void> {
    try {
      const data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, code);
      const sys: pasteboard.SystemPasteboard = pasteboard.getSystemPasteboard();
      await sys.setData(data);
      showToast(this.getUIContext(), `已复制 ${code}`, 1500);
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, TAG, '复制验证码失败：%{public}s', msg);
      showToast(this.getUIContext(), '复制失败');
    }
  }

  /** 复制普通通知文字，供详情页中非识别文本及其空白区域点击使用。 */
  private async copyText(text: string): Promise<void> {
    if (text.length === 0) {
      return;
    }
    try {
      const data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      const sys: pasteboard.SystemPasteboard = pasteboard.getSystemPasteboard();
      await sys.setData(data);
      showToast(this.getUIContext(), '内容已复制', 1500);
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, TAG, '复制普通文本失败：%{public}s', msg);
      showToast(this.getUIContext(), '复制失败');
    }
  }

  /** 复制消息 extras.url 到剪贴板，供列表卡片链接 action 使用 */
  private async copyUrl(url: string): Promise<void> {
    try {
      const data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, url);
      const sys: pasteboard.SystemPasteboard = pasteboard.getSystemPasteboard();
      await sys.setData(data);
      showToast(this.getUIContext(), '链接已复制', 1500);
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, TAG, '复制链接失败：%{public}s', msg);
      showToast(this.getUIContext(), '复制失败');
    }
  }

  private needGuideToConfig(): boolean {
    return !this.loading && !this.hasClientToken && this.errorMsg.length > 0;
  }

  // ====== 多选模式控制 ======
  private enterEditMode(): void {
    this.isEditing = true;
    this.selectedIds = [];
  }

  private exitEditMode(): void {
    this.isEditing = false;
    this.selectedIds = [];
  }

  private onHomeTabIndexChanged(): void {
    if (this.isEditing) {
      this.exitEditMode();
    }
    if (this.homeTabIndex === 0) {
      this.loadMessages();
      if (this.indexPageVisible) {
        this.startPolling();
      }
    } else {
      this.stopPolling();
    }
  }

  private onPageVisibleChanged(): void {
    if (this.indexPageVisible) {
      if (this.homeTabIndex === 0) {
        this.startPolling();
      }
    } else {
      this.stopPolling();
    }
  }

  private onRefreshSignalChanged(): void {
    this.loadMessages();
  }


  // 启动轮询：幂等，重复调用不会叠加定时器
  private startPolling(): void {
    if (this.pollingEnabled) {
      return;
    }
    this.pollingEnabled = true;
    this.scheduleNextPoll();
  }

  private stopPolling(): void {
    this.pollingEnabled = false;
    if (this.pollTimer >= 0) {
      clearTimeout(this.pollTimer);
      this.pollTimer = -1;
    }
  }

  private scheduleNextPoll(): void {
    this.pollTimer = setTimeout(() => {
      this.pollTimer = -1;
      this.pollNewMessages().finally(() => {
        if (this.pollingEnabled) {
          this.scheduleNextPoll();
        }
      });
    }, POLL_INTERVAL_MS);
  }

  // 不清空列表/不重置分页；失败静默，等下一轮
  private async pollNewMessages(): Promise<void> {
    if (this.pollInFlight || this.loading || this.needGuideToConfig()) {
      return;
    }
    this.pollInFlight = true;
    try {
      await ServerManager.getInstance().ensureLoaded();
      if (this.viewAll) {
        await this.syncAllServers(-1);
      } else {
        const cur: ServerEntry | null = ServerManager.getInstance().getCurrentServer();
        if (cur) {
          const changed: boolean = await this.syncSingleServer(cur, false, -1);
          // 单服务器模式有变化时从本地重新加载（保持与 syncFromServer 原行为一致）
          if (changed || this.messages.length === 0) {
            const deviceKey: string = cur.deviceKey;
            if (deviceKey && deviceKey.length > 0) {
              const refreshed = await MessageCacheStore.loadGroupedLatest(deviceKey, 100);
              this.messages = refreshed.messages;
              this.groupTotals = refreshed.totals;
            }
          }
        }
      }
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, TAG, '轮询异常：%{public}s', msg);
    } finally {
      this.pollInFlight = false;
    }
  }

  private onIsEditingChanged(): void {
    if (!this.isEditing && this.selectedIds.length > 0) {
      this.selectedIds = [];
    }
  }

  private handleMultiSelectClicked(): void {
    if (this.messages.length === 0) {
      showToast(this.getUIContext(), '暂无可多选的通知');
      return;
    }
    if (this.isEditing) {
      if (this.selectedIds.length === this.messages.length) {
        this.selectedIds = [];
      } else if (this.selectedIds.length > 0) {
        this.selectedIds = [];
      } else {
        this.exitEditMode();
      }
    } else {
      this.enterEditMode();
    }
  }

  private handleDeletePillClicked(): void {
    if (this.isEditing) {
      if (this.selectedIds.length > 0) {
        this.confirmDeleteSelected();
      } else {
        showToast(this.getUIContext(), '请先选择要删除的通知');
      }
    } else {
      this.confirmDeleteAll();
    }
  }

  private isSelected(id: number): boolean {
    return hasSelectedMessage(this.selectedIds, id);
  }

  private toggleSelect(id: number): void {
    this.selectedIds = toggleSelectedMessage(this.selectedIds, id);
  }

  /** Checkbox 的 onChange 可能由状态回显触发，仅在目标状态不同的时候写入。 */
  private setSelected(id: number, selected: boolean): void {
    const next: number[] = setSelectedMessage(this.selectedIds, id, selected);
    if (next !== this.selectedIds) {
      this.selectedIds = next;
    }
  }

  // ====== group 分组展示 ======

  private isGroupExpanded(groupKey: string): boolean {
    return NotifyGroupStateUtils.isExpanded(this.expandedGroups, groupKey);
  }

  private updateGroupCardHeight(groupKey: string, heightVp: number): void {
    if (heightVp <= 0) {
      return;
    }
    this.groupCardHeights = NotifyGroupStateUtils.updateCardHeight(this.groupCardHeights, groupKey, heightVp);
  }

  private setGroupExpanded(groupKey: string, expanded: boolean): void {
    if (this.isGroupExpanded(groupKey) === expanded) {
      return;
    }
    this.expandedGroups = NotifyGroupStateUtils.toggleExpanded(this.expandedGroups, groupKey);
    this.updateSavedExpandedGroups(groupKey, expanded);
  }

  private toggleGroupExpanded(groupKey: string): void {
    const nextExpanded: boolean = !this.isGroupExpanded(groupKey);
    this.getUIContext().animateTo({ duration: 280, curve: Curve.EaseInOut }, () => {
      this.setGroupExpanded(groupKey, nextExpanded);
    });
  }

  // ====== 分组/平铺模式切换（右下角浮动按钮） ======

  /**
   * 切换分组显示模式并持久化。
   * 切到平铺时清空展开状态（平铺没有分组可展开）；
   * 切回分组时也清空，让用户重新选择展开哪些组。
   */
  private toggleGroupEnabled(): void {
    this.groupEnabled = !this.groupEnabled;
    this.expandedGroups = [];
    PreferencesUtil.putString(null, PreferencesUtil.KEY_GROUP_ENABLED,
      this.groupEnabled ? 'true' : 'false');
    // 平铺模式不展示展开态；重新开启分组时投影已保存的全局展开记录。
    if (this.groupEnabled) {
      this.restoreVisibleExpandedGroups();
    }
  }

  /** 从 Preferences 恢复全局展开记录；异常或旧格式均安全降级为空数组。 */
  private async loadExpandedGroups(): Promise<void> {
    const raw: string = await PreferencesUtil.getString(null, PreferencesUtil.KEY_NOTIFY_EXPANDED_GROUPS, '[]');
    const groups: string[] = [];
    try {
      const parsed: Object = JSON.parse(raw);
      if (parsed instanceof Array) {
        for (let i = 0; i < parsed.length; i++) {
          if (typeof parsed[i] === 'string' && groups.indexOf(String(parsed[i])) < 0) {
            groups.push(String(parsed[i]));
          }
        }
      }
    } catch (_err) {
      // 保留空数组，下一次用户展开/收起会用正确格式覆盖损坏的旧值。
    }
    this.savedExpandedGroups = groups;
    this.expandedGroupsLoaded = true;
    this.restoreVisibleExpandedGroups();
  }

  /** 将持久化记录投影为当前消息列表中真实存在的分组，避免不存在的分组影响渲染。 */
  private restoreVisibleExpandedGroups(): void {
    if (!this.expandedGroupsLoaded || !this.groupEnabled || this.messages.length === 0) {
      return;
    }
    const visibleGroups: string[] = [];
    for (let i = 0; i < this.messages.length; i++) {
      const groupKey: string = this.messages[i].group;
      if (this.savedExpandedGroups.indexOf(groupKey) >= 0 && visibleGroups.indexOf(groupKey) < 0) {
        visibleGroups.push(groupKey);
      }
    }
    this.expandedGroups = visibleGroups;
  }

  /** 仅用户主动展开/收起时更新全局记录，切换服务器和删除消息不会误清理同名分组状态。 */
  private updateSavedExpandedGroups(groupKey: string, expanded: boolean): void {
    const next: string[] = expanded
      ? (this.savedExpandedGroups.indexOf(groupKey) >= 0 ? this.savedExpandedGroups : [...this.savedExpandedGroups, groupKey])
      : this.savedExpandedGroups.filter((key: string) => key !== groupKey);
    this.savedExpandedGroups = next;
    PreferencesUtil.putString(null, PreferencesUtil.KEY_NOTIFY_EXPANDED_GROUPS, JSON.stringify(next));
  }

  private handleGroupHeaderClick(section: NotifySection): void {
    if (this.isEditing) {
      this.toggleGroupSelection(section.messages);
      return;
    }
    if (this.isGroupExpanded(section.groupKey)) {
      this.selectedMessage = section.messages[0];
      this.showDetail = true;
    } else {
      this.toggleGroupExpanded(section.groupKey);
    }
  }

  private isGroupAllSelected(groupMessages: NotifyMessage[]): boolean {
    return areGroupMessagesSelected(this.selectedIds, groupMessages);
  }

  private toggleGroupSelection(groupMessages: NotifyMessage[]): void {
    this.selectedIds = toggleGroupMessages(this.selectedIds, groupMessages);
  }

  private setGroupSelection(groupMessages: NotifyMessage[], selected: boolean): void {
    const next: number[] = setGroupMessagesSelection(this.selectedIds, groupMessages, selected);
    if (next !== this.selectedIds) {
      this.selectedIds = next;
    }
  }

  private removeFromList(ids: number[]): void {
    const idSet: Set<number> = new Set<number>(ids);
    const newList: NotifyMessage[] = [];
    for (let i = 0; i < this.messages.length; i++) {
      if (!idSet.has(this.messages[i].id)) {
        newList.push(this.messages[i]);
      }
    }
    // 可观察分组会只删除目标子项；动画上下文同步平滑收起该行占用的布局空间。
    this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseOut }, () => {
      this.messages = newList;
      this.expandedGroups = retainExpandableGroups(this.messages, this.expandedGroups);
      // 如果删光了，退出编辑模式
      if (this.messages.length === 0) {
        this.exitEditMode();
      }
    });
  }

  /** 从当前内存列表移除整个分组，数据库删除会覆盖该组尚未加载的历史通知。 */
  private removeGroupFromList(groupKey: string): void {
    const remaining: NotifyMessage[] = this.messages.filter((message: NotifyMessage) => message.group !== groupKey);
    this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseOut }, () => {
      this.messages = remaining;
      this.expandedGroups = retainExpandableGroups(this.messages, this.expandedGroups);
      if (this.messages.length === 0) {
        this.exitEditMode();
      }
    });
  }

  // ====== 删除确认与执行 ======
  private confirmDeleteOne(m: NotifyMessage): void {
    const uiCtx: UIContext = this.getUIContext();
    uiCtx.getPromptAction().showDialog({
      title: '从本机删除通知',
      message: `此通知已从服务器迁移到本机。删除后无法恢复。${m.title && m.title.length > 0 ?
        '\n\n「' + m.title + '」' : ''}`,
      buttons: [
        { text: '取消', color: $r('app.color.color_text_tertiary') },
        { text: '删除', color: $r('app.color.color_error') },
      ],
    }, async (err: BusinessError, result: promptAction.ShowDialogSuccessResponse) => {
      if (err || result.index !== 1) {
        return;
      }
      // 远程记录已在同步落库后清理；用户操作只删除本地副本。
      if (m.deviceKey && m.deviceKey.length > 0) {
        const pair: DeviceIdPair = { deviceKey: m.deviceKey, id: m.id };
        await MessageCacheStore.deleteByDeviceIdPairs([pair]);
        this.groupTotals = this.viewAll
          ? await MessageCacheStore.getAllGroupTotals(this.getAllDeviceKeys())
          : await MessageCacheStore.getGroupTotals(m.deviceKey);
      }
      this.removeFromList([m.id]);
      this.exitEditMode();
      showToast(uiCtx, '已删除');
    });
  }

  private confirmDeleteGroup(section: NotifySection): void {
    const uiCtx: UIContext = this.getUIContext();
    const count: number = section.total;
    uiCtx.getPromptAction().showDialog({
      title: '从本机删除整个分组',
      message: `将删除该分组的全部 ${count} 条本地通知，包括尚未加载的历史通知。删除后无法恢复。`,
      buttons: [
        { text: '取消', color: $r('app.color.color_text_tertiary') },
        { text: '全部删除', color: $r('app.color.color_error') },
      ],
    }, async (err: BusinessError, result: promptAction.ShowDialogSuccessResponse) => {
      if (err || result.index !== 1) {
        return;
      }
      showToast(uiCtx, `正在删除 ${count} 条本地通知…`);
      const deviceKeys: string[] = this.viewAll ? this.getAllDeviceKeys() : [this.findCurrentDeviceKey()];
      const deleted: number = await MessageCacheStore.deleteGroup(deviceKeys, section.groupKey);
      if (deleted < 0) {
        showToast(uiCtx, '删除失败，请稍后重试');
        return;
      }
      this.removeGroupFromList(section.groupKey);
      // 刷新分组总数
      this.groupTotals = this.viewAll
        ? await MessageCacheStore.getAllGroupTotals(this.getAllDeviceKeys())
        : await MessageCacheStore.getGroupTotals(this.findCurrentDeviceKey());
      showToast(uiCtx, `已从本机删除 ${deleted} 条`);
    });
  }

  /** 获取当前服务器 deviceKey（单服务器模式刷新分组总数用） */
  private findCurrentDeviceKey(): string {
    const cur: ServerEntry | null = ServerManager.getInstance().getCurrentServer();
    return cur ? cur.deviceKey : '';
  }

  private confirmDeleteSelected(): void {
    const uiCtx: UIContext = this.getUIContext();
    const count: number = this.selectedIds.length;
    uiCtx.getPromptAction().showDialog({
      title: '从本机删除通知',
      message: `将删除选中的 ${count} 条本地通知。删除后无法恢复。`,
      buttons: [
        { text: '取消', color: $r('app.color.color_text_tertiary') },
        { text: '全部删除', color: $r('app.color.color_error') },
      ],
    }, async (err: BusinessError, result: promptAction.ShowDialogSuccessResponse) => {
      if (err || result.index !== 1) {
        return;
      }
      const ids: number[] = [...this.selectedIds];
      // 按 (deviceKey, id) 精确删除，避免跨服务器同 id 误删
      const pairs: DeviceIdPair[] = [];
      for (let i = 0; i < this.messages.length; i++) {
        const m: NotifyMessage = this.messages[i];
        if (ids.indexOf(m.id) < 0) {
          continue;
        }
        if (m.deviceKey && m.deviceKey.length > 0) {
          pairs.push({ deviceKey: m.deviceKey, id: m.id });
        }
      }
      if (pairs.length > 0) {
        await MessageCacheStore.deleteByDeviceIdPairs(pairs);
      }
      this.groupTotals = this.viewAll
        ? await MessageCacheStore.getAllGroupTotals(this.getAllDeviceKeys())
        : await MessageCacheStore.getGroupTotals(this.findCurrentDeviceKey());
      this.removeFromList(ids);
      this.exitEditMode();
      showToast(uiCtx, `已从本机删除 ${pairs.length} 条`);
    });
  }

  private confirmDeleteAll(): void {
    const uiCtx: UIContext = this.getUIContext();
    // 本地无消息时无需调用清空接口
    if (this.messages.length === 0) {
      showToast(uiCtx, '暂无可删除的通知');
      return;
    }
    uiCtx.getPromptAction().showDialog({
      title: '清空全部通知',
      message: this.viewAll
        ? '将删除本机保存的所有服务器通知，包括未加载的历史通知。服务器副本已在同步后清理，删除后无法恢复。'
        : '将删除本机保存的当前服务器全部通知，包括未加载的历史通知。服务器副本已在同步后清理，删除后无法恢复。',
      buttons: [
        { text: '取消', color: $r('app.color.color_text_tertiary') },
        { text: '全部删除', color: $r('app.color.color_error') },
      ],
    }, async (err: BusinessError, result: promptAction.ShowDialogSuccessResponse) => {
      if (err || result.index !== 1) {
        return;
      }
      if (this.viewAll) {
        await MessageCacheStore.clearAllDevices();
        showToast(uiCtx, '已清空本机全部通知');
      } else {
        const deviceKey: string = this.findCurrentDeviceKey();
        if (deviceKey && deviceKey.length > 0) {
          await MessageCacheStore.clearDevice(deviceKey);
        }
        showToast(uiCtx, '已清空本机全部通知');
      }
      this.exitEditMode();
      this.messages = [];
      this.expandedGroups = [];
      this.groupCardHeights = new Map<string, number>();
      this.groupTotals = new Map<string, number>();
      this.groupLoadingMore = new Set<string>();
    });
  }

  private refresh(): void {
    if (this.viewAll) {
      this.title = '全部通知';
      return;
    }
    const cur: ServerEntry | null = ServerManager.getInstance().getCurrentServer();
    if (cur && cur.name && cur.name.length > 0) {
      this.title = cur.name;
    } else {
      this.title = ServerManager.getInstance().getCurrentHostDisplay();
    }
  }

  /** 获取所有已注册（有 deviceKey）的服务器列表，用于"全部"视图模式同步与查询 */
  private getAllRegisteredServers(): ServerEntry[] {
    const list: ServerEntry[] = ServerManager.getInstance().getList();
    const result: ServerEntry[] = [];
    for (let i = 0; i < list.length; i++) {
      if (list[i].deviceKey && list[i].deviceKey.length > 0) {
        result.push(list[i]);
      }
    }
    return result;
  }

  /** 获取所有已注册服务器的 deviceKey 列表 */
  private getAllDeviceKeys(): string[] {
    const servers: ServerEntry[] = this.getAllRegisteredServers();
    const keys: string[] = [];
    for (let i = 0; i < servers.length; i++) {
      keys.push(servers[i].deviceKey);
    }
    return keys;
  }

  /**
   * 切换视图模式（全部 / 单服务器）。
   * 通过 ServerManager 统一管理，onChange 回调会处理列表刷新。
   */
  setViewAll(viewAll: boolean): void {
    ServerManager.getInstance().setViewAllMode(viewAll);
  }

  private async loadMessages(): Promise<void> {
    if (this.loading) {
      this.refreshing = false;
      this.loadQueued = true;
      return;
    }
    this.loading = true;
    const seq: number = ++this.loadSeq;
    // 清空旧错误，避免短暂闪烁旧错误态
    this.errorMsg = '';
    try {
      await ServerManager.getInstance().ensureLoaded();
      // 每次进入或刷新列表前清理 ttl 已到期的本地历史；清空内存以强制从缓存回填。
      const expiredDeleted: number = await MessageCacheStore.purgeExpired();
      if (expiredDeleted > 0) {
        this.messages = [];
        this.groupTotals = new Map<string, number>();
      }
      if (this.viewAll) {
        // 全部模式：并行同步所有已注册服务器
        await this.syncAllServers(seq);
      } else {
        // 单服务器模式：只同步当前服务器
        const cur: ServerEntry | null = ServerManager.getInstance().getCurrentServer();
        if (cur) {
          const changed: boolean = await this.syncSingleServer(cur, false, seq);
          // 同步完成后从缓存回填列表（onChange 已清空 this.messages，必须回填）
          if (changed || this.messages.length === 0) {
            const deviceKey: string = cur.deviceKey;
            if (deviceKey && deviceKey.length > 0) {
              const refreshed = await MessageCacheStore.loadGroupedLatest(deviceKey, 100);
              this.messages = refreshed.messages;
              this.groupTotals = refreshed.totals;
            }
          }
        }
      }
      this.hasClientToken = await NotifyMessageService.getInstance().hasEffectiveClientToken();
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, TAG, 'loadMessages 异常：%{public}s', msg);
      if (seq === this.loadSeq) {
        this.errorMsg = '加载失败';
      }
    } finally {
      this.loading = false;
      this.refreshing = false;
      if (this.loadQueued) {
        this.loadQueued = false;
        this.loadMessages(); // 补拉：消费排队期间产生的最新拉取需求
      }
    }
  }

  /**
   * 同步单个服务器的远程暂存消息。
   * 每页先解密并完整写入本地，再删除远程副本；删除失败项会在下一轮幂等重试。
   */
  private async syncSingleServer(server: ServerEntry, forceFull: boolean,
    expectedSeq: number = -1): Promise<boolean> {
    const svc = NotifyMessageService.getInstance();
    const deviceKey: string = server.deviceKey;
    if (!deviceKey || deviceKey.length === 0) {
      return false;
    }

    // 代际校验
    if (expectedSeq >= 0 && expectedSeq !== this.loadSeq) {
      return false;
    }

    // 远程历史是待迁移队列。每轮必须从 0 检查，才能重试上次已落库但远程删除失败的消息。
    let after: number = 0;
    let newMaxId: number = 0;
    if (forceFull) {
      await MessageCacheStore.clearDevice(deviceKey);
    } else {
      const meta = await MessageCacheStore.getMeta(deviceKey);
      newMaxId = meta.maxId;
    }

    let hasNewMessages: boolean = false;

    while (true) {
      if (expectedSeq >= 0 && expectedSeq !== this.loadSeq) {
        return false;
      }
      const result = await svc.getMessages(null, 0, SYNC_PAGE_SIZE, after, 0, server, true);
      if (!result.ok) {
        hilog.warn(DOMAIN, TAG, 'syncSingleServer 失败（%{public}s）：%{public}s', deviceKey, result.errorMsg);
        // 本地无消息时透出错误，有消息时静默保留
        if (this.messages.length === 0 && expectedSeq >= 0) {
          this.errorMsg = result.errorMsg;
        }
        return false;
      }

      let nextAfter: number = after;
      if (result.messages.length > 0) {
        // 解密已在 getMessages 中完成；明文、ciphertext 和 IV 必须一起成功落库后才能删远程。
        const written: boolean = await MessageCacheStore.upsertMessages(deviceKey, result.messages);
        if (!written) {
          hilog.warn(DOMAIN, TAG, 'syncSingleServer 本地写入失败，保留历史游标：%{public}s', deviceKey);
          return false;
        }
        // 非归档加密消息不会显示在 App 列表；先逐条发布解密后的本地通知，成功后才允许删除远端密文。
        for (let i: number = 0; i < result.messages.length; i++) {
          const message: NotifyMessage = result.messages[i];
          if (message.needsDecryptedNotification()) {
            const published: boolean = await DecryptedNotificationService.publish(message, server);
            if (!published) {
              message.migrationReady = false;
            }
          }
        }
        hasNewMessages = true;
        for (let i = 0; i < result.messages.length; i++) {
          if (result.messages[i].id > newMaxId) {
            newMaxId = result.messages[i].id;
          }
          if (result.messages[i].id > nextAfter) {
            nextAfter = result.messages[i].id;
          }
        }
        await this.deleteMigratedRemoteMessages(server, result.messages);
      }

      // 服务端有下一页却没有推进 id，会导致无限请求；保持未完成状态并下次重试。
      if (result.hasMore && nextAfter <= after) {
        hilog.warn(DOMAIN, TAG, 'syncSingleServer 分页游标未推进：%{public}s', deviceKey);
        return false;
      }

      // maxId 仅用于本地统计；远程扫描起点固定为 0，不以它跳过删除失败项。
      const metaSaved: boolean = await MessageCacheStore.saveMeta(
        deviceKey, newMaxId, 0, 0, true);
      if (!metaSaved) {
        hilog.warn(DOMAIN, TAG, 'syncSingleServer 同步进度保存失败：%{public}s', deviceKey);
        return false;
      }

      if (!result.hasMore) {
        break;
      }
      after = nextAfter;
    }

    if (expectedSeq >= 0 && expectedSeq !== this.loadSeq) {
      return false;
    }

    this.errorMsg = '';
    return hasNewMessages;
  }

  /** 本地落库完成后并行清理远程副本；失败记录留在服务器供下一轮同步重试。 */
  private async deleteMigratedRemoteMessages(server: ServerEntry, messages: NotifyMessage[]): Promise<void> {
    const svc = NotifyMessageService.getInstance();
    const readyMessages: NotifyMessage[] = messages.filter((message: NotifyMessage) => message.migrationReady);
    let failed: number = 0;
    for (let offset: number = 0; offset < readyMessages.length; offset += REMOTE_DELETE_CONCURRENCY) {
      const tasks: Promise<string>[] = [];
      const end: number = Math.min(offset + REMOTE_DELETE_CONCURRENCY, readyMessages.length);
      for (let i: number = offset; i < end; i++) {
        tasks.push(svc.deleteMessage(readyMessages[i].id, null, server));
      }
      const results: string[] = await Promise.all(tasks);
      for (let i: number = 0; i < results.length; i++) {
        if (results[i].length > 0) {
          failed++;
        }
      }
    }
    if (failed > 0) {
      hilog.warn(DOMAIN, TAG, '远程迁移清理失败：server=%{public}s failed=%{public}d total=%{public}d',
        server.name, failed, readyMessages.length);
    }
  }

  /**
   * "全部"视图模式：并行同步所有已注册服务器。
   * 任一服务器有数据变化时，从本地缓存重新加载全部消息（跨服务器分组聚合）。
   */
  private async syncAllServers(expectedSeq: number): Promise<void> {
    const servers: ServerEntry[] = this.getAllRegisteredServers();
    if (servers.length === 0) {
      this.messages = [];
      this.groupTotals = new Map<string, number>();
      return;
    }

    // 并行同步所有服务器
    const tasks: Promise<boolean>[] = [];
    for (let i = 0; i < servers.length; i++) {
      tasks.push(this.syncSingleServer(servers[i], false, expectedSeq));
    }
    const results: boolean[] = await Promise.all(tasks);

    // 代际失效：若列表已被清空（onChange 清空），需从缓存兜底回填，避免显示"暂无消息"
    if (expectedSeq >= 0 && expectedSeq !== this.loadSeq) {
      if (this.messages.length === 0) {
        const deviceKeys: string[] = this.getAllDeviceKeys();
        const refreshed = await MessageCacheStore.loadAllGroupedLatest(deviceKeys, 100);
        this.messages = refreshed.messages;
        this.groupTotals = refreshed.totals;
      }
      return;
    }

    let anyChanged: boolean = false;
    for (let i = 0; i < results.length; i++) {
      if (results[i]) {
        anyChanged = true;
        break;
      }
    }

    // 无变化且内存非空：不刷新，避免轮询空转闪烁
    if (!anyChanged && this.messages.length > 0) {
      return;
    }

    // 有变化或内存为空：从本地缓存重新加载所有服务器的消息
    const deviceKeys: string[] = this.getAllDeviceKeys();
    const refreshed = await MessageCacheStore.loadAllGroupedLatest(deviceKeys, 100);
    this.messages = refreshed.messages;
    this.groupTotals = refreshed.totals;
  }

  /**
   * 组内"加载更多"：加载某 group_key 下比当前内存中最老 id 更老的 100 条。
   * 数据源为本地 DB（首次播种已拉取足够消息，组内分页只读本地）。
   * append 到 this.messages 末尾，buildNotifySections 会自动聚合到已有 section。
   */
  private async loadMoreInGroup(groupKey: string): Promise<void> {
    if (this.groupLoadingMore.has(groupKey)) {
      return;
    }
    // 找到该 group 在内存中的最老消息 id（id 最小）
    let oldestId: number = Number.MAX_SAFE_INTEGER;
    for (let i = 0; i < this.messages.length; i++) {
      if (this.messages[i].group === groupKey && this.messages[i].id < oldestId) {
        oldestId = this.messages[i].id;
      }
    }
    if (oldestId === Number.MAX_SAFE_INTEGER) {
      return;
    }
    this.groupLoadingMore = new Set<string>(this.groupLoadingMore).add(groupKey);
    try {
      const PAGE_SIZE: number = 100;
      let older: NotifyMessage[] = [];
      if (this.viewAll) {
        // 全部模式：跨所有服务器加载该 group 的更老消息
        const deviceKeys: string[] = this.getAllDeviceKeys();
        older = await MessageCacheStore.loadAllGroupOlder(deviceKeys, groupKey, oldestId, PAGE_SIZE);
      } else {
        const deviceKey: string = await ServerManager.getInstance().getCurrentDeviceKey(null);
        if (!deviceKey || deviceKey.length === 0) {
          return;
        }
        older = await MessageCacheStore.loadGroupOlder(deviceKey, groupKey, oldestId, PAGE_SIZE);
      }
      if (older.length > 0) {
        // 去重后 append
        const existingIds: Set<number> = new Set<number>();
        for (let i = 0; i < this.messages.length; i++) {
          existingIds.add(this.messages[i].id);
        }
        const deduped: NotifyMessage[] = [];
        for (let i = 0; i < older.length; i++) {
          if (!existingIds.has(older[i].id)) {
            deduped.push(older[i]);
            existingIds.add(older[i].id);
          }
        }
        if (deduped.length > 0) {
          this.messages = this.messages.concat(deduped);
        }
      }
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, TAG, 'loadMoreInGroup 异常：%{public}s', msg);
    } finally {
      const next = new Set<string>(this.groupLoadingMore);
      next.delete(groupKey);
      this.groupLoadingMore = next;
    }
  }

  private handleMoreClicked(): void {
    try {
      this.dialogController.open();
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, TAG, 'dialog open 失败：%{public}s', msg);
      showToast(this.getUIContext(), '弹窗无法打开');
    }
  }

  // 获取 UIAbilityContext（DocumentViewPicker 需要）
  private getAbilityContext(): common.UIAbilityContext | null {
    try {
      const ctx = this.getUIContext().getHostContext();
      return ctx as common.UIAbilityContext;
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, TAG, 'getHostContext 失败：%{public}s', msg);
      return null;
    }
  }

  /** 导出选中消息：文件写入与序列化由 NotifyExportService 处理。 */
  private async exportSelectedMessages(): Promise<void> {
    if (this.exportingSelected || this.selectedIds.length === 0) {
      return;
    }
    const uiContext: UIContext = this.getUIContext();
    this.exportingSelected = true;
    try {
      const abilityContext = this.getAbilityContext();
      if (!abilityContext) {
        showToast(uiContext, '上下文获取失败');
        return;
      }
      const count: number = await NotifyExportService.exportSelected(abilityContext, this.messages, this.selectedIds);
      if (count < 0) {
        showToast(uiContext, '设备未注册，无法导出');
      } else if (count > 0) {
        showToast(uiContext, `已导出 ${count} 条通知`, 1500);
      }
    } catch (err) {
      const message: string = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, TAG, '导出选中消息失败：%{public}s', message);
      showToast(uiContext, '导出失败');
    } finally {
      this.exportingSelected = false;
    }
  }
}
