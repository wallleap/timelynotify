import { hilog } from '@kit.PerformanceAnalysisKit';
import { promptAction, UIContext } from '@kit.ArkUI';
import { BusinessError, pasteboard } from '@kit.BasicServicesKit';
import { common, Want } from '@kit.AbilityKit';
import { ServerEntry } from '../model/ServerEntry';
import { ServerManager } from '../services/ServerManager';
import { NotifyMessage } from '../model/NotifyMessage';
import { NotifyMessageService } from '../services/NotifyMessageService';
import { MessageCacheStore } from '../services/MessageCacheStore';
import { DeviceIdPair } from '../services/MessageCacheStore';
import { PreferencesUtil } from '../utils/PreferencesUtil';
import { ServerSwitchDialog } from '../components/notify/ServerSwitchDialog';
import { ServerKeyDialog, ServerActionMenuDialog } from '../components/ServerActionDialogs';
import { ClientTokenDialog } from '../components/ClientTokenDialog';
import { DeviceRegisterService } from '../services/DeviceRegisterService';
import {
  getDialogBackgroundOptions,
  getDialogMaterial,
  getSystemMaterial,
  KEY_IMMERSIVE_LIGHT_ENABLED,
  KEY_MATERIAL_LOADED,
  SUPPORTS_IMMERSIVE_MATERIAL,
  resolveBlurStyle
} from '../utils/ImmersiveUtil';
import { hdsMaterial, HdsNavigation, HdsNavigationTitleMode, IconStyleMode, ScrollEffectType, TextStyleMode } from '@kit.UIDesignKit';
import {
  DOMAIN,
  KEY_HOME_TAB_INDEX,
  KEY_INDEX_PAGE_VISIBLE,
  KEY_NOTIFY_EDITING,
  KEY_NOTIFY_OPEN_REQUEST,
  KEY_NOTIFY_REFRESH_SIGNAL,
  KEY_NOTIFY_SYNC_FEEDBACK,
  KEY_NOTIFY_SYNC_PROGRESS,
  KEY_NOTIFY_SYNC_REVISION
} from '../common/Constant';
import { NotifySyncService } from '../services/NotifySyncService';
import showToast from '../components/showToast';
import { NotifySection } from '../components/notify/NotifyViewTypes';
import {
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
import { belongsToPushInstance, compareNotifyOrder, notifyIdentity } from '../utils/NotifyIdentity';

const TAG: string = 'NotifyView';

// 失败服务器及其错误信息（用于点击 banner 精准弹修复弹窗）
interface ServerErrorInfo {
  server: ServerEntry;
  error: string;
}

// 收缩错误胶囊与标题栏之间保留的呼吸间距。
const COMPACT_BANNER_TOP_GAP: number = 8;


// 通知页 - 展示接收到的 HTTP 推送消息列表
@Component
export struct NotifyView {
  @State title: string = '';
  @State @Watch('restoreVisibleExpandedGroups') messages: NotifyMessage[] = [];
  @State loading: boolean = false;
  @StorageProp(KEY_NOTIFY_SYNC_PROGRESS) syncProgressText: string = '';
  @StorageProp(KEY_NOTIFY_SYNC_FEEDBACK) syncFeedbackText: string = '';
  @StorageProp(KEY_NOTIFY_SYNC_REVISION) @Watch('onSyncRevisionChanged') syncRevision: number = 0;
  @State errorMsg: string = '';
  // 单服务或全部模式下 per-server 同步错误的非阻塞提示（列出失败的 server 及原因）
  @State @Watch('onServerErrorBannerChanged') serverErrorBanner: string = '';
  // 列表离开顶部后将完整错误提示收缩为可点击的小胶囊。
  @State serverErrorBannerCollapsed: boolean = false;
  // 固定 Banner 的实测高度，用于给下方列表预留等高安全区域。
  @State serverErrorBannerHeight: number = 0;
  @State refreshing: boolean = false;
  @State hasClientToken: boolean = false;
  // 点击查看的消息详情（底部半模态面板）
  @State showDetail: boolean = false;
  @State selectedMessage: NotifyMessage | null = null;
  @StorageLink(KEY_NOTIFY_EDITING) @Watch('onIsEditingChanged') isEditing: boolean = false;
  @State selectedIds: string[] = [];
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
  @StorageProp(KEY_MATERIAL_LOADED) immersiveMaterialLoaded: boolean = false;
  // 切回「通知」Tab（值为 0）时自动刷新列表
  @StorageProp(KEY_HOME_TAB_INDEX) @Watch('onHomeTabIndexChanged') homeTabIndex: number = 0;
  @StorageProp(KEY_NOTIFY_REFRESH_SIGNAL) @Watch('onRefreshSignalChanged') refreshSignal: number = 0;
  @StorageProp(KEY_NOTIFY_OPEN_REQUEST) @Watch('onOpenRequestChanged') openRequest: string = '';
  @StorageProp(KEY_INDEX_PAGE_VISIBLE) @Watch('onPageVisibleChanged') indexPageVisible: boolean = true;
  @State refreshState: RefreshStatus = RefreshStatus.Inactive;
  // 自绘标题栏底边与列表起点均使用窗口坐标；两者之差即实际遮挡距离。
  @State fallbackTitleBarBottom: number = -1;
  @State listTop: number = -1;
  // 「跳到底部」浮动按钮显隐：上滑离开首屏时显示，下滑或在首屏时隐藏。
  @State showScrollToBottom: boolean = false;
  // 「跳到底部」触发信号：每次自增传给列表，列表 Watch 后执行两段式定位滚动。
  @State scrollToBottomSignal: number = 0;
  // 「切换通知服务」弹窗：点击时（材质必已就绪）才构造，以便 systemMaterial 读取到最新就绪态
  private dialogController: CustomDialogController | null = null;
  private onChange: ((list: ServerEntry[], curId: string) => void) | null = null;
  private loadSeq: number = 0;
  private loadQueued: boolean = false;
  // 防止前后台刷新和点击信号同时到达时重复同步、重复打开详情。
  private openingPushNotice: boolean = false;
  private scroller: Scroller = new Scroller();
  // 详情 Sheet 内部 List 的滚动控制器，与 Sheet 内 HdsNavigation.bindToScrollable 共享以驱动标题栏动态模糊。
  private detailScroller: Scroller = new Scroller();
  // 「跳到底部」程序滚动进行中：屏蔽 handleListScroll 的方向判断，避免动画期间 onDidScroll 让按钮重现。
  private isAutoScrolling: boolean = false;
  // 当前列表对应的 device_key 快照；key 切换时需清空内存中的旧设备消息，即使处于“全部”模式。
  private visibleDeviceKeys: string = '';
  // 持久化的全局展开记录；仅在切换展开/收起时变更，避免切换服务器时误删不可见分组。
  private savedExpandedGroups: string[] = [];
  // Preferences 异步读取完成前不恢复，避免把默认空数组误写回磁盘。
  private expandedGroupsLoaded: boolean = false;
  // 页级刷新合并：多个服务器同时提交时避免并行查询造成旧快照覆盖新快照。
  private pageRefreshInFlight: boolean = false;
  private pageRefreshPending: boolean = false;
  // 应用级同步服务保存错误，页面只负责按当前视图展示。
  private syncErrors: Map<string, string> = new Map<string, string>();
  // 失败服务器修复弹窗 controller（必须由成员持有，局部变量会被回收导致 close 失效）
  private fixClientTokenController: CustomDialogController | null = null;
  private fixKeyController: CustomDialogController | null = null;
  private fixActionMenuController: CustomDialogController | null = null;

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
      // 从 ServerManager 同步视图模式（ServerSwitchDialog 切换全部/单服务器时触发）
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
  }

  aboutToDisappear() {
    if (this.onChange) {
      ServerManager.getInstance().removeChangeListener(this.onChange);
    }
    this.loadSeq++;
  }

  @Builder
  fallbackTitleBar() {
    NotifyTitleBar({ title: this.title, isEditing: this.isEditing, statusBarHeight: this.statusBarHeight,
      onOpenSettings: () => this.handleMoreClicked(), onToggleSelection: () => this.handleMultiSelectClicked(),
      onDelete: () => this.handleDeletePillClicked() })
      .onAreaChange((_old: Area, area: Area) => {
        const bottom: number = (area.globalPosition.y as number) + (area.height as number);
        if (bottom >= 0 && bottom !== this.fallbackTitleBarBottom) {
          this.fallbackTitleBarBottom = bottom;
        }
      });
  }

  @Builder
  customTitleContent() {
    NotifyTitleBar({ title: this.title, isEditing: this.isEditing, useHdsLayout: true,
      onOpenSettings: () => this.handleMoreClicked() });
  }

  // 单服务或全部模式下 per-server 错误的非阻塞提示条（点击打开对应修复入口）
  @Builder
  serverErrorBannerView() {
    Row() {
      Text(this.serverErrorBannerCollapsed ? '服务异常 · 点击修复' : this.serverErrorBanner)
        .fontSize(12)
        .fontColor($r('app.color.color_warning'))
        .maxLines(this.serverErrorBannerCollapsed ? 1 : 2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(this.serverErrorBannerCollapsed ? 0 : 1)
    }
    // 收缩态按内容宽度布局，最长不超过父容器，避免长状态文案溢出屏幕。
    .width(this.serverErrorBannerCollapsed ? 'auto' : '100%')
    .constraintSize({ maxWidth: '100%' })
    .padding(this.serverErrorBannerCollapsed
      ? { left: 12, right: 12, top: 7, bottom: 7 }
      : { left: 16, right: 16, top: 6, bottom: 6 })
    .backgroundColor($r('app.color.color_bg_warning'))
    .borderRadius(this.serverErrorBannerCollapsed ? 20 : 0)
    // 降级布局的标题栏以 Stack 覆盖正文；Banner 使用标题栏实际底边避让，沉浸布局保持原位。
    .margin({
      left: this.serverErrorBannerCollapsed ? 16 : 0,
      top: SUPPORTS_IMMERSIVE_MATERIAL && this.immersiveLightEnabled
        ? 0 : Math.max(0, this.fallbackTitleBarBottom) +
          (this.serverErrorBannerCollapsed ? COMPACT_BANNER_TOP_GAP : 0)
    })
    .onAreaChange((_old: Area, area: Area) => {
      const height: number = area.height as number;
      if (height > 0 && height !== this.serverErrorBannerHeight) {
        this.serverErrorBannerHeight = height;
      }
    })
    .onClick(() => {
      this.openFixDialogForFirstError();
    })
  }

  /**
   * 生成可操作的服务器同步失败文案。提示条本身可点击，此处显式说明后续动作，
   * 避免用户误以为缓存列表仍在展示时错误状态已经恢复。
   */
  private buildServerErrorBannerMessage(server: ServerEntry, error: string): string {
    const name: string = server.name || server.baseURL;
    return name + '：' + error + '；点击修改服务器配置';
  }

  /**
   * 根据单服务器同步结果呈现错误：有缓存时保留可用列表并显示非阻塞提示，
   * 没有缓存时保留原有的全屏错误页，防止空页面掩盖同步失败原因。
   */
  private updateSingleServerErrorPresentation(server: ServerEntry): void {
    const error: string | undefined = this.syncErrors.get(server.id);
    if (!error) {
      this.errorMsg = '';
      this.serverErrorBanner = '';
      return;
    }
    if (this.messages.length > 0) {
      this.errorMsg = '';
      this.serverErrorBanner = this.buildServerErrorBannerMessage(server, error);
      return;
    }
    this.errorMsg = error;
    this.serverErrorBanner = '';
  }

  /** 同步 Banner 出现/消失时重置视觉状态，避免下一次错误沿用旧滚动位置。 */
  private onServerErrorBannerChanged(): void {
    if (this.serverErrorBanner.length === 0) {
      this.serverErrorBannerCollapsed = false;
      this.serverErrorBannerHeight = 0;
      return;
    }
    this.serverErrorBannerCollapsed = this.scroller.currentOffset().yOffset > 0;
  }

  /**
   * Banner 覆盖在列表之上时（沉浸光感与降级模式均如此），为首项和下拉刷新指示器预留实际高度，
   * 避免首条通知被 Banner 遮挡。无 Banner 时只保留标题栏避让距离。
   */
  private getListTopInset(): number {
    const titleInset: number = this.fallbackTitleBarBottom >= 0 && this.listTop >= 0
      ? Math.max(0, this.fallbackTitleBarBottom - this.listTop) : 0;
    if (this.serverErrorBanner.length === 0) {
      return titleInset;
    }
    const bannerHeight: number = this.serverErrorBannerCollapsed ? 32 : 44;
    return titleInset + Math.max(this.serverErrorBannerHeight, bannerHeight) +
      (this.serverErrorBannerCollapsed ? COMPACT_BANNER_TOP_GAP : 0);
  }

  /** 以轻量动画切换 Banner 的完整提示与收缩胶囊形态。 */
  private setServerErrorBannerCollapsed(collapsed: boolean): void {
    if (this.serverErrorBannerCollapsed === collapsed) {
      return;
    }
    this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseOut }, () => {
      this.serverErrorBannerCollapsed = collapsed;
    });
  }

  // 找到第一个失败的服务器及其错误信息
  private findFirstErrorServer(): ServerErrorInfo | null {
    const list: ServerEntry[] = ServerManager.getInstance().getList();
    for (let i = 0; i < list.length; i++) {
      const err: string | undefined = this.syncErrors.get(list[i].id);
      if (err) {
        const info: ServerErrorInfo = { server: list[i], error: err };
        return info;
      }
    }
    return null;
  }

  // 根据错误类型直接弹对应修复弹窗
  private openFixDialogForFirstError(): void {
    const found: ServerErrorInfo | null = this.findFirstErrorServer();
    if (!found) {
      return;
    }
    const server: ServerEntry = found.server;
    const error: string = found.error;

    if (error.includes('Token')) {
      this.openClientTokenDialogFor(server);
    } else if (error.includes('设备')) {
      this.openKeyDialogFor(server);
    } else {
      this.openActionMenuFor(server);
    }
  }

  // ====== 各弹窗打开方法（复用组件，指定目标服务器） ======

  private openClientTokenDialogFor(server: ServerEntry): void {
    try {
      const dialogBg = getDialogBackgroundOptions();
      this.fixClientTokenController = new CustomDialogController({
        builder: ClientTokenDialog({
          getInitToken: (): string => server.clientToken,
          saveToken: async (token: string): Promise<boolean> => {
            await ServerManager.getInstance().updateServerClientToken(null, server.id, token);
            return true;
          },
          onSaved: (): void => {
            this.loadMessages();
          },
        }),
        alignment: DialogAlignment.Center,
        autoCancel: true,
        offset: { dx: 0, dy: 0 },
        cornerRadius: 14,
        systemMaterial: dialogBg.systemMaterial,
        backgroundColor: dialogBg.backgroundColor,
        backgroundBlurStyle: dialogBg.backgroundBlurStyle,
      });
      this.fixClientTokenController.open();
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'client token dialog open 失败');
    }
  }

  private openKeyDialogFor(server: ServerEntry): void {
    try {
      const dialogBg = getDialogBackgroundOptions();
      this.fixKeyController = new CustomDialogController({
        builder: ServerKeyDialog({
          getCurrentKey: (): string => server.deviceKey,
          onConfirm: (inputKey: string): void => {
            this.handleResetKeyFor(server, inputKey);
          },
        }),
        alignment: DialogAlignment.Center,
        autoCancel: true,
        offset: { dx: 0, dy: 0 },
        cornerRadius: 14,
        systemMaterial: dialogBg.systemMaterial,
        backgroundColor: dialogBg.backgroundColor,
        backgroundBlurStyle: dialogBg.backgroundBlurStyle,
      });
      this.fixKeyController.open();
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'key dialog open 失败');
    }
  }

  private async handleResetKeyFor(server: ServerEntry, inputKey: string): Promise<void> {
    const key: string | null = await DeviceRegisterService.getInstance()
      .syncKeyForServer(null, server.id, server.baseURL, inputKey.length > 0 ? inputKey : '');
    if (key && key.length > 0) {
      showToast(this.getUIContext(), inputKey.length > 0 ? '已还原 Key' : '已重置 Key');
      this.loadMessages();
    } else {
      showToast(this.getUIContext(), '操作失败');
    }
  }

  private openActionMenuFor(server: ServerEntry): void {
    try {
      const dialogBg = getDialogBackgroundOptions();
      this.fixActionMenuController = new CustomDialogController({
        builder: ServerActionMenuDialog({
          onCopy: () => { this.handleCopyServer(server); },
          onResetKey: () => { this.openKeyDialogFor(server); },
          onClientToken: () => { this.openClientTokenDialogFor(server); },
          onEncryption: () => { AppStorage.setOrCreate(KEY_HOME_TAB_INDEX, 1); },
          onRename: () => { AppStorage.setOrCreate(KEY_HOME_TAB_INDEX, 1); },
          onDelete: () => { AppStorage.setOrCreate(KEY_HOME_TAB_INDEX, 1); },
        }),
        alignment: DialogAlignment.Center,
        autoCancel: true,
        offset: { dx: 0, dy: 0 },
        cornerRadius: 14,
        systemMaterial: dialogBg.systemMaterial,
        backgroundColor: dialogBg.backgroundColor,
        backgroundBlurStyle: dialogBg.backgroundBlurStyle,
      });
      this.fixActionMenuController.open();
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'action menu open 失败');
    }
  }

  private async handleCopyServer(server: ServerEntry): Promise<void> {
    let key: string = server.deviceKey;
    if (!key || key.length === 0) {
      const fresh: string | null = await DeviceRegisterService.getInstance()
        .syncKeyForServer(null, server.id, server.baseURL, '');
      key = fresh && fresh.length > 0 ? fresh : '';
    }
    if (!key || key.length === 0) {
      showToast(this.getUIContext(), '未获取到 Key');
      return;
    }
    const text: string = `${server.baseURL}/${key}`;
    try {
      const data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      const sys: pasteboard.SystemPasteboard = pasteboard.getSystemPasteboard();
      await sys.setData(data);
      showToast(this.getUIContext(), '已复制地址和 Key', 1200);
    } catch (err) {
      showToast(this.getUIContext(), '复制失败');
    }
  }

  @Builder
  refreshContentBody() {
    // 沉浸光感与降级模式统一使用 Stack 覆盖布局：Banner 浮于列表上层，
    // 避免正常流布局把列表往下推、或滚动内容覆盖 Banner。
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        if (this.syncProgressText.length > 0 || this.syncFeedbackText.length > 0) {
          this.syncProgressView();
        }
        this.refreshListContent();
      }
      .width('100%')
      .height('100%');

      if (this.serverErrorBanner.length > 0) {
        this.serverErrorBannerView();
      }
    }
    .width('100%')
    .height('100%');
  }

  /** 大批量历史迁移时给出已处理数量，不宣称总数或删除成功数。 */
  @Builder
  private syncProgressView() {
    Text(this.syncProgressText.length > 0 ? this.syncProgressText : this.syncFeedbackText)
      .fontSize(12)
      .fontColor($r('app.color.color_text_secondary'))
      .padding({ left: 16, right: 16, top: 6, bottom: 6 })
      .width('100%');
  }

  /** 通知列表与下拉刷新的公共内容层；由外层决定 Banner 是流式还是固定展示。 */
  @Builder
  private refreshListContent() {
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
    .layoutWeight(1)
    .onStateChange((state: RefreshStatus) => {
      // 同步刷新状态给自定义指示器，控制其显隐。
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

        // 右下角"跳到底部"浮动按钮：上滑离开首屏时出现，位于分组按钮上方
        if (this.showScrollToBottom && !this.isEditing && this.messages.length > 0) {
          this.scrollToBottomFab();
        }

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

  /**
   * 右下角「跳到底部」浮动按钮：位于分组模式按钮上方，使用 select_more（向下箭头）图标。
   * 触发条件：上滑离开首屏时出现；下滑或回到首屏时隐藏。
   * 通过 if 条件渲染 + transition 实现淡入淡出 + 轻微上移的丝滑过渡。
   */
  @Builder
  private scrollToBottomFab() {
    Row() {
      Image($r('app.media.select_more'))
        .width(20).height(20).objectFit(ImageFit.Contain)
        .fillColor($r('app.color.color_text_primary'))
        .draggable(false);
    }
    .width(44).height(44).borderRadius(22)
    .justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center)
    .backgroundColor($r('app.color.color_bg_glass_control'))
    .backgroundBlurStyle(resolveBlurStyle('card')!)
    .border({ width: 1, color: $r('app.color.color_border_glass') })
    // 分组按钮 bottom = navBarHeight + 72；本按钮在其上方，留 12vp 间距 + 44vp 按钮高度。
    .margin({ right: 16, bottom: this.navBarHeight + 72 + 44 + 12 })
    .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 16 }))
      .animation({ duration: 220, curve: Curve.EaseOut }))
    .onClick(() => {
      this.scrollToBottom();
    });
  }

  /**
   * 处理列表滚动事件，控制「跳到底部」按钮显隐。
   * - scrollOffset > 0：列表向上滚动（手指上滑），离开首屏后显示按钮；
   * - scrollOffset < 0：列表向下滚动（手指下滑），隐藏按钮；
   * - 在首屏（yOffset <= 0）：隐藏按钮。
   * 忽略 Idle 状态，避免静止时重复触发。
   * 「跳到底部」程序滚动期间整体屏蔽，否则动画产生的正向滚动会让按钮中途重现闪烁。
   */
  private handleListScroll(scrollOffset: number, scrollState: ScrollState): void {
    if (this.isAutoScrolling || scrollState === ScrollState.Idle) {
      return;
    }
    const offset = this.scroller.currentOffset();
    const atTop: boolean = offset.yOffset <= 0;
    if (atTop) {
      if (this.showScrollToBottom) {
        this.showScrollToBottom = false;
      }
      this.setServerErrorBannerCollapsed(false);
      return;
    }
    if (scrollOffset > 0) {
      this.setServerErrorBannerCollapsed(true);
      // 上滑离开首屏，显示
      if (!this.showScrollToBottom) {
        this.showScrollToBottom = true;
      }
    } else if (scrollOffset < 0) {
      // 下滑，隐藏
      if (this.showScrollToBottom) {
        this.showScrollToBottom = false;
      }
    }
  }

  /**
   * 点击「跳到底部」按钮：隐藏按钮并置位自动滚动标记，通过信号交给列表执行两段式定位：
   * 短距离直接 smooth 滚动到末项；长距离先无动画瞬跳到末段附近，再短程 smooth 收尾。
   * 滚动结束（onScrollStop）后列表回调 onAutoScrollEnd 解除屏蔽。
   */
  private scrollToBottom(): void {
    this.showScrollToBottom = false;
    this.isAutoScrolling = true;
    this.scrollToBottomSignal++;
  }

  /** 列表自动定位滚动结束（或用户手指滚动停止）回调：解除自动滚动屏蔽。 */
  private handleAutoScrollEnd(): void {
    this.isAutoScrolling = false;
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
      .bindSheet(this.showDetail, this.detailBuilder(), {
        height: SheetSize.LARGE,
        preferType: SheetType.BOTTOM,
        // 标题与关闭按钮由 Sheet 内 HdsNavigation 的 MODAL 标题栏承载，以支持内容上滚时的动态模糊。
        showClose: false,
        enableFloatingDragBar: true,
        // 降级时减轻遮罩，让轻量模糊背板下的列表层次更可辨；正文 List 保持实色。
        maskColor: this.useSheetSystemMaterial() ? undefined : '#33000000',
        backgroundColor: this.useSheetSystemMaterial() ? Color.Transparent : $r('app.color.color_bg_sheet_blur'),
        blurStyle: this.useSheetSystemMaterial() ? undefined : BlurStyle.COMPONENT_ULTRA_THIN,
        systemMaterial: this.useSheetSystemMaterial() ? getSystemMaterial('sheet') : undefined,
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

          // 非沉浸式分支的右下角「跳到底部」按钮
          if (this.showScrollToBottom && !this.isEditing && this.messages.length > 0) {
            this.scrollToBottomFab();
          }

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
      .bindSheet(this.showDetail, this.detailBuilder(), {
        height: SheetSize.LARGE,
        preferType: SheetType.BOTTOM,
        // 标题与关闭按钮由 Sheet 内 HdsNavigation 的 MODAL 标题栏承载，以支持内容上滚时的动态模糊。
        showClose: false,
        enableFloatingDragBar: true,
        // 两种导航布局共用同一降级效果。
        maskColor: this.useSheetSystemMaterial() ? undefined : '#33000000',
        backgroundColor: this.useSheetSystemMaterial() ? Color.Transparent : $r('app.color.color_bg_sheet_blur'),
        blurStyle: this.useSheetSystemMaterial() ? undefined : BlurStyle.COMPONENT_ULTRA_THIN,
        systemMaterial: this.useSheetSystemMaterial() ? getSystemMaterial('sheet') : undefined,
        onDisappear: () => {
          this.showDetail = false;
        }
      })
      .backgroundColor($r('app.color.color_bg_page'));
    }
  }

  @Builder
  refreshHeaderBuilder() {
    NotifyRefreshHeader({ refreshState: this.refreshState,
      topInset: this.getListTopInset() });
  }

  @Builder
  listView() {
    NotifyMessageList({ messages: this.messages, isEditing: this.isEditing, selectedIds: this.selectedIds,
      expandedGroups: this.expandedGroups, groupCardHeights: this.groupCardHeights,
      groupTotals: this.groupTotals, groupLoadingMore: this.groupLoadingMore,
      groupEnabled: this.groupEnabled,
      statusBarHeight: this.statusBarHeight, navBarHeight: this.navBarHeight,
      topInset: this.getListTopInset(),
      immersiveLightEnabled: this.immersiveLightEnabled, listScroller: this.scroller,
      scrollToBottomSignal: this.scrollToBottomSignal,
      onListTopChange: (top: number) => {
        // 下拉刷新会暂时移动列表；只记录静止时的布局起点，避免占位随手势抖动。
        if (!this.refreshing && this.refreshState === RefreshStatus.Inactive && top !== this.listTop) {
          this.listTop = top;
        }
      },
      onListScroll: (scrollOffset: number, scrollState: ScrollState) =>
        this.handleListScroll(scrollOffset, scrollState),
      onListReachStart: () => {
        if (this.showScrollToBottom) {
          this.showScrollToBottom = false;
        }
        this.setServerErrorBannerCollapsed(false);
      },
      onAutoScrollEnd: () => {
        this.handleAutoScrollEnd();
      },
      onLoadMoreInGroup: (groupKey: string) => this.loadMoreInGroup(groupKey),
      onToggleSelect: (id: string) => this.toggleSelect(id),
      onSetSelected: (id: string, selected: boolean) => this.setSelected(id, selected),
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
    // detailScroller 跨次打开复用，待 Sheet 内 List 挂载后瞬时回到顶部，避免沿用上一条详情的滚动位置。
    setTimeout(() => {
      this.detailScroller.scrollEdge(Edge.Top);
    }, 50);
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
    const ids: string[] = [];
    for (let i = 0; i < this.messages.length; i++) {
      ids.push(notifyIdentity(this.messages[i]));
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

  /** 详情正文；沉浸/降级两种 MODAL 标题栏样式共用同一内容。 */
  @Builder
  detailContent() {
    NotifyMessageDetail({
      message: this.selectedMessage,
      useImmersiveMaterial: this.useDetailSheetMaterial(),
      detailScroller: this.detailScroller,
      onOpenUrl: (url: string) => { this.openUrl(url); },
      onCopyCode: (code: string) => { this.copyCode(code); },
      onCopyUrl: (url: string) => { this.copyUrl(url); },
      onCopyText: (text: string) => { this.copyText(text); },
      onCopyContent: (text: string) => { this.copyContent(text); },
      onDelete: () => {
        if (this.selectedMessage) {
          this.confirmDeleteOne(this.selectedMessage, true);
        }
      }
    });
  }

  /**
   * 详情 Sheet 内容：HdsNavigation 使用 MODAL（半模态）标题栏承载标题与关闭按钮，
   * bindToScrollable 绑定内部 List 后，内容上滚穿入标题栏区域即呈现动态模糊。
   * 沉浸分支：渐变模糊 + 自适应系统材质；降级分支：通用模糊背板。
   */
  @Builder
  detailBuilder() {
    if (this.useDetailSheetMaterial()) {
      HdsNavigation() {
        this.detailContent();
      }
        .titleBar({
          enableComponentSafeArea: true,
          content: {
            title: { mainTitle: '通知详情' },
            menu: {
              value: [
                {
                  content: {
                    icon: $r('sys.symbol.xmark'),
                    type: IconStyleMode.SMALL,
                    action: (): void => {
                      this.showDetail = false;
                    }
                  }
                }
              ]
            }
          },
          style: {
            scrollEffectOpts: {
              enableScrollEffect: true,
              scrollEffectType: ScrollEffectType.GRADIENT_BLUR
            },
            systemMaterialEffect: {
              materialType: hdsMaterial.MaterialType.ADAPTIVE,
              materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
            }
          }
        })
        .hideBackButton(true)
        .titleMode(HdsNavigationTitleMode.MODAL)
        .bindToScrollable([this.detailScroller])
        .width('100%')
        .height('100%');
    } else {
      HdsNavigation() {
        this.detailContent();
      }
        .titleBar({
          enableComponentSafeArea: true,
          content: {
            title: { mainTitle: '通知详情' },
            menu: {
              value: [
                {
                  content: {
                    icon: $r('sys.symbol.xmark'),
                    type: IconStyleMode.SMALL,
                    action: (): void => {
                      this.showDetail = false;
                    }
                  }
                }
              ]
            }
          },
          style: {
            scrollEffectOpts: {
              enableScrollEffect: true,
              scrollEffectType: ScrollEffectType.COMMON_BLUR
            }
          }
        })
        .hideBackButton(true)
        .titleMode(HdsNavigationTitleMode.MODAL)
        .bindToScrollable([this.detailScroller])
        .width('100%')
        .height('100%');
    }
  }

  /**
   * 详情内容走材质样式分支：API 26+、用户启用且 uiMaterial 已加载即可，不要求设备 supported——
   * supported=false 时 systemMaterial 虽 no-op，但透明 List + glass 卡片 + 按钮底色兜底
   * 仍能透出 bindSheet 系统面板的半透明材质（否则内容层实色，只有标题栏透）。
   */
  private useDetailSheetMaterial(): boolean {
    return SUPPORTS_IMMERSIVE_MATERIAL && this.immersiveLightEnabled && this.immersiveMaterialLoaded;
  }

  /**
   * bindSheet 容器背板走「系统材质分支」的条件：API 26+ 且用户开关开即可，
   * 不要求 isImmersiveMaterialSupported/材质就绪——supported=false 的设备（如 SMOOTH 模拟器）
   * systemMaterial 虽 no-op，但 bindSheet 系统默认面板本身就是半透明材质，比
   * blurStyle+灰底的降级分支更透；材质实例在能力闸门前已预创建，getSystemMaterial 可安全读取。
   * 注意：仅用于 sheet options；详情内部标题栏的材质组件链仍用 useDetailSheetMaterial 闸门。
   */
  private useSheetSystemMaterial(): boolean {
    return SUPPORTS_IMMERSIVE_MATERIAL && this.immersiveLightEnabled;
  }

  /** aboutToAppear 是同步签名，这里 fire-and-forget 初始化链 */
  private async initAfterServerManagerReady(): Promise<void> {
    this.loading = true;
    try {
      await ServerManager.getInstance().ensureLoaded();
      this.viewAll = ServerManager.getInstance().getViewAllMode();
      this.visibleDeviceKeys = this.getAllDeviceKeys().join('|');
      this.refresh();
      await this.refreshVisibleAfterSyncPage(++this.loadSeq);
      await NotifySyncService.getInstance().requestSync();
      await this.refreshVisibleAfterSyncPage(this.loadSeq);
      this.updateSyncErrorPresentation();
      this.hasClientToken = await NotifyMessageService.getInstance().hasEffectiveClientToken();
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, TAG, '初始化失败：%{public}s', msg);
    } finally {
      this.loading = false;
      if (this.loadQueued) {
        this.loadQueued = false;
        this.loadMessages();
      } else {
        this.processPendingPushNotice();
      }
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

  /** 复制通知 extras.copy 指定的待复制文本，供详情页 action 区“复制”按钮使用。 */
  private async copyContent(text: string): Promise<void> {
    if (text.length === 0) {
      return;
    }
    try {
      const data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      const sys: pasteboard.SystemPasteboard = pasteboard.getSystemPasteboard();
      await sys.setData(data);
      // copy 文本可能是长内容，截断后展示，避免 Toast 撑满屏幕
      const display: string = text.length > 20 ? `${text.substring(0, 20)}…` : text;
      showToast(this.getUIContext(), `已复制 ${display}`, 1500);
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, TAG, '复制待复制文本失败：%{public}s', msg);
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
    NotifySyncService.getInstance().setTabIndex(this.homeTabIndex);
    if (this.indexPageVisible && this.homeTabIndex === 0) {
      this.onSyncRevisionChanged();
    }
  }

  private onPageVisibleChanged(): void {
    if (this.indexPageVisible && this.homeTabIndex === 0) {
      this.onSyncRevisionChanged();
    }
  }

  private onSyncRevisionChanged(): void {
    if (!this.indexPageVisible || this.homeTabIndex !== 0) {
      return;
    }
    const seq: number = this.loadSeq;
    this.refreshVisibleAfterSyncPage(seq).then(() => {
      this.updateSyncErrorPresentation();
    });
  }

  private updateSyncErrorPresentation(): void {
    this.syncErrors = NotifySyncService.getInstance().getErrors();
    if (!this.viewAll) {
      const current: ServerEntry | null = ServerManager.getInstance().getCurrentServer();
      if (current) {
        this.updateSingleServerErrorPresentation(current);
      }
      return;
    }
    const servers: ServerEntry[] = this.getAllRegisteredServers();
    let errorText: string = '';
    let bannerText: string = '';
    let failed: number = 0;
    for (let i: number = 0; i < servers.length; i++) {
      const error: string | undefined = this.syncErrors.get(servers[i].id);
      if (!error) {
        continue;
      }
      failed++;
      errorText += (errorText.length > 0 ? '\n' : '') + (servers[i].name || servers[i].baseURL) + '：' + error;
      bannerText += (bannerText.length > 0 ? '\n' : '') + this.buildServerErrorBannerMessage(servers[i], error);
    }
    this.errorMsg = failed === servers.length && this.messages.length === 0 ? errorText : '';
    this.serverErrorBanner = this.errorMsg.length > 0 ? '' : bannerText;
  }

  private onRefreshSignalChanged(): void {
    this.loadMessages();
  }

  /** 温启动点击通知可能发生在任意 Tab；加载完成后统一消费最新目标。 */
  private onOpenRequestChanged(): void {
    if (this.openRequest.length > 0) {
      try {
        const values: Object = JSON.parse(this.openRequest);
        if (values instanceof Array && values.length > 3 && values[3] === 'none') {
          this.processPendingPushNotice();
          return;
        }
      } catch (_ignore) {
      }
      this.loadMessages();
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

  private isSelected(id: string): boolean {
    return hasSelectedMessage(this.selectedIds, id);
  }

  private toggleSelect(id: string): void {
    this.selectedIds = toggleSelectedMessage(this.selectedIds, id);
  }

  /** Checkbox 的 onChange 可能由状态回显触发，仅在目标状态不同的时候写入。 */
  private setSelected(id: string, selected: boolean): void {
    const next: string[] = setSelectedMessage(this.selectedIds, id, selected);
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

  private toggleGroupSelection(groupMessages: NotifyMessage[]): void {
    this.selectedIds = toggleGroupMessages(this.selectedIds, groupMessages);
  }

  private setGroupSelection(groupMessages: NotifyMessage[], selected: boolean): void {
    const next: string[] = setGroupMessagesSelection(this.selectedIds, groupMessages, selected);
    if (next !== this.selectedIds) {
      this.selectedIds = next;
    }
  }

  private removeFromList(ids: string[]): void {
    const idSet: Set<string> = new Set<string>(ids);
    const newList: NotifyMessage[] = [];
    for (let i = 0; i < this.messages.length; i++) {
      if (!idSet.has(notifyIdentity(this.messages[i]))) {
        newList.push(this.messages[i]);
      }
    }
    // 可观察分组会只删除目标子项；动画上下文同步平滑收起该行占用的布局空间。
    this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseOut }, () => {
      this.messages = newList;
      // 按真实总数同步展开态：整组删到只剩 1 条时自动收起为普通卡片。
      this.expandedGroups = retainExpandableGroups(this.messages, this.expandedGroups, this.groupTotals);
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
      this.expandedGroups = retainExpandableGroups(this.messages, this.expandedGroups, this.groupTotals);
      if (this.messages.length === 0) {
        this.exitEditMode();
      }
    });
  }

  // ====== 删除确认与执行 ======
  private confirmDeleteOne(m: NotifyMessage, closeDetailOnSuccess: boolean = false): void {
    const uiCtx: UIContext = this.getUIContext();
    uiCtx.getPromptAction().showDialog({
      title: '从本机删除通知',
      message: `此通知已从服务器迁移到本机。删除后无法恢复。${m.title && m.title.length > 0 ?
        '\n\n「' + m.title + '」' : ''}`,
      buttons: [
        { text: '取消', color: $r('app.color.color_text_tertiary') },
        { text: '删除', color: $r('app.color.color_error') },
      ],
      // API 26+ 材质就绪时系统确认框走 ULTRA_THICK 沉浸材质，旧系统缺省纯色
      systemMaterial: getDialogMaterial(),
    }, async (err: BusinessError, result: promptAction.ShowDialogSuccessResponse) => {
      if (err || result.index !== 1) {
        return;
      }
      // 远程记录已在同步落库后清理；用户操作只删除本地副本。
      if (m.deviceKey && m.deviceKey.length > 0) {
        const pair: DeviceIdPair = { deviceKey: m.deviceKey, id: m.id };
        await MessageCacheStore.deleteByDeviceIdPairs([pair]);
        this.groupTotals = await MessageCacheStore.getAllGroupTotals(this.getVisibleHistoryKeys());
      }
      this.removeFromList([notifyIdentity(m)]);
      this.exitEditMode();
      // 从详情发起删除时，确认成功后再关闭 Sheet；取消时保留当前详情。
      if (closeDetailOnSuccess) {
        this.showDetail = false;
      }
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
      // API 26+ 材质就绪时系统确认框走 ULTRA_THICK 沉浸材质，旧系统缺省纯色
      systemMaterial: getDialogMaterial(),
    }, async (err: BusinessError, result: promptAction.ShowDialogSuccessResponse) => {
      if (err || result.index !== 1) {
        return;
      }
      showToast(uiCtx, `正在删除 ${count} 条本地通知…`);
      const deviceKeys: string[] = this.getVisibleHistoryKeys();
      const deleted: number = await MessageCacheStore.deleteGroup(deviceKeys, section.groupKey);
      if (deleted < 0) {
        showToast(uiCtx, '删除失败，请稍后重试');
        return;
      }
      this.removeGroupFromList(section.groupKey);
      // 刷新分组总数
      this.groupTotals = await MessageCacheStore.getAllGroupTotals(this.getVisibleHistoryKeys());
      showToast(uiCtx, `已从本机删除 ${deleted} 条`);
    });
  }

  /** 当前服务器的全部本地历史（含旧数据库实例）。 */
  private getCurrentHistoryKeys(): string[] {
    const cur: ServerEntry | null = ServerManager.getInstance().getCurrentServer();
    return cur ? ServerManager.getInstance().getHistoryKeysForServer(cur) : [];
  }

  private getVisibleHistoryKeys(): string[] {
    return this.viewAll ? this.getAllDeviceKeys() : this.getCurrentHistoryKeys();
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
      // API 26+ 材质就绪时系统确认框走 ULTRA_THICK 沉浸材质，旧系统缺省纯色
      systemMaterial: getDialogMaterial(),
    }, async (err: BusinessError, result: promptAction.ShowDialogSuccessResponse) => {
      if (err || result.index !== 1) {
        return;
      }
      const ids: string[] = [...this.selectedIds];
      // 按 (deviceKey, id) 精确删除，避免跨服务器同 id 误删
      const pairs: DeviceIdPair[] = [];
      for (let i = 0; i < this.messages.length; i++) {
        const m: NotifyMessage = this.messages[i];
        if (ids.indexOf(notifyIdentity(m)) < 0) {
          continue;
        }
        if (m.deviceKey && m.deviceKey.length > 0) {
          pairs.push({ deviceKey: m.deviceKey, id: m.id });
        }
      }
      if (pairs.length > 0) {
        await MessageCacheStore.deleteByDeviceIdPairs(pairs);
      }
      this.groupTotals = await MessageCacheStore.getAllGroupTotals(this.getVisibleHistoryKeys());
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
      // API 26+ 材质就绪时系统确认框走 ULTRA_THICK 沉浸材质，旧系统缺省纯色
      systemMaterial: getDialogMaterial(),
    }, async (err: BusinessError, result: promptAction.ShowDialogSuccessResponse) => {
      if (err || result.index !== 1) {
        return;
      }
      if (this.viewAll) {
        await MessageCacheStore.clearAllDevices();
        showToast(uiCtx, '已清空本机全部通知');
      } else {
        const keys: string[] = this.getCurrentHistoryKeys();
        for (let i = 0; i < keys.length; i++) {
          await MessageCacheStore.clearDevice(keys[i]);
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
      const owned: string[] = ServerManager.getInstance().getHistoryKeysForServer(servers[i]);
      for (let j = 0; j < owned.length; j++) {
        if (keys.indexOf(owned[j]) < 0) {
          keys.push(owned[j]);
        }
      }
    }
    const unknown: string[] = ServerManager.getInstance().getLegacyUnknownKeys();
    for (let i = 0; i < unknown.length; i++) {
      if (keys.indexOf(unknown[i]) < 0) {
        keys.push(unknown[i]);
      }
    }
    return keys;
  }


  /** 多服务逐页提交后合并列表查询；代际变化时不把旧服务结果写回当前页面。 */
  private async refreshVisibleAfterSyncPage(expectedSeq: number): Promise<void> {
    if (this.pageRefreshInFlight) {
      this.pageRefreshPending = true;
      return;
    }
    this.pageRefreshInFlight = true;
    try {
      do {
        this.pageRefreshPending = false;
        const seq: number = this.loadSeq;
        if (expectedSeq >= 0 && expectedSeq !== seq) {
          return;
        }
        const keys: string[] = this.viewAll ? this.getAllDeviceKeys() : this.getCurrentHistoryKeys();
        const refreshed = await MessageCacheStore.loadAllGroupedLatest(keys, 100);
        if (seq === this.loadSeq) {
          this.messages = refreshed.messages;
          this.groupTotals = refreshed.totals;
        }
      } while (this.pageRefreshPending);
    } finally {
      this.pageRefreshInFlight = false;
    }
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
    this.errorMsg = '';
    this.serverErrorBanner = '';
    try {
      await ServerManager.getInstance().ensureLoaded();
      const expiredDeleted: number = await MessageCacheStore.purgeExpired();
      if (expiredDeleted > 0) {
        this.messages = [];
        this.groupTotals = new Map<string, number>();
      }
      await this.refreshVisibleAfterSyncPage(seq);
      await NotifySyncService.getInstance().requestSync();
      await this.refreshVisibleAfterSyncPage(seq);
      this.updateSyncErrorPresentation();
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
      } else {
        this.processPendingPushNotice();
      }
    }
  }

  /** 点击目标未必属于当前单服务器；按实例身份先查本地，再同步候选服务器。 */
  private async processPendingPushNotice(): Promise<void> {
    if (this.openingPushNotice || !this.openRequest || this.loading || this.loadQueued) {
      return;
    }
    this.openingPushNotice = true;
    const request: string = this.openRequest;
    try {
      const values: Object = JSON.parse(request);
      if (values instanceof Array && values.length > 3 && values[3] === 'none') {
        this.showDetail = false;
        return;
      }
      if (!(values instanceof Array) || values.length < 2 ||
        typeof values[0] !== 'string' || typeof values[1] !== 'string') {
        showToast(this.getUIContext(), '无法定位这条通知');
        return;
      }
      const instanceId: string = values[0] as string;
      const idText: string = values[1] as string;
      const id: number = Number(idText);
      if (!instanceId || !/^\d+$/.test(idText) || !Number.isSafeInteger(id) || id <= 0) {
        showToast(this.getUIContext(), '通知未归档或已过期，无法打开详情');
        return;
      }
      const manager: ServerManager = ServerManager.getInstance();
      await manager.ensureLoaded();
      const servers: ServerEntry[] = this.getAllRegisteredServers();
      let found: NotifyMessage | null = await this.findPushNotice(servers, instanceId, id);
      if (!found) {
        // 只同步当前实例匹配的服务；旧版尚未记录实例时也尝试同步确认身份。
        for (let i: number = 0; i < servers.length && !found; i++) {
          const server: ServerEntry = servers[i];
          if (server.instanceId && server.instanceId !== instanceId) {
            continue;
          }
          await NotifySyncService.getInstance().syncServerNow(server);
          found = await this.findPushNotice([server], instanceId, id);
        }
      }
      if (!found) {
        showToast(this.getUIContext(), '通知已过期、未归档或来源服务不可用');
        return;
      }
      if (AppStorage.get<string>(KEY_NOTIFY_OPEN_REQUEST) !== request) {
        return;
      }
      // 加密载荷里的 url 不会明传给 Push Kit；解密落库后仍要保持 url 高于 action 的语义。
      if (found.url) {
        this.openUrl(found.url);
        return;
      }
      // 单服务器视图中，先切到消息的真实来源，避免详情关闭后落在错误的服务列表。
      if (!manager.getViewAllMode()) {
        const source: ServerEntry | null = this.findPushNoticeServer(servers, found.deviceKey, instanceId);
        if (!source || !(await manager.switchTo(null, source.id))) {
          showToast(this.getUIContext(), '无法切换到通知来源服务');
          return;
        }
      }
      this.openMessageDetail(found);
    } catch (err) {
      const msg: string = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, TAG, '打开推送详情失败：%{public}s', msg);
      showToast(this.getUIContext(), '无法打开这条通知');
    } finally {
      if (AppStorage.get<string>(KEY_NOTIFY_OPEN_REQUEST) === request) {
        AppStorage.setOrCreate(KEY_NOTIFY_OPEN_REQUEST, '');
      }
      this.openingPushNotice = false;
      if (this.openRequest && this.openRequest !== request) {
        this.processPendingPushNotice();
      }
    }
  }

  /** 从所有已归属的历史键精确查找，绝不只按数字 ID 匹配。 */
  private async findPushNotice(servers: ServerEntry[], instanceId: string, id: number): Promise<NotifyMessage | null> {
    for (let i: number = 0; i < servers.length; i++) {
      const keys: string[] = ServerManager.getInstance().getHistoryKeysForServer(servers[i]);
      for (let j: number = 0; j < keys.length; j++) {
        if (!belongsToPushInstance(keys[j], instanceId)) {
          continue;
        }
        const message: NotifyMessage | null = await MessageCacheStore.loadByDeviceAndId(keys[j], id);
        if (message) {
          return message;
        }
      }
    }
    return null;
  }

  /** 找到本地来源键所属的配置服务；来源不明历史不得猜测归属。 */
  private findPushNoticeServer(servers: ServerEntry[], sourceKey: string, instanceId: string): ServerEntry | null {
    if (!belongsToPushInstance(sourceKey, instanceId)) {
      return null;
    }
    for (let i: number = 0; i < servers.length; i++) {
      if (ServerManager.getInstance().getHistoryKeysForServer(servers[i]).indexOf(sourceKey) >= 0) {
        return servers[i];
      }
    }
    return null;
  }


  /**
   * 组内"加载更多"：按时间、ID 和来源组成的全序加载更旧的 100 条。
   * 数据源为本地 DB（首次播种已拉取足够消息，组内分页只读本地）。
   * append 到 this.messages 末尾，buildNotifySections 会自动聚合到已有 section。
   */
  private async loadMoreInGroup(groupKey: string): Promise<void> {
    if (this.groupLoadingMore.has(groupKey)) {
      return;
    }
    let oldest: NotifyMessage | null = null;
    for (let i = 0; i < this.messages.length; i++) {
      const message: NotifyMessage = this.messages[i];
      if (message.group === groupKey && (!oldest || compareNotifyOrder(oldest, message) < 0)) {
        oldest = message;
      }
    }
    if (!oldest) {
      return;
    }
    this.groupLoadingMore = new Set<string>(this.groupLoadingMore).add(groupKey);
    try {
      const PAGE_SIZE: number = 100;
      const keys: string[] = this.getVisibleHistoryKeys();
      const older: NotifyMessage[] = await MessageCacheStore.loadAllGroupOlder(keys, groupKey, oldest, PAGE_SIZE);
      if (older.length > 0) {
        // 去重后 append
        const existingIds: Set<string> = new Set<string>();
        for (let i = 0; i < this.messages.length; i++) {
          existingIds.add(notifyIdentity(this.messages[i]));
        }
        const deduped: NotifyMessage[] = [];
        for (let i = 0; i < older.length; i++) {
          const identity: string = notifyIdentity(older[i]);
          if (!existingIds.has(identity)) {
            deduped.push(older[i]);
            existingIds.add(identity);
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
      // 「切换通知服务」弹窗：仅单选视图范围（全部通知/某服务器）。
      // 打开时构造：背板统一走 getDialogBackgroundOptions（真机 ULTRA_THICK 沉浸材质；
      // 模拟器/低算力为系统容器 COMPONENT_THICK 模糊），旧系统纯色降级
      const dialogBg = getDialogBackgroundOptions();
      this.dialogController = new CustomDialogController({
        builder: ServerSwitchDialog(),
        alignment: DialogAlignment.Center,
        autoCancel: true,
        offset: { dx: 0, dy: 0 },
        cornerRadius: 14,
        systemMaterial: dialogBg.systemMaterial,
        backgroundColor: dialogBg.backgroundColor,
        backgroundBlurStyle: dialogBg.backgroundBlurStyle,
      });
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
