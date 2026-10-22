import { hilog } from '@kit.PerformanceAnalysisKit';
import { UIContext } from '@kit.ArkUI';
import { BusinessError, pasteboard } from '@kit.BasicServicesKit';
import { common, Want } from '@kit.AbilityKit';
import { ServerEntry } from '../model/ServerEntry';
import { ServerManager } from '../services/ServerManager';
import { NotifyMessage } from '../model/NotifyMessage';
import { NotifyMessageService } from '../services/NotifyMessageService';
import { DeviceIdPair, MessageCacheStore } from '../services/MessageCacheStore';
import { PreferencesUtil } from '../utils/PreferencesUtil';
import { extractHost } from '../utils/ServerUrlUtil';
import { ServerSwitchDialog } from '../components/notify/ServerSwitchDialog';
import { ServerActionMenuDialog, ServerKeyDialog, ServerRenameDialog } from '../components/ServerActionDialogs';
import { ClientTokenDialog } from '../components/ClientTokenDialog';
import { DecryptionSettingsDialog } from '../components/DecryptionSettingsDialog';
import { DangerConfirmDialog } from '../components/DangerConfirmDialog';
import { EncryptionConfig } from '../model/EncryptionConfig';
import { EncryptionConfigService } from '../services/EncryptionConfigService';
import { DeviceRegisterService } from '../services/DeviceRegisterService';
import {
  getDialogBackgroundOptions,
  getDialogMaterial,
  getEnabledSystemMaterial,
  IMMERSIVE_GROUP_TOGGLE_MODIFIER,
  IMMERSIVE_SEARCH_TITLE_MODIFIER,
  KEY_IMMERSIVE_LIGHT_ENABLED,
  KEY_MATERIAL_LOADED,
  resolveBlurStyle,
  shouldUseLoadedMaterialStyle,
  shouldUseSystemMaterialPath
} from '../utils/ImmersiveUtil';
import {
  hdsMaterial,
  HdsNavigation,
  HdsNavigationTitleMode,
  IconStyleMode,
  ScrollEffectType,
  TextStyleMode
} from '@kit.UIDesignKit';
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
  areGroupMessagesSelected,
  hasSelectedMessage,
  retainExpandableGroups,
  setSelectedMessage,
  toggleSelectedMessage
} from '../components/notify/NotifySelectionUtils';
import { NotifyMessageDetail } from '../components/notify/NotifyMessageDetail';
import { NotifyTitleBar } from '../components/notify/NotifyTitleBar';
import { NotifyEditActionBar } from '../components/notify/NotifyEditActionBar';
import { NotifyContentState } from '../components/notify/NotifyContentState';
import { NotifyRefreshHeader } from '../components/notify/NotifyRefreshHeader';
import { NotifyGroupStateUtils } from '../components/notify/NotifyGroupStateUtils';
import { NotifyMessageList } from '../components/notify/NotifyMessageList';
import { NOTIFY_LIST_ROW_GAP } from '../components/notify/NotifyListDataSource';
import { NotifyMessageCard } from '../components/notify/NotifyMessageCard';
import { NotifyExportService } from '../services/NotifyExportService';
import {
  belongsToPushInstance,
  compareNotifyOrder,
  notifyIdentity,
  resolveCurrentRemoteServer
} from '../utils/NotifyIdentity';

const TAG: string = 'NotifyView';

// 失败服务器及其错误信息（用于点击 banner 精准弹修复弹窗）
interface ServerErrorInfo {
  server: ServerEntry;
  error: string;
}

interface ManualDeleteResult {
  deletedIds: string[];
  remoteFailed: number;
  localFailed: boolean;
}

// 收缩错误胶囊与标题栏之间保留的呼吸间距。
const COMPACT_BANNER_TOP_GAP: number = 8;
// 平铺态先读取最近 500 条，触底后每次再从本地缓存读取 500 条。
const FLAT_PAGE_SIZE: number = 500;
// 搜索栏与标题栏之间的留白；沉浸布局激活时切到 HDS 标题栏，降级布局仍平移原输入框。
const SEARCH_BAR_HEIGHT: number = 44;
const SEARCH_BAR_GAP: number = 8;
// 降级布局已有独立的定位逻辑，收缩态只需补偿标题栏下方的呼吸间距。
const SEARCH_ACTIVE_BANNER_FALLBACK_LIFT: number = 8;
// 降级布局中搜索栏与服务异常 Banner 之间单独留白。
const SEARCH_BANNER_GAP: number = 8;
// 列表自身已有 16vp 顶部间距，此处不再重复留白。
const SEARCH_BAR_BOTTOM_GAP: number = 0;
const SEARCH_TRANSITION_DURATION: number = 240;
const SEARCH_PREVIEW_HANDOFF_DURATION: number = 48;
// 右侧小图标横向展开的距离更长，使用稍长时长避免宽度与文字同时突变。
const SEARCH_COMPACT_TRANSITION_DURATION: number = 320;
// 标题下方搜索入口与 MINI 标题栏搜索框的相对位置及宽度差。
const SEARCH_ENTRY_TOP_OFFSET: number = 68;
const SEARCH_TITLE_TOP_OFFSET: number = 16;
const SEARCH_TITLE_RIGHT_EXTRA: number = 52;
// 外层 Stack 与 HDS 标题栏的坐标原点相差约 8vp，补偿后图标与输入框共用同一中心线。
const SEARCH_COMPACT_HDS_TOP_CORRECTION: number = 8;
// 离开顶部与回顶使用不同阈值，避免手指回弹时搜索入口反复展开、收缩。
const SEARCH_COLLAPSE_OFFSET: number = 16;
const SEARCH_EXPAND_OFFSET: number = 2;
// 回顶最后一段随列表位置渐进展开；完整搜索栏仍只在真正到顶时接管。
const SEARCH_EXPAND_RANGE: number = 240;
const SEARCH_SCROLL_SAMPLE_MS: number = 16;
const SEARCH_PAGE_SIZE: number = 50;
const SEARCH_DEBOUNCE_MS: number = 250;
// 搜索列表长距离跳底也只平滑滚动最后五项，避免遍历全部结果的长动画。
const SEARCH_BOTTOM_SMOOTH_RANGE: number = 5;


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
  @State @Watch('onSelectedIdsChanged') selectedIds: string[] = [];
  // 每个 group_key 当前选中的缓存消息数，供 group 头部"已选 X / Y"显示真实选中数量
  @State selectedGroupCounts: Map<string, number> = new Map<string, number>();
  // 导出选中消息：防重复触发
  @State exportingSelected: boolean = false;
  @State expandedGroups: string[] = [];
  @State groupCardHeights: Map<string, number> = new Map<string, number>();
  // 每个 group_key 的真实总数（含未加载到内存的部分），用于徽标显示和"加载更多"按钮
  @State groupTotals: Map<string, number> = new Map<string, number>();
  // 当前可见 device_keys 的本地缓存消息总数，用于"全选"计数与判断
  @State totalCachedCount: number = 0;
  // 组内加载更多进行中的 group_key 集合，用于按钮显示 loading 态
  @State groupLoadingMore: Set<string> = new Set<string>();
  // 平铺态分页状态由页面持有，列表组件只负责触底和底部提示。
  @State flatLoadingMore: boolean = false;
  // 是否启用分组显示（右下角浮动按钮切换，持久化到 Preferences）
  @State groupEnabled: boolean = true;
  @State searchActive: boolean = false;
  @State searchPreviewExiting: boolean = false;
  @State searchQuery: string = '';
  @State searchResults: NotifyMessage[] = [];
  @State searchLoading: boolean = false;
  @State searchHasMore: boolean = false;
  @State searchError: boolean = false;
  // 普通浏览态离开列表顶部后，将搜索入口缩成标题栏右侧图标。
  @State searchCollapsed: boolean = false;
  // 标题下搜索栏与标题栏圆形搜索按钮之间的跨层过渡进度。
  @State searchCollapseTransitionVisible: boolean = false;
  @State searchCollapseProgress: number = 0;
  @State searchViewportWidth: number = 400;
  // 过渡期使用独立于 HDS 标题栏裁剪区域的临时搜索胶囊。
  @State searchTransitionVisible: boolean = false;
  @State searchTransitionProgress: number = 0;
  // 右侧搜索按钮展开到标题栏输入框时，使用外层临时胶囊保持位移和宽度连续。
  @State searchCompactTransitionVisible: boolean = false;
  @State searchCompactTransitionProgress: number = 0;
  // 点击半途胶囊时记录实际几何位置，避免下一段动画跳回右侧图标起点。
  @State searchCompactStartX: number = 0;
  @State searchCompactStartY: number = 0;
  @State searchCompactStartWidth: number = SEARCH_BAR_HEIGHT;
  @State searchCompactStartHeight: number = SEARCH_BAR_HEIGHT;
  @State searchCompactStartPadding: number = 10;
  @State searchCompactStartTextOpacity: number = 0;
  @State searchCompactStartIconSize: number = 24;
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
  @State fallbackSearchBarBottom: number = -1;
  @State listTop: number = -1;
  // 「跳到底部」浮动按钮显隐：上滑离开首屏时显示，下滑、在首屏或到达底部时隐藏。
  @State showScrollToBottom: boolean = false;
  // 搜索层独立维护显隐，隐藏的普通列表回调不能改变当前搜索按钮。
  @State showSearchScrollToBottom: boolean = false;
  // 「跳到底部」触发信号：每次自增传给列表，列表 Watch 后执行两段式定位滚动。
  @State scrollToBottomSignal: number = 0;
  // 「切换通知服务」弹窗：点击时（材质必已就绪）才构造，以便 systemMaterial 读取到最新就绪态
  private dialogController: CustomDialogController | null = null;
  private onChange: ((list: ServerEntry[], curId: string) => void) | null = null;
  private loadSeq: number = 0;
  // 刷新时保持已浏览的平铺历史深度，避免同步新消息后把旧页截掉。
  private flatLoadedLimit: number = FLAT_PAGE_SIZE;
  private loadQueued: boolean = false;
  private forceRefreshQueued: boolean = false;
  // Toggle 状态回调结束后再切换列表，避免同步清空消息时卸载正在响应事件的组件。
  private groupSwitchTimer: number = -1;
  // 「跳到底部」是单次动作：等待 Toggle 回调结束后执行，并忽略期间的连点。
  private scrollToBottomTimer: number = -1;
  // 防止前后台刷新和点击信号同时到达时重复同步、重复打开详情。
  private openingPushNotice: boolean = false;
  private scroller: Scroller = new Scroller();
  // 搜索内容独立滚动；空状态也保持 List 挂载，供 HDS 标题栏正确采样。
  private searchScroller: Scroller = new Scroller();
  private searchPreviewMounted: boolean = false;
  // 搜索列表的末项可视索引及两段式跳底状态；目标为 -1 时没有在途自动滚动。
  private searchVisibleEndIndex: number = 0;
  private searchAutoScrollTarget: number = -1;
  private searchAutoScrollSmoothing: boolean = false;
  private searchAutoScrollTimeout: number = -1;
  // 自动贴底后的回弹不重新显示按钮，须由真实触摸将搜索列表滚离底部。
  private suppressSearchBottomUntilUserScroll: boolean = false;
  private searchBottomUserTouchStarted: boolean = false;
  private searchInputController: TextInputController = new TextInputController();
  private searchSeq: number = 0;
  private searchTimer: number = -1;
  // 原列表在关键词搜索期间隐藏；记录首次隐藏前的偏移以便清空或取消时恢复。
  private searchBaseOffset: number = 0;
  private searchBaseOffsetSaved: boolean = false;
  // 阻止过渡中重复点击造成标题栏与临时胶囊状态错位。
  private searchTransitioning: boolean = false;
  // 滚动方向可能在动画中改变；结束时按列表实际位置校正一次。
  private searchCollapseTransitioning: boolean = false;
  // 收缩动画中点击胶囊时，等该动画收尾后继续进入搜索，避免点击无响应。
  private pendingSearchAfterCollapse: boolean = false;
  private searchCompactStartedFromScroll: boolean = false;
  // 系统状态栏回顶不一定逐帧发送 onDidScroll，滚动期间以 Scroller 实际偏移驱动过渡。
  private searchScrollSampleTimer: number = -1;
  private searchScrollLastOffset: number = -1;
  private searchScrollIdleSamples: number = 0;
  // 只用实际偏移变化判断方向；停在过渡区时保留当前位置，不回弹到图标。
  private searchMovingTowardTop: boolean = false;
  // 详情 Sheet 内部 List 的滚动控制器，与 Sheet 内 HdsNavigation.bindToScrollable 共享以驱动标题栏动态模糊。
  private detailScroller: Scroller = new Scroller();
  // 「跳到底部」程序滚动进行中：屏蔽 handleListScroll 的方向判断，避免动画期间 onDidScroll 让按钮重现。
  private isAutoScrolling: boolean = false;
  // 自动贴底后继续隐藏按钮，直到真实手势把列表带离底部。
  private suppressBottomButtonUntilUserScroll: boolean = false;
  private bottomButtonUserTouchStarted: boolean = false;
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
  private fixEncryptionController: CustomDialogController | null = null;
  private fixRenameController: CustomDialogController | null = null;

  aboutToAppear() {
    this.initAfterServerManagerReady();
    // 读取分组显示开关（默认开启分组）
    PreferencesUtil.getString(null, PreferencesUtil.KEY_GROUP_ENABLED, 'true')
      .then((value: string) => {
        const enabled: boolean = value === 'true';
        if (enabled !== this.groupEnabled) {
          this.groupEnabled = enabled;
          this.flatLoadedLimit = FLAT_PAGE_SIZE;
          this.messages = [];
          this.refreshVisibleAfterSyncPage(-1);
        }
      });
    this.loadExpandedGroups();
    this.onChange = (_list: ServerEntry[], _curId: string): void => {
      this.resetSearchBottomButton();
      this.suppressBottomButtonUntilUserScroll = false;
      this.bottomButtonUserTouchStarted = false;
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
        this.flatLoadedLimit = FLAT_PAGE_SIZE;
        this.messages = [];
        this.expandedGroups = [];
        this.groupCardHeights = new Map<string, number>();
        this.groupTotals = new Map<string, number>();
        this.totalCachedCount = 0;
        this.groupLoadingMore = new Set<string>();
      }
      this.loadSeq++;
      if (this.isSearchPreviewVisible()) {
        this.scheduleSearch();
      }
      this.loadMessages();
    };
    ServerManager.getInstance().addChangeListener(this.onChange);
  }

  aboutToDisappear() {
    this.resetSearchBottomButton();
    this.searchPreviewMounted = false;
    this.suppressBottomButtonUntilUserScroll = false;
    this.bottomButtonUserTouchStarted = false;
    if (this.groupSwitchTimer >= 0) {
      clearTimeout(this.groupSwitchTimer);
      this.groupSwitchTimer = -1;
    }
    if (this.scrollToBottomTimer >= 0) {
      clearTimeout(this.scrollToBottomTimer);
      this.scrollToBottomTimer = -1;
    }
    this.pendingSearchAfterCollapse = false;
    this.stopSearchScrollSampling();
    if (this.onChange) {
      ServerManager.getInstance().removeChangeListener(this.onChange);
    }
    this.loadSeq++;
  }

  @Builder
  fallbackTitleBar() {
    NotifyTitleBar({
      title: this.title,
      isEditing: this.isEditing,
      statusBarHeight: this.statusBarHeight,
      // 临时滚动胶囊接管搜索入口时，不再同时显示标题栏右侧的搜索图标。
      searchCollapsed: this.searchCollapsed && !this.searchCollapseTransitionVisible &&
        !this.searchCompactTransitionVisible,
      onOpenSettings: () => this.handleMoreClicked(),
      onToggleSelection: () => this.handleMultiSelectClicked(),
      onDelete: () => this.handleDeletePillClicked(),
      onSearch: () => this.enterSearch()
    })
      .opacity(this.searchActive ? 0 : this.searchCompactTransitionVisible ?
        1 - this.searchCompactTransitionProgress : 1)
      .hitTestBehavior(this.searchActive || this.searchCompactTransitionVisible ?
        HitTestMode.None : HitTestMode.Default)
      .onAreaChange((_old: Area, area: Area) => {
        const bottom: number = (area.globalPosition.y as number) + (area.height as number);
        if (bottom >= 0 && bottom !== this.fallbackTitleBarBottom) {
          this.fallbackTitleBarBottom = bottom;
        }
      });
  }

  @Builder
  customTitleContent() {
    if (this.searchActive) {
      this.searchTitleBar();
    } else {
      NotifyTitleBar({
        title: this.title,
        isEditing: this.isEditing,
        useHdsLayout: true,
        searchCollapsed: this.searchCollapsed,
        onOpenSettings: () => this.handleMoreClicked()
      })
        .opacity(this.searchTransitionVisible ? 0 : this.searchCompactTransitionVisible ?
          1 - this.searchCompactTransitionProgress : 1);
    }
  }

  /** 标题栏与普通入口共用字段结构，避免两套搜索内容和行为逐渐分叉。 */
  @Builder
  private searchField() {
    Row({ space: 4 }) {
      Image($r('app.media.search'))
        .width(20)
        .height(20)
        .objectFit(ImageFit.Contain)
        .fillColor($r('app.color.color_text_hint'))
        .draggable(false);
      TextInput({ placeholder: '搜索通知', text: this.searchQuery, controller: this.searchInputController })
        .id('notify_search_input')
        .layoutWeight(1)
        .height(SEARCH_BAR_HEIGHT)
        .fontSize(16)
        .fontColor($r('app.color.color_text_primary'))
        .placeholderColor($r('app.color.color_text_hint'))
        .backgroundColor(Color.Transparent)
        .padding({ left: 0, right: 0 })
        .enableKeyboardOnFocus(this.searchActive)
        .onClick(() => this.enterSearch())
        .onChange((value: string) => {
          // HDS 标题栏更新可能重复回调相同文本；只在真实输入变化时重新防抖查询。
          if (value === this.searchQuery) {
            return;
          }
          if (!this.searchBaseOffsetSaved && this.searchQuery.trim().length === 0 && value.trim().length > 0) {
            const offset = this.getListYOffset();
            if (offset !== undefined) {
              this.searchBaseOffset = Math.max(0, offset);
              this.searchBaseOffsetSaved = true;
            }
          }
          this.searchQuery = value;
          this.scheduleSearch();
          if (value.trim().length === 0) {
            this.restoreSearchBaseOffset();
          }
        });
    }
    .layoutWeight(1)
    .height(SEARCH_BAR_HEIGHT)
    .padding({ left: 14, right: 10 })
    .alignItems(VerticalAlign.Center);
  }

  /** 激活时让输入框真正成为 HDS 标题栏子节点，系统材质由 util 统一启用。 */
  @Builder
  private searchTitleBar() {
    Row({ space: 8 }) {
      Row() {
        this.searchField();
      }
      .layoutWeight(1)
      .height(SEARCH_BAR_HEIGHT)
      .borderRadius(22)
      .attributeModifier(IMMERSIVE_SEARCH_TITLE_MODIFIER);

      Text('取消')
        .fontSize(16)
        .fontColor($r('app.color.color_text_primary'))
        .height(SEARCH_BAR_HEIGHT)
        .padding({ left: 4, right: 4 })
        .align(Alignment.Center)
        .onClick(() => this.cancelSearch());
    }
    .width('100%')
    .height(SEARCH_BAR_HEIGHT)
    .padding({ left: 16, right: 16 })
    .opacity(this.searchTransitionVisible || this.searchCompactTransitionVisible ? 0 : 1);
  }

  /** 默认入口展示为文本胶囊，避免点击时提前唤起键盘。 */
  @Builder
  private searchBottomBar() {
    Row() {
      Row() {
        Row({ space: 4 }) {
          Image($r('app.media.search'))
            .width(20)
            .height(20)
            .objectFit(ImageFit.Contain)
            .fillColor($r('app.color.color_text_hint'))
            .draggable(false);
          Text('搜索通知')
            .fontSize(16)
            .fontColor($r('app.color.color_text_hint'));
        }
        .padding({ left: 14 });
      }
      .layoutWeight(1)
      .height(SEARCH_BAR_HEIGHT)
      .borderRadius(22)
      .attributeModifier(IMMERSIVE_SEARCH_TITLE_MODIFIER)
      .onClick(() => this.enterSearch());
    }
    .width('100%')
    .height(SEARCH_BAR_HEIGHT + SEARCH_BAR_GAP)
    .padding({ left: 16, right: 16, bottom: SEARCH_BAR_GAP })
    .opacity(this.searchTransitionVisible || this.searchCollapseTransitionVisible ? 0 : 1)
    .hitTestBehavior(this.searchTransitionVisible || this.searchCollapseTransitionVisible ?
      HitTestMode.None : HitTestMode.Default);
  }

  /** 位于 HDS 外层的滚动收缩胶囊，避免跨标题栏时被 bottomBuilder 裁剪。 */
  @Builder
  private searchCollapseTransitionBar() {
    Row({ space: 4 }) {
      Image($r('app.media.search'))
        .width(20)
        .height(20)
        .objectFit(ImageFit.Contain)
        .fillColor($r('app.color.color_text_hint'))
        .draggable(false);
      Text('搜索通知')
        .fontSize(16)
        .fontColor($r('app.color.color_text_hint'))
        .maxLines(1)
        .opacity(1 - this.searchCollapseProgress);
    }
    .width((this.searchViewportWidth - 32) * (1 - this.searchCollapseProgress) +
      (shouldUseSystemMaterialPath(this.immersiveLightEnabled) ? SEARCH_BAR_HEIGHT : 38) *
      this.searchCollapseProgress)
    .height(SEARCH_BAR_HEIGHT - (shouldUseSystemMaterialPath(this.immersiveLightEnabled) ? 0 : 6) *
      this.searchCollapseProgress)
    .padding({ left: 14 - 2 * this.searchCollapseProgress })
    .borderRadius(22)
    .clip(true)
    // 跨层移动期间系统材质不会连续绘制，临时层使用同主题毛玻璃兜底。
    .backgroundColor($r('app.color.color_bg_glass_control'))
    .backgroundBlurStyle(resolveBlurStyle('card')!)
    .border({ width: 1, color: $r('app.color.color_border_glass') })
    .position({ x: 16, y: shouldUseSystemMaterialPath(this.immersiveLightEnabled) ?
      this.statusBarHeight + SEARCH_ENTRY_TOP_OFFSET :
      Math.max(this.fallbackTitleBarBottom, this.statusBarHeight + 56) + SEARCH_BAR_GAP })
    .translate({
      x: (this.searchViewportWidth - 32 - (shouldUseSystemMaterialPath(this.immersiveLightEnabled) ?
        SEARCH_BAR_HEIGHT : 38)) * this.searchCollapseProgress,
      y: (this.statusBarHeight + SEARCH_TITLE_TOP_OFFSET -
        (shouldUseSystemMaterialPath(this.immersiveLightEnabled) ?
          this.statusBarHeight + SEARCH_ENTRY_TOP_OFFSET :
          Math.max(this.fallbackTitleBarBottom, this.statusBarHeight + 56) + SEARCH_BAR_GAP)) *
        this.searchCollapseProgress
    })
    .onClick(() => this.enterSearch());
  }

  /** 从标题栏右侧图标原位展开，结束后由真正的输入框接管焦点和系统材质。 */
  @Builder
  private searchCompactTransitionBar() {
    Row({ space: 4 }) {
      Image($r('app.media.search'))
        .width(this.searchCompactStartIconSize * (1 - this.searchCompactTransitionProgress) +
          20 * this.searchCompactTransitionProgress)
        .height(this.searchCompactStartIconSize * (1 - this.searchCompactTransitionProgress) +
          20 * this.searchCompactTransitionProgress)
        .objectFit(ImageFit.Contain)
        .fillColor(this.searchCompactStartedFromScroll ? $r('app.color.color_text_hint') :
          $r('app.color.color_text_primary'))
        .opacity(1 - 0.4 * this.searchCompactTransitionProgress)
        .draggable(false);
      Text('搜索通知')
        .fontSize(16)
        .fontColor($r('app.color.color_text_hint'))
        .maxLines(1)
        .opacity(this.searchCompactStartTextOpacity * (1 - this.searchCompactTransitionProgress) +
          Math.max(0, (this.searchCompactTransitionProgress - 0.35) / 0.65));
    }
    .width(this.searchCompactStartWidth * (1 - this.searchCompactTransitionProgress) +
      (this.searchViewportWidth - 32 - SEARCH_TITLE_RIGHT_EXTRA) * this.searchCompactTransitionProgress)
    .height(this.searchCompactStartHeight * (1 - this.searchCompactTransitionProgress) +
      SEARCH_BAR_HEIGHT * this.searchCompactTransitionProgress)
    .padding({ left: this.searchCompactStartPadding * (1 - this.searchCompactTransitionProgress) +
      14 * this.searchCompactTransitionProgress })
    .borderRadius(22)
    .clip(true)
    .backgroundColor($r('app.color.color_bg_glass_control'))
    .backgroundBlurStyle(resolveBlurStyle('card')!)
    .border({ width: 1, color: $r('app.color.color_border_glass') })
    .position({ x: this.searchCompactStartX, y: this.searchCompactStartY })
    .translate({
      x: (16 - this.searchCompactStartX) * this.searchCompactTransitionProgress,
      y: (this.statusBarHeight + SEARCH_TITLE_TOP_OFFSET -
        (shouldUseSystemMaterialPath(this.immersiveLightEnabled) ? SEARCH_COMPACT_HDS_TOP_CORRECTION : 3) -
        this.searchCompactStartY) * this.searchCompactTransitionProgress
    });

    Text('取消')
      .fontSize(16)
      .fontColor($r('app.color.color_text_primary'))
      .width(SEARCH_TITLE_RIGHT_EXTRA - 8)
      .height(SEARCH_BAR_HEIGHT)
      .opacity(Math.max(0, (this.searchCompactTransitionProgress - 0.45) / 0.55))
      .align(Alignment.Center)
      .position({ x: this.searchViewportWidth - 16 - (SEARCH_TITLE_RIGHT_EXTRA - 8),
        y: this.statusBarHeight + SEARCH_TITLE_TOP_OFFSET -
          (shouldUseSystemMaterialPath(this.immersiveLightEnabled) ? SEARCH_COMPACT_HDS_TOP_CORRECTION : 3) });
  }

  /** 过渡胶囊位于外层 Stack，移动时不会被 HDS 的 bottomBuilder 裁剪。 */
  @Builder
  private searchTransitionBar() {
    Row({ space: 8 * this.searchTransitionProgress }) {
      Row({ space: 4 }) {
        Image($r('app.media.search'))
          .width(20)
          .height(20)
          .objectFit(ImageFit.Contain)
          .fillColor($r('app.color.color_text_hint'))
          .draggable(false);
        Text('搜索通知')
          .fontSize(16)
          .fontColor($r('app.color.color_text_hint'));
      }
      .layoutWeight(1)
      .height(SEARCH_BAR_HEIGHT)
      .padding({ left: 14 })
      .borderRadius(22)
      // 移动中的跨层材质不会持续绘制，临时胶囊用轻量毛玻璃避免中途变成纯透明。
      .backgroundColor($r('app.color.color_bg_glass_control'))
      .backgroundBlurStyle(resolveBlurStyle('card')!)
      .border({ width: 1, color: $r('app.color.color_border_glass') });

      Text('取消')
        .fontSize(16)
        .fontColor($r('app.color.color_text_primary'))
        .width((SEARCH_TITLE_RIGHT_EXTRA - 8) * this.searchTransitionProgress)
        .height(SEARCH_BAR_HEIGHT)
        .opacity(this.searchTransitionProgress)
        .align(Alignment.Center);
    }
    .width('100%')
    .height(SEARCH_BAR_HEIGHT)
    .padding({ left: 16, right: 16 })
    .position({ x: 0, y: this.statusBarHeight + SEARCH_ENTRY_TOP_OFFSET })
    .translate({ y: (SEARCH_TITLE_TOP_OFFSET - SEARCH_ENTRY_TOP_OFFSET) * this.searchTransitionProgress });
  }

  /** 未激活时展示标题下的入口；降级布局仍在同一覆盖层内完成切换。 */
  @Builder
  private searchBar() {
    Row({ space: this.searchActive ? 8 : 0 }) {
      Row() {
        this.searchField();
      }
      .layoutWeight(1)
      .height(SEARCH_BAR_HEIGHT)
      .padding({ left: 14, right: 10 })
      .alignItems(VerticalAlign.Center)
      .borderRadius(22)
      .border({ width: 1, color: $r('app.color.color_border_glass') })
      .backgroundColor($r('app.color.color_bg_glass_control'))
      .backgroundBlurStyle(resolveBlurStyle('card')!)
      .onClick(() => this.enterSearch());

      if (this.searchActive) {
        Text('取消')
          .fontSize(16)
          .fontColor($r('app.color.color_text_primary'))
          .height(SEARCH_BAR_HEIGHT)
          .padding({ left: 4, right: 4 })
          .align(Alignment.Center)
          .onClick(() => this.cancelSearch());
      }
    }
    .width('100%')
    .height(SEARCH_BAR_HEIGHT)
    .padding({ left: 16, right: 16 })
    .position({ x: 0, y: this.searchActive ? this.statusBarHeight + 13 :
      (shouldUseSystemMaterialPath(this.immersiveLightEnabled) ? this.statusBarHeight + 56 :
        Math.max(this.fallbackTitleBarBottom, this.statusBarHeight + 56)) + SEARCH_BAR_GAP })
    .onAreaChange((_old: Area, area: Area) => {
      if (!this.searchActive) {
        return;
      }
      const bottom: number = (area.globalPosition.y as number) + (area.height as number);
      if (bottom >= 0 && bottom !== this.fallbackSearchBarBottom) {
        this.fallbackSearchBarBottom = bottom;
      }
    })
    .opacity(this.searchCollapseTransitionVisible || this.searchCompactTransitionVisible ? 0 : 1)
    .hitTestBehavior(this.searchCollapseTransitionVisible || this.searchCompactTransitionVisible ?
      HitTestMode.None : HitTestMode.Default)
    .zIndex(2);
  }

  /** 分组模式下用独立平铺层承载搜索；底层分组 List 始终保留节点和滚动位置。 */
  @Builder
  private searchPreview() {
    Column() {
      List({ space: 0, scroller: this.searchScroller }) {
        // 降级布局的 List 从页面顶端开始，首项必须避开标题栏中的搜索框。
        ListItem() {
          Row().width('100%').height(this.getSearchPreviewTopInset());
        }
        // 空关键词也从独立平铺分页读取，不能拼接各组快照后把末条当作全局分页游标。
        if (this.searchResults.length === 0) {
          ListItem() {
            Text(this.searchLoading ? '正在搜索…' : this.searchError ? '搜索失败，请重试' : '没有找到相关通知')
              .fontSize(16)
              .fontColor($r('app.color.color_text_secondary'))
              .width('100%')
              .textAlign(TextAlign.Center)
              .padding({ top: 40 })
              .onClick(() => { if (this.searchError) this.scheduleSearch(); });
          }
        } else {
          ForEach(this.searchResults, (message: NotifyMessage) => {
            ListItem() {
              NotifyMessageCard({
                message: message,
                // 保留分组空词预览首条的共享转场，底层分组数据源仍不改写。
                contentTransitionId: this.groupEnabled && this.searchQuery.trim().length === 0 &&
                  this.messages.length > 0 && notifyIdentity(message) === notifyIdentity(this.messages[0]) ?
                  `gmc:${message.group}` : '',
                onOpen: (item: NotifyMessage) => this.openMessageDetail(item),
                onOpenUrl: (url: string) => this.openUrl(url),
                onCopyCode: (code: string) => this.copyCode(code),
                onCopyUrl: (url: string) => this.copyUrl(url)
              });
            }
            .margin({ bottom: NOTIFY_LIST_ROW_GAP });
          }, (message: NotifyMessage) => notifyIdentity(message));
          ListItem() {
            Text(this.searchLoading ? '加载中…' : this.searchError ? '加载失败，点击重试' :
              this.searchHasMore ? '加载更多' : '没有更多了')
              .fontSize(14)
              .fontColor($r('app.color.color_text_secondary'))
              .width('100%')
              .textAlign(TextAlign.Center)
              .padding(16)
              .onClick(() => this.loadMoreSearch());
          }
        }
        ListItem() {
          Row().width('100%').height(this.navBarHeight + 72);
        }
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ left: 16, right: 16 })
      .clip(false)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .onAppear(() => {
        this.searchPreviewMounted = true;
        if (this.groupEnabled && this.searchQuery.trim().length === 0) {
          this.scheduleSearch();
        }
      })
      .onDisAppear(() => {
        this.searchPreviewMounted = false;
        this.resetSearchBottomButton();
      })
      .onDidScroll((scrollOffset: number, scrollState: ScrollState) => {
        this.handleSearchResultScroll(scrollOffset, scrollState);
      })
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Down && this.isSearchPreviewVisible()) {
          this.finishSearchAutoScroll();
          this.searchBottomUserTouchStarted = true;
        }
      })
      .onScrollIndex((_first: number, last: number) => {
        this.searchVisibleEndIndex = last;
        if (this.searchAutoScrollTarget >= 0 && !this.searchAutoScrollSmoothing &&
          last >= this.searchAutoScrollTarget - SEARCH_BOTTOM_SMOOTH_RANGE) {
          this.startSearchBottomSmoothing();
        }
      })
      .onScrollStop(() => {
        // 瞬跳阶段的 stop 不代表两段式定位结束；只在平滑收尾之后解除屏蔽。
        if (this.searchAutoScrollSmoothing) {
          this.finishSearchAutoScroll();
        }
      })
      .onReachStart(() => {
        this.showSearchScrollToBottom = false;
      })
      .onReachEnd(() => {
        this.showSearchScrollToBottom = false;
        this.loadMoreSearch();
      });
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Center)
    .backgroundColor($r('app.color.color_bg_page'))
    // 分组时平铺层一直可见；非分组时仍只在有关键词时覆盖原列表。
    .visibility(this.groupEnabled || this.searchQuery.trim().length > 0 ? Visibility.Visible : Visibility.Hidden);
  }

  /** 输入防抖并废弃旧请求；搜索范围与当前通知视图一致。 */
  private scheduleSearch(): void {
    this.resetSearchBottomButton();
    // 平铺层可能已有滚动位置；输入首字或切换关键词都让结果从顶部开始。
    if (this.searchPreviewMounted && this.searchActive) {
      this.searchScroller.scrollEdge(Edge.Top);
    }
    this.searchSeq++;
    if (this.searchTimer >= 0) {
      clearTimeout(this.searchTimer);
      this.searchTimer = -1;
    }
    this.searchResults = [];
    this.searchHasMore = false;
    this.searchError = false;
    // 平铺空词继续使用原列表；分组空词预览需要独立查询完整历史，支持触底分页。
    if (this.searchQuery.trim().length === 0 && !this.groupEnabled) {
      this.searchLoading = false;
      return;
    }
    this.searchLoading = true;
    const seq: number = this.searchSeq;
    this.searchTimer = setTimeout(() => {
      this.searchTimer = -1;
      this.fetchSearchPage(seq, null);
    }, SEARCH_DEBOUNCE_MS);
  }

  private async fetchSearchPage(seq: number, before: NotifyMessage | null): Promise<void> {
    const keys: string[] = this.getVisibleHistoryKeys();
    const query: string = this.searchQuery.trim();
    // 空词沿用普通平铺每页 500 条；多读一条判断是否还有下一页，不修改分组快照。
    const pageSize: number = query.length === 0 ? FLAT_PAGE_SIZE : SEARCH_PAGE_SIZE;
    const page: NotifyMessage[] | null = query.length === 0 ?
      (before ? await MessageCacheStore.loadAllFlatOlder(keys, before, pageSize + 1) :
        await MessageCacheStore.loadAllFlatLatest(keys, pageSize + 1)) :
      await MessageCacheStore.searchLocal(keys, query, before, pageSize + 1);
    if (seq !== this.searchSeq || !this.searchActive || query !== this.searchQuery.trim() ||
      keys.join('|') !== this.getVisibleHistoryKeys().join('|')) {
      return;
    }
    this.searchLoading = false;
    if (page === null) {
      this.searchError = true;
      return;
    }
    this.searchError = false;
    this.searchHasMore = page.length > pageSize;
    const visible: NotifyMessage[] = page.slice(0, pageSize);
    // 新页改变末项索引，终止旧目标；保持贴底屏蔽，下一次真实滚动再允许显示按钮。
    this.finishSearchAutoScroll();
    this.searchResults = before ? this.searchResults.concat(visible) : visible;
  }

  private loadMoreSearch(): void {
    if (!this.isSearchPreviewVisible() || this.searchLoading || (!this.searchHasMore && !this.searchError) ||
      this.searchResults.length === 0) {
      return;
    }
    this.searchLoading = true;
    this.searchError = false;
    this.fetchSearchPage(this.searchSeq, this.searchResults[this.searchResults.length - 1]);
  }

  /** 搜索层撤下后还原原列表的浏览位置，避免 HDS 切换滚动器时将其重置到顶部。 */
  private restoreSearchBaseOffset(): void {
    if (!this.searchBaseOffsetSaved) {
      return;
    }
    const offset: number = this.searchBaseOffset;
    this.searchBaseOffsetSaved = false;
    setTimeout((): void => {
      this.scroller.scrollTo({ xOffset: 0, yOffset: offset, animation: false });
    }, 32);
  }

  /** 记录搜索入口当下的位置，供进入与取消搜索共用同一动画端点。 */
  private prepareSearchCompactTransition(fromScroll: boolean): void {
    const materialPath: boolean = shouldUseSystemMaterialPath(this.immersiveLightEnabled);
    const compactSize: number = materialPath ? SEARCH_BAR_HEIGHT : 38;
    this.searchCompactStartedFromScroll = fromScroll;
    if (fromScroll) {
      const progress: number = this.searchCollapseProgress;
      const entryY: number = materialPath ? this.statusBarHeight + SEARCH_ENTRY_TOP_OFFSET :
        Math.max(this.fallbackTitleBarBottom, this.statusBarHeight + 56) + SEARCH_BAR_GAP;
      this.searchCompactStartX = 16 + (this.searchViewportWidth - 32 - compactSize) * progress;
      this.searchCompactStartY = entryY + (this.statusBarHeight + SEARCH_TITLE_TOP_OFFSET - entryY) * progress;
      this.searchCompactStartWidth = (this.searchViewportWidth - 32) * (1 - progress) + compactSize * progress;
      this.searchCompactStartHeight = SEARCH_BAR_HEIGHT - (materialPath ? 0 : 6) * progress;
      this.searchCompactStartPadding = 14 - 2 * progress;
      this.searchCompactStartTextOpacity = 1 - progress;
      this.searchCompactStartIconSize = 20;
      return;
    }
    this.searchCompactStartX = this.searchViewportWidth - 16 - compactSize;
    this.searchCompactStartY = this.statusBarHeight + SEARCH_TITLE_TOP_OFFSET -
      (materialPath ? SEARCH_COMPACT_HDS_TOP_CORRECTION : 0);
    this.searchCompactStartWidth = compactSize;
    this.searchCompactStartHeight = compactSize;
    this.searchCompactStartPadding = 10;
    this.searchCompactStartTextOpacity = 0;
    this.searchCompactStartIconSize = 24;
  }

  /** 外层胶囊先完成上移，之后才切换标题栏节点和聚焦输入框。 */
  private enterSearch(): void {
    if (this.searchActive || this.isEditing || this.searchTransitioning) {
      return;
    }
    if (this.searchCollapseTransitioning) {
      this.pendingSearchAfterCollapse = true;
      return;
    }
    this.resetSearchBottomButton();
    this.searchPreviewExiting = false;
    const offset: number | undefined = this.getListYOffset();
    if (offset !== undefined) {
      this.searchBaseOffset = Math.max(0, offset);
      this.searchBaseOffsetSaved = true;
    }
    // 点击滚动过渡胶囊时先结束它的采样与绘制，避免输入框接管后旧胶囊仍叠在列表上。
    this.stopSearchScrollSampling();
    // 降级搜索栏上移前清除普通入口的旧坐标，首项占位先使用目标位置，随后再以实测底边校准。
    this.fallbackSearchBarBottom = -1;
    // 收起状态从右侧图标原位展开，结束后再挂载输入框和键盘。
    if (this.searchCollapsed) {
      this.prepareSearchCompactTransition(this.searchCollapseTransitionVisible);
      this.searchTransitioning = true;
      this.searchCompactTransitionProgress = 0;
      this.searchCollapseTransitionVisible = false;
      this.searchCompactTransitionVisible = true;
      this.getUIContext().animateTo({ duration: SEARCH_COMPACT_TRANSITION_DURATION, curve: Curve.EaseOut }, () => {
        this.searchCompactTransitionProgress = 1;
        this.searchActive = true;
      });
      setTimeout(() => {
        this.searchCompactTransitionVisible = false;
        this.searchTransitioning = false;
        setTimeout(() => focusControl.requestFocus('notify_search_input'), 64);
      }, SEARCH_COMPACT_TRANSITION_DURATION);
      return;
    }
    this.searchCollapseTransitionVisible = false;
    if (shouldUseSystemMaterialPath(this.immersiveLightEnabled)) {
      this.searchTransitioning = true;
      this.searchTransitionProgress = 0;
      this.searchTransitionVisible = true;
      this.getUIContext().animateTo({ duration: SEARCH_TRANSITION_DURATION, curve: Curve.EaseOut }, () => {
        this.searchTransitionProgress = 1;
        this.searchActive = true;
      });
      setTimeout(() => {
        this.searchTransitionVisible = false;
        this.searchTransitioning = false;
        setTimeout(() => focusControl.requestFocus('notify_search_input'), 32);
      }, SEARCH_TRANSITION_DURATION);
      return;
    }
    this.getUIContext().animateTo({ duration: SEARCH_TRANSITION_DURATION, curve: Curve.EaseOut }, () => {
      this.searchActive = true;
    });
    setTimeout(() => {
      if (this.searchActive) {
        focusControl.requestFocus('notify_search_input');
      }
    }, SEARCH_TRANSITION_DURATION);
  }

  /** 取消搜索仅恢复 UI；原列表节点与滚动控制器始终保留。 */
  private cancelSearch(): void {
    if (this.searchTransitioning) {
      return;
    }
    this.resetSearchBottomButton();
    this.searchInputController.stopEditing();
    this.searchSeq++;
    if (this.searchTimer >= 0) {
      clearTimeout(this.searchTimer);
      this.searchTimer = -1;
    }
    const exitSeq: number = this.searchSeq;
    this.searchPreviewExiting = this.searchQuery.trim().length > 0 || this.groupEnabled;
    // 原分组列表没有被改写；短暂保留搜索层，等标题栏开始回收后直接交接。
    setTimeout(() => {
      if (this.searchActive || this.searchSeq !== exitSeq) {
        return;
      }
      this.searchQuery = '';
      this.searchPreviewExiting = false;
    }, SEARCH_PREVIEW_HANDOFF_DURATION);
    // 结果层退场后再清理旧内容，避免先闪出空状态。
    setTimeout(() => {
      if (this.searchActive || this.searchSeq !== exitSeq) {
        return;
      }
      this.searchResults = [];
      this.searchLoading = false;
      this.searchHasMore = false;
      this.searchError = false;
    }, SEARCH_PREVIEW_HANDOFF_DURATION + 16);
    this.restoreSearchBaseOffset();
    // 只切换叠层可见性，不重建底层分组 List。
    this.searchActive = false;
    // 从输入框反向收回右侧图标，保留进入搜索前的列表滚动位置。
    if (this.searchCollapsed) {
      this.searchTransitioning = true;
      this.searchCompactTransitionProgress = 1;
      this.searchCompactTransitionVisible = true;
      this.getUIContext().animateTo({ duration: SEARCH_COMPACT_TRANSITION_DURATION, curve: Curve.EaseInOut }, () => {
        this.searchCompactTransitionProgress = 0;
      });
      setTimeout(() => {
        this.searchCompactTransitionVisible = false;
        this.searchTransitioning = false;
        const currentOffset = this.getListYOffset();
        if (currentOffset === undefined) {
          return;
        }
        const offset: number = Math.max(0, currentOffset);
        if (offset <= SEARCH_EXPAND_OFFSET) {
          this.finishSearchExpandAtTop();
        } else if (this.searchCompactStartedFromScroll && offset < SEARCH_EXPAND_RANGE) {
          const ratio: number = offset / SEARCH_EXPAND_RANGE;
          this.searchCollapseProgress = ratio * ratio * (3 - 2 * ratio);
          this.searchCollapseTransitionVisible = true;
        }
      }, SEARCH_COMPACT_TRANSITION_DURATION);
      return;
    }
    if (shouldUseSystemMaterialPath(this.immersiveLightEnabled)) {
      this.searchTransitioning = true;
      this.searchTransitionProgress = 1;
      this.searchTransitionVisible = true;
      setTimeout(() => {
        this.getUIContext().animateTo({ duration: SEARCH_TRANSITION_DURATION, curve: Curve.EaseInOut }, () => {
          this.searchTransitionProgress = 0;
        });
        setTimeout(() => {
          this.searchTransitionVisible = false;
          this.searchTransitioning = false;
        }, SEARCH_TRANSITION_DURATION);
      }, 16);
      return;
    }
  }

  // 单服务或全部模式下 per-server 错误的非阻塞提示条（点击打开对应修复入口）
  private getBannerSearchCollapseProgress(): number {
    if (this.isEditing) {
      return 0;
    }
    // 右侧图标展开为标题栏输入框不会恢复下方搜索栏；保留滚动收缩量。
    if (this.searchCollapsed && (this.searchCompactTransitionVisible || this.searchActive)) {
      const start: number = this.searchCompactStartedFromScroll ? this.searchCollapseProgress : 1;
      return Math.max(0, Math.min(1, start));
    }
    if (this.searchCollapseTransitionVisible) {
      return Math.max(0, Math.min(1, this.searchCollapseProgress));
    }
    return this.searchCollapsed ? 1 : 0;
  }

  private getBannerSearchActiveLiftProgress(): number {
    if (this.isEditing) {
      return 0;
    }
    if (this.searchCompactTransitionVisible) {
      return Math.max(0, Math.min(1, this.searchCompactTransitionProgress));
    }
    if (this.searchTransitionVisible) {
      return Math.max(0, Math.min(1, this.searchTransitionProgress));
    }
    return this.searchActive ? 1 : 0;
  }

  /** HDS 外层的 Banner 与搜索过渡胶囊共用屏幕坐标，不再依赖内容区起点。 */
  private getHdsBannerTop(): number {
    const titleY: number = this.statusBarHeight + SEARCH_TITLE_TOP_OFFSET;
    const entryY: number = this.statusBarHeight + SEARCH_ENTRY_TOP_OFFSET;
    let searchY: number = entryY;
    if (this.searchCompactTransitionVisible) {
      const progress: number = Math.max(0, Math.min(1, this.searchCompactTransitionProgress));
      searchY = this.searchCompactStartY + (titleY - SEARCH_COMPACT_HDS_TOP_CORRECTION -
        this.searchCompactStartY) * progress;
    } else if (this.searchTransitionVisible) {
      searchY = entryY + (titleY - entryY) * this.searchTransitionProgress;
    } else if (this.searchCollapseTransitionVisible) {
      searchY = entryY + (titleY - entryY) * this.searchCollapseProgress;
    } else if (this.searchActive || this.searchCollapsed || this.isEditing) {
      searchY = titleY;
    }
    return searchY + SEARCH_BAR_HEIGHT + SEARCH_BANNER_GAP;
  }

  /** 搜索期间只收起 Banner 外观；保留列表滚动状态供取消搜索时恢复。 */
  private isServerErrorBannerCompact(): boolean {
    return this.serverErrorBannerCollapsed || this.searchActive || this.searchTransitionVisible ||
      this.searchCompactTransitionVisible;
  }

  @Builder
  private serverErrorBannerContent() {
    Row() {
      Text(this.isServerErrorBannerCompact() ? '服务异常 · 点击修复' : this.serverErrorBanner)
        .fontSize(12)
        .fontColor($r('app.color.color_warning'))
        .maxLines(this.isServerErrorBannerCompact() ? 1 : 3)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(this.isServerErrorBannerCompact() ? 0 : 1)
    }
    // 展开态跟通知卡片对齐；收缩态仍按文字宽度显示胶囊。
    .width(this.isServerErrorBannerCompact() ? 'auto' : '100%')
    .constraintSize({ maxWidth: '100%' })
    .padding(this.isServerErrorBannerCompact()
      ? {
        left: 12,
        right: 12,
        top: 7,
        bottom: 7
      }
      : {
        left: 16,
        right: 16,
        top: 6,
        bottom: 6
      })
    .backgroundColor($r('app.color.color_bg_warning'))
    .borderRadius(this.isServerErrorBannerCompact() ? 20 : 12)
    .animation({ duration: 180, curve: Curve.EaseOut })
    .onAreaChange((_old: Area, area: Area) => {
      const height: number = area.height as number;
      if (height > 0 && height !== this.serverErrorBannerHeight) {
        this.serverErrorBannerHeight = height;
      }
    })
    .onClick(() => {
      this.openFixDialogForFirstError();
    });
  }

  @Builder
  serverErrorBannerView() {
    Row() {
      this.serverErrorBannerContent();
    }
    .width('100%')
    .padding({ left: 16, right: this.isServerErrorBannerCompact() ? 0 : 16 })
    // 降级态按搜索框底边避让；沉浸态在外层 Stack 单独定位。
    .margin({
      top: (this.searchActive && !this.searchCollapsed ? this.getFallbackActiveSearchInset() :
        Math.max(0, this.fallbackTitleBarBottom) +
        (this.isEditing ? 0 : SEARCH_BAR_GAP + SEARCH_BAR_HEIGHT + SEARCH_BAR_BOTTOM_GAP)) +
        (this.isEditing ? 0 : SEARCH_BANNER_GAP) +
        (this.isServerErrorBannerCompact() ? COMPACT_BANNER_TOP_GAP : 0)
    })
    .translate({ y: -(SEARCH_BAR_GAP + SEARCH_BAR_HEIGHT) * this.getBannerSearchCollapseProgress() -
      (this.searchCollapsed ? SEARCH_ACTIVE_BANNER_FALLBACK_LIFT : 0) *
      this.getBannerSearchActiveLiftProgress() })
  }

  @Builder
  private hdsServerErrorBannerView() {
    Row() {
      this.serverErrorBannerContent();
    }
    .width('100%')
    .padding({ left: 16, right: this.isServerErrorBannerCompact() ? 0 : 16 })
    .position({ x: 0, y: this.getHdsBannerTop() });
  }

  @Builder
  refreshContentBody() {
    // 降级布局的 Banner 浮于列表上层；HDS Banner 改在外层与搜索控件共用坐标。
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        if (this.syncProgressText.length > 0 || this.syncFeedbackText.length > 0) {
          this.syncProgressView();
        }
        this.refreshListContent();
      }
      .width('100%')
      .height('100%')
      // 分组搜索始终隐藏但保留底层 List；平铺模式仅在有关键词时隐藏原列表。
      .visibility(this.searchActive && (this.groupEnabled || this.searchQuery.trim().length > 0) ?
        Visibility.Hidden : Visibility.Visible);

      if (this.serverErrorBanner.length > 0 && !shouldUseSystemMaterialPath(this.immersiveLightEnabled)) {
        this.serverErrorBannerView();
      }

      if (this.searchActive || this.searchPreviewExiting) {
        this.searchPreview();
      }
    }
    .width('100%')
    .height('100%');
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

        // 右下角"跳到底部"浮动按钮：上滑离开首屏时出现，固定在分组按钮下方。
        if (this.shouldShowScrollToBottom()) {
          this.scrollToBottomFab();
        }

        // 右下角"分组/平铺"模式切换浮动按钮
        // 仅在非编辑模式、有消息时显示
        if (!this.searchActive && !this.isEditing && this.messages.length > 0) {
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

  build() {
    if (shouldUseSystemMaterialPath(this.immersiveLightEnabled)) {
      Stack({ alignContent: Alignment.TopStart }) {
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
            bottomBuilder: {
              builder: (): void => {
                if (!this.searchActive && !this.isEditing &&
                  (!this.searchCollapsed || this.searchCollapseTransitionVisible)) {
                  this.searchBottomBar();
                }
              },
              // 回顶的临时胶囊在 HDS 外层绘制；收缩态过渡不逐帧改变标题栏高度，
              // 否则高度反过来改变 Scroller 偏移，形成滚动与展开互相驱动的抖动。
              height: this.searchActive || this.isEditing || this.searchCollapsed ? 0 :
                this.searchCollapseTransitionVisible ?
                (SEARCH_BAR_HEIGHT + SEARCH_BAR_GAP) * (1 - this.searchCollapseProgress) :
                SEARCH_BAR_HEIGHT + SEARCH_BAR_GAP
            },
            menu: {
              maxCount: 3,
              value: this.searchActive || this.searchTransitionVisible || this.searchCompactTransitionVisible ? [] :
                this.searchCollapsed && !this.isEditing && !this.searchCollapseTransitionVisible ? [
                {
                  content: {
                    label: '多选',
                    type: TextStyleMode.NORMAL,
                    action: (): void => {
                      this.handleMultiSelectClicked();
                    }
                  }
                },
                {
                  content: {
                    icon: $r('app.media.trash'),
                    action: (): void => {
                      this.handleDeletePillClicked();
                    }
                  }
                },
                {
                  content: {
                    icon: $r('app.media.search'),
                    action: (): void => {
                      this.enterSearch();
                    }
                  }
                }
              ] : [
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
                    icon: $r('app.media.trash'),
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
          },
        })
        .hideBackButton(true)
        .titleMode(HdsNavigationTitleMode.MINI)
        .bindToScrollable([this.searchActive && !this.searchTransitioning ? this.searchScroller : this.scroller])
        .width('100%')
        .height('100%')
        .bindSheet(this.showDetail, this.detailBuilder(), {
          height: SheetSize.LARGE,
          preferType: SheetType.BOTTOM,
          // 标题与关闭按钮由 Sheet 内 HdsNavigation 的 MODAL 标题栏承载，以支持内容上滚时的动态模糊。
          showClose: false,
          enableFloatingDragBar: true,
          // 降级时减轻遮罩，让轻量模糊背板下的列表层次更可辨；正文 List 保持实色。
          maskColor: shouldUseLoadedMaterialStyle(this.immersiveLightEnabled, this.immersiveMaterialLoaded)
            ? undefined : '#33000000',
          backgroundColor: shouldUseLoadedMaterialStyle(this.immersiveLightEnabled, this.immersiveMaterialLoaded)
            ? Color.Transparent : $r('app.color.color_bg_sheet_blur'),
          blurStyle: shouldUseLoadedMaterialStyle(this.immersiveLightEnabled, this.immersiveMaterialLoaded)
            ? undefined : BlurStyle.COMPONENT_ULTRA_THIN,
          systemMaterial: getEnabledSystemMaterial('sheet', this.immersiveLightEnabled),
          onDisappear: () => {
            this.showDetail = false;
          }
        })
        .backgroundColor($r('app.color.color_bg_page'));

        if (this.serverErrorBanner.length > 0) {
          this.hdsServerErrorBannerView();
        }

        if (this.searchTransitionVisible) {
          this.searchTransitionBar();
        }
        if (this.searchCollapseTransitionVisible && !this.searchActive &&
          !this.searchTransitionVisible && !this.searchCompactTransitionVisible) {
          this.searchCollapseTransitionBar();
        }
        if (this.searchCompactTransitionVisible) {
          this.searchCompactTransitionBar();
        }

      }
      .width('100%')
      .height('100%')
      .onAreaChange((_old: Area, area: Area) => {
        const width: number = area.width as number;
        if (width > 0 && width !== this.searchViewportWidth) {
          this.searchViewportWidth = width;
        }
      });
    } else {
      Column() {
        Stack({ alignContent: Alignment.BottomEnd }) {
          Stack({ alignContent: Alignment.Top }) {
            this.refreshContentBody();
            this.fallbackTitleBar();
            if (this.searchActive) {
              // 降级搜索态隐藏了普通标题栏，补上不透出列表文字的标题区背板。
              Row()
                .width('100%')
                .height(this.statusBarHeight + 13 + SEARCH_BAR_HEIGHT + SEARCH_BAR_GAP)
                .backgroundColor($r('app.color.color_bg_page'))
                .hitTestBehavior(HitTestMode.None)
                .zIndex(1);
            }
            if (!this.isEditing && (!this.searchCollapsed || this.searchActive ||
              this.searchCollapseTransitionVisible)) {
              this.searchBar();
            }
          }
          .width('100%')
          .height('100%')

          if (this.searchCollapseTransitionVisible && !this.searchActive &&
            !this.searchTransitionVisible && !this.searchCompactTransitionVisible) {
            this.searchCollapseTransitionBar();
          }
          if (this.searchCompactTransitionVisible) {
            this.searchCompactTransitionBar();
          }

          // 非沉浸式分支的右下角「跳到底部」按钮
          if (this.shouldShowScrollToBottom()) {
            this.scrollToBottomFab();
          }

          // 非沉浸式分支的右下角分组模式切换按钮
          if (!this.searchActive && !this.isEditing && this.messages.length > 0) {
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
      .onAreaChange((_old: Area, area: Area) => {
        const width: number = area.width as number;
        if (width > 0 && width !== this.searchViewportWidth) {
          this.searchViewportWidth = width;
        }
      })
      .bindSheet(this.showDetail, this.detailBuilder(), {
        height: SheetSize.LARGE,
        preferType: SheetType.BOTTOM,
        // 标题与关闭按钮由 Sheet 内 HdsNavigation 的 MODAL 标题栏承载，以支持内容上滚时的动态模糊。
        showClose: false,
        enableFloatingDragBar: true,
        // 两种导航布局共用同一降级效果。
        maskColor: shouldUseLoadedMaterialStyle(this.immersiveLightEnabled, this.immersiveMaterialLoaded)
          ? undefined : '#33000000',
        backgroundColor: shouldUseLoadedMaterialStyle(this.immersiveLightEnabled, this.immersiveMaterialLoaded)
          ? Color.Transparent : $r('app.color.color_bg_sheet_blur'),
        blurStyle: shouldUseLoadedMaterialStyle(this.immersiveLightEnabled, this.immersiveMaterialLoaded)
          ? undefined : BlurStyle.COMPONENT_ULTRA_THIN,
        systemMaterial: getEnabledSystemMaterial('sheet', this.immersiveLightEnabled),
        onDisappear: () => {
          this.showDetail = false;
        }
      })
      .backgroundColor($r('app.color.color_bg_page'));
    }
  }

  @Builder
  refreshHeaderBuilder() {
    NotifyRefreshHeader({
      refreshState: this.refreshState,
      topInset: this.getListTopInset()
    });
  }

  @Builder
  listView() {
    NotifyMessageList({
      messages: this.messages,
      isEditing: this.isEditing,
      selectedIds: this.selectedIds,
      expandedGroups: this.expandedGroups,
      groupCardHeights: this.groupCardHeights,
      groupTotals: this.groupTotals,
      selectedGroupCounts: this.selectedGroupCounts,
      groupLoadingMore: this.groupLoadingMore,
      groupEnabled: this.groupEnabled,
      flatHasMore: !this.groupEnabled && this.totalCachedCount > this.messages.length,
      flatLoadingMore: this.flatLoadingMore,
      statusBarHeight: this.statusBarHeight,
      navBarHeight: this.navBarHeight,
      topInset: this.getListTopInset(),
      immersiveLightEnabled: this.immersiveLightEnabled,
      listScroller: this.scroller,
      scrollToBottomSignal: this.scrollToBottomSignal,
      onListTopChange: (top: number) => {
        // 下拉刷新会暂时移动列表；只记录静止时的布局起点，避免占位随手势抖动。
        if (!this.refreshing && this.refreshState === RefreshStatus.Inactive && top !== this.listTop) {
          this.listTop = top;
        }
      },
      onListScroll: (scrollOffset: number, scrollState: ScrollState) =>
      this.handleListScroll(scrollOffset, scrollState),
      onListScrollStart: () => this.handleSearchScrollStart(),
      onListTouchDown: () => {
        this.bottomButtonUserTouchStarted = true;
      },
      onListScrollStop: () => this.handleSearchScrollStop(),
      onListReachStart: () => {
        this.finishSearchExpandAtTop();
        if (this.showScrollToBottom) {
          this.showScrollToBottom = false;
        }
        this.setServerErrorBannerCollapsed(false);
      },
      onListReachEnd: () => {
        if (this.showScrollToBottom) {
          this.showScrollToBottom = false;
        }
      },
      onAutoScrollEnd: () => {
        this.handleAutoScrollEnd();
      },
      onLoadMoreInGroup: (groupKey: string) => this.loadMoreInGroup(groupKey),
      onLoadMoreFlat: () => this.loadMoreFlat(),
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
      onOpenUrl: (url: string) => this.openUrl(url),
      onCopyCode: (code: string) => this.copyCode(code),
      onCopyUrl: (url: string) => this.copyUrl(url)
    });
  }

  // 多选模式底部操作栏（需要加在 Refresh 外面）
  @Builder
  editActionBar() {
    NotifyEditActionBar({
      selectedCount: this.selectedIds.length,
      messageCount: this.totalCachedCount,
      exporting: this.exportingSelected,
      navBarHeight: this.navBarHeight,
      immersiveLightEnabled: this.immersiveLightEnabled,
      onCancel: () => this.exitEditMode(),
      onToggleAll: () => this.toggleAllSelection(),
      onExport: () => this.handleExportSelected(),
      onDelete: () => this.handleDeleteSelected()
    });
  }

  /** 详情正文；沉浸/降级两种 MODAL 标题栏样式共用同一内容。 */
  @Builder
  detailContent() {
    NotifyMessageDetail({
      message: this.selectedMessage,
      useImmersiveMaterial: shouldUseLoadedMaterialStyle(this.immersiveLightEnabled, this.immersiveMaterialLoaded),
      detailScroller: this.detailScroller,
      onOpenUrl: (url: string) => {
        this.openUrl(url);
      },
      onCopyCode: (code: string) => {
        this.copyCode(code);
      },
      onCopyUrl: (url: string) => {
        this.copyUrl(url);
      },
      onCopyText: (text: string, label: string) => {
        this.copyText(text, label);
      },
      onCopyContent: (text: string) => {
        this.copyContent(text);
      },
      onDelete: () => {
        if (this.selectedMessage) {
          this.confirmDeleteOne(this.selectedMessage, true);
        }
      }
    });
  }

  // ====== 各弹窗打开方法（复用组件，指定目标服务器） ======

  /**
   * 详情 Sheet 内容：HdsNavigation 使用 MODAL（半模态）标题栏承载标题与关闭按钮，
   * bindToScrollable 绑定内部 List 后，内容上滚穿入标题栏区域即呈现动态模糊。
   * 沉浸分支：渐变模糊 + 自适应系统材质；降级分支：通用模糊背板。
   */
  @Builder
  detailBuilder() {
    if (shouldUseLoadedMaterialStyle(this.immersiveLightEnabled, this.immersiveMaterialLoaded)) {
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
   * 切换视图模式（全部 / 单服务器）。
   * 通过 ServerManager 统一管理，onChange 回调会处理列表刷新。
   */
  setViewAll(viewAll: boolean): void {
    ServerManager.getInstance().setViewAllMode(viewAll);
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
    this.serverErrorBannerCollapsed = (this.getListYOffset() ?? 0) > 0;
  }

  /** 搜索结果在降级布局中从页面顶端绘制，首项按输入框实测底边避让。 */
  private getSearchPreviewTopInset(): number {
    if (shouldUseSystemMaterialPath(this.immersiveLightEnabled)) {
      return 16;
    }
    const searchBottom: number = this.fallbackSearchBarBottom >= 0 ? this.fallbackSearchBarBottom :
      this.statusBarHeight + 13 + SEARCH_BAR_HEIGHT;
    return Math.max(16, searchBottom + SEARCH_BAR_GAP);
  }

  /** 降级搜索态按搜索栏底边计算避让，避免继续沿用隐藏标题栏的高度。 */
  private getFallbackActiveSearchInset(): number {
    // 搜索态的普通标题栏不可见，优先使用搜索框实测底边；首次布局前使用相同的目标位置。
    const searchBottom: number = this.fallbackSearchBarBottom >= 0 ? this.fallbackSearchBarBottom :
      this.statusBarHeight + 13 + SEARCH_BAR_HEIGHT;
    return Math.max(0, searchBottom - Math.max(0, this.listTop)) + SEARCH_BAR_GAP;
  }

  /** Banner 覆盖列表时，为首项和下拉刷新指示器预留实际遮挡高度。 */
  private getListTopInset(): number {
    const fallbackActiveSearch: boolean = this.searchActive &&
      !shouldUseSystemMaterialPath(this.immersiveLightEnabled);
    const titleInset: number = fallbackActiveSearch ? this.getFallbackActiveSearchInset() :
      this.fallbackTitleBarBottom >= 0 && this.listTop >= 0
      ? Math.max(0, this.fallbackTitleBarBottom - this.listTop) : 0;
    const searchInset: number = fallbackActiveSearch || this.isEditing ||
      shouldUseSystemMaterialPath(this.immersiveLightEnabled) ? 0 :
      SEARCH_BAR_GAP + SEARCH_BAR_HEIGHT + SEARCH_BAR_BOTTOM_GAP;
    if (this.serverErrorBanner.length === 0) {
      return titleInset + searchInset;
    }
    const compact: boolean = this.isServerErrorBannerCompact();
    const bannerHeight: number = compact ? 32 : Math.max(this.serverErrorBannerHeight, 44);
    return titleInset + searchInset + bannerHeight +
      (!shouldUseSystemMaterialPath(this.immersiveLightEnabled) && !this.isEditing ? SEARCH_BANNER_GAP : 0) +
      (compact ? COMPACT_BANNER_TOP_GAP : 0);
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

  private openClientTokenDialogFor(server: ServerEntry): void {
    try {
      // 背板与「服务器操作」「切换通知服务」弹窗统一：API 26+ 且开关开启即传 THICK 材质，
      // 不以设备 supported 结果拦截，材质分支透明；旧系统或开关关闭走系统容器轻量模糊。
      const dialogMaterial = getDialogMaterial(this.immersiveLightEnabled);
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
        systemMaterial: dialogMaterial,
        backgroundColor: dialogMaterial ? Color.Transparent : undefined,
        backgroundBlurStyle: dialogMaterial ? undefined : BlurStyle.COMPONENT_ULTRA_THIN,
      });
      this.fixClientTokenController.open();
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'client token dialog open 失败');
    }
  }

  private openKeyDialogFor(server: ServerEntry): void {
    try {
      // 背板与「服务器操作」「切换通知服务」弹窗统一：API 26+ 且开关开启即传 THICK 材质，
      // 不以设备 supported 结果拦截，材质分支透明；旧系统或开关关闭走系统容器轻量模糊。
      const dialogMaterial = getDialogMaterial(this.immersiveLightEnabled);
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
        systemMaterial: dialogMaterial,
        backgroundColor: dialogMaterial ? Color.Transparent : undefined,
        backgroundBlurStyle: dialogMaterial ? undefined : BlurStyle.COMPONENT_ULTRA_THIN,
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
      // 与 Sheet 一致：API 26+ 且用户开启时传材质，不以设备 supported 结果拦截。
      const dialogMaterial = getDialogMaterial(this.immersiveLightEnabled);
      const host: string = extractHost(server.baseURL);
      const name: string = server.name.trim();
      this.fixActionMenuController = new CustomDialogController({
        builder: ServerActionMenuDialog({
          serverLabel: name.length > 0 && name !== host ? `${name} · ${host}` : host,
          onCopy: () => {
            this.handleCopyServer(server);
          },
          onResetKey: () => {
            this.openKeyDialogFor(server);
          },
          onClientToken: () => {
            this.openClientTokenDialogFor(server);
          },
          onEncryption: () => {
            this.openEncryptionDialogFor(server);
          },
          onRename: () => {
            this.openRenameDialogFor(server);
          },
          onDelete: () => {
            this.confirmDeleteServer(server);
          },
        }),
        alignment: DialogAlignment.Center,
        autoCancel: true,
        offset: { dx: 0, dy: 0 },
        cornerRadius: 14,
        systemMaterial: dialogMaterial,
        backgroundColor: dialogMaterial ? Color.Transparent : undefined,
        backgroundBlurStyle: dialogMaterial ? undefined : BlurStyle.COMPONENT_ULTRA_THIN,
      });
      this.fixActionMenuController.open();
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'action menu open 失败');
    }
  }

  private findConfiguredServer(id: string): ServerEntry | null {
    const server: ServerEntry | undefined = ServerManager.getInstance().getList()
      .find((item: ServerEntry) => item.id === id);
    return server ?? null;
  }

  private async openEncryptionDialogFor(server: ServerEntry): Promise<void> {
    const target: ServerEntry | null = this.findConfiguredServer(server.id);
    if (!target) {
      showToast(this.getUIContext(), '服务器信息缺失');
      return;
    }
    try {
      const dialogMaterial = getDialogMaterial(this.immersiveLightEnabled);
      this.fixEncryptionController = new CustomDialogController({
        builder: DecryptionSettingsDialog({
          serverLabel: target.name || target.baseURL,
          loadConfig: (): Promise<EncryptionConfig> => EncryptionConfigService.get(null, target.id),
          onSave: (config: EncryptionConfig): Promise<boolean> => this.saveEncryptionFor(target.id, config),
          onClear: (): Promise<boolean> => this.clearEncryptionFor(target.id),
        }),
        alignment: DialogAlignment.Center,
        autoCancel: true,
        offset: { dx: 0, dy: 0 },
        cornerRadius: 14,
        systemMaterial: dialogMaterial,
        backgroundColor: dialogMaterial ? Color.Transparent : undefined,
        backgroundBlurStyle: dialogMaterial ? undefined : BlurStyle.COMPONENT_ULTRA_THIN,
      });
      this.fixEncryptionController.open();
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'encryption dialog open 失败：%{public}s',
        err instanceof Error ? err.message : String(err));
      showToast(this.getUIContext(), '弹窗无法打开');
    }
  }

  private async saveEncryptionFor(serverId: string, config: EncryptionConfig): Promise<boolean> {
    const server: ServerEntry | null = this.findConfiguredServer(serverId);
    if (!server) {
      showToast(this.getUIContext(), '服务器信息缺失');
      return false;
    }
    config.deviceKey = server.deviceKey;
    try {
      const ok: boolean = await EncryptionConfigService.save(null, serverId, config);
      if (ok) {
        try {
          await NotifyMessageService.getInstance().redecryptCachedMessages(server);
        } catch (err) {
          hilog.warn(DOMAIN, TAG, 'redecrypt cached messages 失败：%{public}s',
            err instanceof Error ? err.message : String(err));
        }
        try {
          NotifySyncService.getInstance().retryServer(serverId);
          this.loadMessages();
        } catch (err) {
          hilog.warn(DOMAIN, TAG, '保存后刷新通知失败：%{public}s',
            err instanceof Error ? err.message : String(err));
        }
      }
      showToast(this.getUIContext(), ok ? '解密设置已保存' : '保存失败');
      return ok;
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'save encryption 失败：%{public}s',
        err instanceof Error ? err.message : String(err));
      showToast(this.getUIContext(), '保存失败');
      return false;
    }
  }

  private async clearEncryptionFor(serverId: string): Promise<boolean> {
    const server: ServerEntry | null = this.findConfiguredServer(serverId);
    if (!server) {
      showToast(this.getUIContext(), '服务器信息缺失');
      return false;
    }
    try {
      const ok: boolean = await EncryptionConfigService.remove(null, serverId);
      if (ok) {
        try {
          await NotifyMessageService.getInstance().redecryptCachedMessages(server);
        } catch (err) {
          hilog.warn(DOMAIN, TAG, 'redecrypt cached messages 失败：%{public}s',
            err instanceof Error ? err.message : String(err));
        }
        try {
          NotifySyncService.getInstance().retryServer(serverId);
          this.loadMessages();
        } catch (err) {
          hilog.warn(DOMAIN, TAG, '清除后刷新通知失败：%{public}s',
            err instanceof Error ? err.message : String(err));
        }
      }
      showToast(this.getUIContext(), ok ? '解密设置已清除' : '清除失败');
      return ok;
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'clear encryption 失败：%{public}s',
        err instanceof Error ? err.message : String(err));
      showToast(this.getUIContext(), '清除失败');
      return false;
    }
  }

  private openRenameDialogFor(server: ServerEntry): void {
    const target: ServerEntry | null = this.findConfiguredServer(server.id);
    if (!target) {
      showToast(this.getUIContext(), '服务器信息缺失');
      return;
    }
    try {
      // 背板与「服务器操作」「切换通知服务」弹窗统一：API 26+ 且开关开启即传 THICK 材质，
      // 不以设备 supported 结果拦截，材质分支透明；旧系统或开关关闭走系统容器轻量模糊。
      const dialogMaterial = getDialogMaterial(this.immersiveLightEnabled);
      this.fixRenameController = new CustomDialogController({
        builder: ServerRenameDialog({
          getInitName: (): string => this.findConfiguredServer(server.id)?.name ?? '',
          serverDomain: extractHost(target.baseURL),
          onConfirm: (name: string): void => {
            this.renameServerFor(server.id, name);
          },
        }),
        alignment: DialogAlignment.Center,
        autoCancel: true,
        offset: { dx: 0, dy: 0 },
        cornerRadius: 14,
        systemMaterial: dialogMaterial,
        backgroundColor: dialogMaterial ? Color.Transparent : undefined,
        backgroundBlurStyle: dialogMaterial ? undefined : BlurStyle.COMPONENT_ULTRA_THIN,
      });
      this.fixRenameController.open();
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'rename dialog open 失败：%{public}s',
        err instanceof Error ? err.message : String(err));
      showToast(this.getUIContext(), '弹窗无法打开');
    }
  }

  private async renameServerFor(serverId: string, name: string): Promise<void> {
    if (!this.findConfiguredServer(serverId)) {
      showToast(this.getUIContext(), '服务器信息缺失');
      return;
    }
    try {
      const ok: boolean = await ServerManager.getInstance().renameServer(null, serverId, name);
      showToast(this.getUIContext(), ok ? '已重命名' : '重命名失败');
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'rename server 失败：%{public}s',
        err instanceof Error ? err.message : String(err));
      showToast(this.getUIContext(), '重命名失败');
    }
  }

  private async confirmDeleteServer(server: ServerEntry): Promise<void> {
    const manager: ServerManager = ServerManager.getInstance();
    if (!this.findConfiguredServer(server.id)) {
      showToast(this.getUIContext(), '服务器信息缺失');
      return;
    }
    if (manager.getList().length <= 1) {
      showToast(this.getUIContext(), '至少保留一个服务器');
      return;
    }
    try {
      if (!await this.confirmDanger('删除服务器', `确定删除「${server.name || server.baseURL}」吗？`, '确定')) {
        return;
      }
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'delete server dialog 失败：%{public}s',
        err instanceof Error ? err.message : String(err));
      return;
    }
    try {
      const ok: boolean = await manager.deleteServer(null, server.id);
      if (ok) {
        try {
          await EncryptionConfigService.remove(null, server.id);
        } catch (err) {
          hilog.warn(DOMAIN, TAG, 'delete server encryption config 失败：%{public}s',
            err instanceof Error ? err.message : String(err));
        }
      }
      showToast(this.getUIContext(), ok ? '已删除' : '删除失败', ok ? 1200 : undefined);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'delete server 失败：%{public}s',
        err instanceof Error ? err.message : String(err));
      showToast(this.getUIContext(), '删除失败');
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

  /** 大批量历史迁移时给出已处理数量，不宣称总数或删除成功数。 */
  @Builder
  private syncProgressView() {
    Text(this.syncProgressText.length > 0 ? this.syncProgressText : this.syncFeedbackText)
      .fontSize(12)
      .fontColor($r('app.color.color_text_secondary'))
      .padding({
        left: 16,
        right: 16,
        top: 6,
        bottom: 6
      })
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
        NotifyContentState({ mode: 'error', errorMsg: this.errorMsg, onRetry: () => this.loadMessages(true) });
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
      this.loadMessages(true);
    });
  }

  /**
   * 右下角分组模式切换按钮：
   * - 当前分组模式：显示 group_expand 图标，点击切为平铺
   * - 当前平铺模式：显示 group_collapse 图标，点击切为分组
   */
  @Builder
  private groupModeToggleFab() {
    Toggle({ type: ToggleType.Button, isOn: this.groupEnabled }) {
      Row() {
        Image(this.groupEnabled ? $r('app.media.group_expand') : $r('app.media.group_collapse'))
          .width(20)
          .height(20)
          .objectFit(ImageFit.Contain)
          .fillColor($r('app.color.color_text_primary'))
          .draggable(false);
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center);
    }
    .width(44)
    .height(44)
    .borderRadius(22)
    .selectedColor(Color.Transparent)
    .attributeModifier(IMMERSIVE_GROUP_TOGGLE_MODIFIER)
    // 分组切换固定在上方，与下方 44vp 的跳底按钮间隔 12vp；跳底隐藏时也不移动。
    .margin({ right: 16, bottom: this.navBarHeight + 72 + 44 + 12 })
    .onChange((isOn: boolean) => {
      if (this.groupEnabled === isOn || this.groupSwitchTimer >= 0) {
        return;
      }
      this.groupSwitchTimer = setTimeout(() => {
        this.groupSwitchTimer = -1;
        if (this.groupEnabled !== isOn) {
          this.toggleGroupEnabled();
        }
      }, 0);
    });
  }

  /**
   * 右下角「跳到底部」浮动按钮：位于分组模式按钮下方，使用 select_more（向下箭头）图标。
   * 触发条件：上滑离开首屏时出现；下滑或回到首屏时隐藏。
   * 通过 if 条件渲染 + transition 实现淡入淡出 + 轻微上移的丝滑过渡。
   */
  @Builder
  private scrollToBottomFab() {
    Toggle({ type: ToggleType.Button, isOn: false }) {
      Row() {
        Image($r('app.media.select_more'))
          .width(20)
          .height(20)
          .objectFit(ImageFit.Contain)
          .fillColor($r('app.color.color_text_primary'))
          .draggable(false);
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center);
    }
    .width(44)
    .height(44)
    .borderRadius(22)
    .selectedColor(Color.Transparent)
    .attributeModifier(IMMERSIVE_GROUP_TOGGLE_MODIFIER)
    // 普通与搜索列表均使用下方固定位置，不随分组按钮显隐而移动。
    .margin({ right: 16, bottom: this.navBarHeight + 72 })
    .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 16 }))
      .animation({ duration: 220, curve: Curve.EaseOut }))
    .onChange((isOn: boolean) => {
      if (!isOn || this.isCurrentListAutoScrolling() || this.scrollToBottomTimer >= 0) {
        return;
      }
      this.scrollToBottomTimer = setTimeout(() => {
        this.scrollToBottomTimer = -1;
        if (this.shouldShowScrollToBottom() && !this.isCurrentListAutoScrolling()) {
          this.scrollToBottom();
        }
      }, 0);
    });
  }

  /**
   * 处理列表滚动事件，控制「跳到底部」按钮显隐。
   * - scrollOffset > 0：列表向上滚动（手指上滑），离开首屏后显示按钮；
   * - scrollOffset < 0：列表向下滚动（手指下滑），隐藏按钮；
   * - 在首屏（yOffset <= 0）或已到达底部：隐藏按钮。
   * 忽略 Idle 状态，避免静止时重复触发。
   * 「跳到底部」程序滚动期间整体屏蔽，否则动画产生的正向滚动会让按钮中途重现闪烁。
   */
  private handleListScroll(scrollOffset: number, scrollState: ScrollState): void {
    if (this.isSearchPreviewVisible()) {
      return;
    }
    if (scrollOffset < -0.5) {
      this.searchMovingTowardTop = true;
    } else if (scrollOffset > 0.5) {
      this.searchMovingTowardTop = false;
    }
    this.updateSearchCollapsedFromOffset();
    if (this.isAutoScrolling || scrollState === ScrollState.Idle) {
      return;
    }
    const offset = this.getListYOffset();
    if (offset === undefined) {
      return;
    }
    // 分页追加后，继续向旧消息方向滚动也会离开原来的底部；不能只允许反向滚动解除屏蔽。
    // 仍要求真实触摸、有效位移且已离开当前底部，避免自动贴底后的回弹重新显示按钮。
    const atEnd: boolean = this.scroller.isAtEnd();
    if (this.suppressBottomButtonUntilUserScroll && this.bottomButtonUserTouchStarted &&
      !atEnd && Math.abs(scrollOffset) > 0.5) {
      this.suppressBottomButtonUntilUserScroll = false;
      this.bottomButtonUserTouchStarted = false;
    }
    const atTop: boolean = offset <= 0;
    if (atTop) {
      if (this.showScrollToBottom) {
        this.showScrollToBottom = false;
      }
      this.setServerErrorBannerCollapsed(false);
      return;
    }
    if (atEnd) {
      if (this.showScrollToBottom) {
        this.showScrollToBottom = false;
      }
      return;
    }
    if (this.suppressBottomButtonUntilUserScroll) {
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

  /** 列表重建期间 Scroller 可能暂时解绑，此时 currentOffset() 没有返回值。 */
  private getListYOffset(): number | undefined {
    return this.scroller.currentOffset()?.yOffset;
  }

  /** 滚动偏移驱动回顶展开；离顶收缩仍沿用原动画。 */
  private updateSearchCollapsedFromOffset(): void {
    if (this.searchActive || this.isEditing || this.searchTransitioning ||
      this.searchCollapseTransitioning || this.messages.length === 0) {
      return;
    }
    const currentOffset = this.getListYOffset();
    if (currentOffset === undefined) {
      return;
    }
    const offset: number = Math.max(0, currentOffset);
    if (this.searchCollapsed && offset <= SEARCH_EXPAND_OFFSET) {
      this.finishSearchExpandAtTop();
      return;
    }
    if (this.searchCollapsed && (this.searchMovingTowardTop || this.searchCollapseTransitionVisible) &&
      offset < SEARCH_EXPAND_RANGE) {
      const ratio: number = offset / SEARCH_EXPAND_RANGE;
      // 平滑插值避免进入/离开采样区间时速度突变；不启动额外的定时动画。
      const progress: number = ratio * ratio * (3 - 2 * ratio);
      if (!this.searchCollapseTransitionVisible) {
        this.searchCollapseTransitionVisible = true;
      }
      this.searchCollapseProgress = progress;
      return;
    }
    if (this.searchCollapsed && this.searchCollapseTransitionVisible) {
      this.searchCollapseTransitionVisible = false;
      this.searchCollapseProgress = 1;
    }
    if (!this.searchCollapsed && offset >= SEARCH_COLLAPSE_OFFSET) {
      this.setSearchCollapsed(true);
    }
  }

  /** 系统回顶与手势滚动共用实际偏移采样，不再按事件来源猜测动画时序。 */
  private handleSearchScrollStart(): void {
    this.startSearchScrollSampling();
  }

  /** 滚动停止只停止采样；半途位置不强制缩回。 */
  private handleSearchScrollStop(): void {
    this.stopSearchScrollSampling();
  }

  /** 从 List 的滚动开始事件持续采样；系统回顶缺少逐帧回调时也能在到顶前展开。 */
  private startSearchScrollSampling(): void {
    if (this.searchScrollSampleTimer >= 0 || this.searchActive || this.isEditing ||
      this.searchTransitioning || this.searchCollapseTransitioning ||
      this.messages.length === 0) {
      return;
    }
    const initialOffset = this.getListYOffset();
    if (initialOffset === undefined) {
      return;
    }
    this.searchScrollLastOffset = initialOffset;
    this.searchScrollIdleSamples = 0;
    this.searchScrollSampleTimer = setInterval(() => {
      const offset = this.getListYOffset();
      if (offset === undefined || this.searchActive || this.isEditing || this.messages.length === 0) {
        this.stopSearchScrollSampling();
        return;
      }
      if (offset < this.searchScrollLastOffset - 0.5) {
        this.searchMovingTowardTop = true;
      } else if (offset > this.searchScrollLastOffset + 0.5) {
        this.searchMovingTowardTop = false;
      }
      this.updateSearchCollapsedFromOffset();
      // onScrollIndex 也可能由数据更新触发；长时间无位移时释放兜底采样器。
      this.searchScrollIdleSamples = Math.abs(offset - this.searchScrollLastOffset) < 0.5 ?
        this.searchScrollIdleSamples + 1 : 0;
      this.searchScrollLastOffset = offset;
      if (offset <= SEARCH_EXPAND_OFFSET || this.searchScrollIdleSamples >= 120) {
        this.stopSearchScrollSampling();
      }
    }, SEARCH_SCROLL_SAMPLE_MS);
  }

  /** 停止采样；只有真正到顶才交接完整搜索栏，半途保留过渡胶囊。 */
  private stopSearchScrollSampling(): void {
    if (this.searchScrollSampleTimer >= 0) {
      clearInterval(this.searchScrollSampleTimer);
      this.searchScrollSampleTimer = -1;
    }
    const offset = this.getListYOffset();
    if (offset !== undefined && offset <= SEARCH_EXPAND_OFFSET) {
      this.finishSearchExpandAtTop();
    }
    this.searchMovingTowardTop = false;
  }

  /** 到顶时直接完成临时胶囊与 HDS 搜索栏的交接，不再额外播放 240ms 展开。 */
  private finishSearchExpandAtTop(): void {
    if (!this.searchCollapsed || this.searchActive || this.isEditing || this.searchTransitioning ||
      this.searchCollapseTransitioning) {
      return;
    }
    this.searchCollapseProgress = 0;
    this.searchMovingTowardTop = false;
    this.searchCollapsed = false;
    this.searchCollapseTransitionVisible = false;
  }

  /** 离顶收缩动画；回顶展开改由滚动位置连续驱动。 */
  private setSearchCollapsed(collapsed: boolean): void {
    if (this.searchCollapsed === collapsed || this.searchActive || this.isEditing ||
      this.searchCollapseTransitioning) {
      return;
    }
    this.searchCollapseTransitioning = true;
    this.searchCollapseProgress = collapsed ? 0 : 1;
    this.searchCollapseTransitionVisible = true;
    this.getUIContext().animateTo({ duration: SEARCH_TRANSITION_DURATION, curve: Curve.EaseInOut }, () => {
      this.searchCollapseProgress = collapsed ? 1 : 0;
    });
    setTimeout(() => {
      this.searchCollapsed = collapsed;
      // 收缩动画改变标题栏高度产生的偏移不能被误判成用户正在回顶。
      if (collapsed) {
        this.searchMovingTowardTop = false;
      }
      this.searchCollapseTransitionVisible = false;
      this.searchCollapseTransitioning = false;
      this.updateSearchCollapsedFromOffset();
      if (this.pendingSearchAfterCollapse) {
        this.pendingSearchAfterCollapse = false;
        this.enterSearch();
      }
    }, SEARCH_TRANSITION_DURATION);
  }

  /**
   * 点击「跳到底部」按钮：隐藏按钮并置位自动滚动标记，通过信号交给列表执行两段式定位：
   * 短距离直接 smooth 滚动到末项；长距离先无动画瞬跳到末段附近，再短程 smooth 收尾。
   * 滚动结束（onScrollStop）后列表回调 onAutoScrollEnd 解除屏蔽。
   */
  private scrollToBottom(): void {
    if (this.isSearchPreviewVisible()) {
      this.scrollSearchToBottom();
      return;
    }
    this.showScrollToBottom = false;
    this.suppressBottomButtonUntilUserScroll = true;
    this.bottomButtonUserTouchStarted = false;
    this.isAutoScrolling = true;
    this.scrollToBottomSignal++;
  }

  /** 空关键词的平铺模式仍展示原列表；分组预览及有关键词的结果使用独立搜索层。 */
  private isSearchPreviewVisible(): boolean {
    return this.searchActive && (this.groupEnabled || this.searchQuery.trim().length > 0);
  }

  /** 搜索预览和命中结果共用按钮，空结果不沿用底层普通列表的按钮。 */
  private shouldShowScrollToBottom(): boolean {
    if (this.isEditing) {
      return false;
    }
    return this.isSearchPreviewVisible()
      ? this.showSearchScrollToBottom && this.getSearchMessageCount() > 0
      : this.showScrollToBottom && this.messages.length > 0;
  }

  /** 只检查当前可见列表的自动滚动，另一层的历史状态不拦截点击。 */
  private isCurrentListAutoScrolling(): boolean {
    return this.isSearchPreviewVisible() ? this.searchAutoScrollTarget >= 0 : this.isAutoScrolling;
  }

  /** 空词预览和关键词结果都由独立分页持有，只统计当前已加载的搜索层消息。 */
  private getSearchMessageCount(): number {
    return this.searchResults.length;
  }

  /** 搜索按钮沿用普通列表的方向规则，并允许分页后继续正向滚动解除贴底屏蔽。 */
  private handleSearchResultScroll(scrollOffset: number, scrollState: ScrollState): void {
    if (!this.isSearchPreviewVisible() || this.searchAutoScrollTarget >= 0 || scrollState === ScrollState.Idle) {
      return;
    }
    const offset: number | undefined = this.searchScroller.currentOffset()?.yOffset;
    if (offset === undefined) {
      return;
    }
    const atEnd: boolean = this.searchScroller.isAtEnd();
    if (this.suppressSearchBottomUntilUserScroll && this.searchBottomUserTouchStarted &&
      !atEnd && Math.abs(scrollOffset) > 0.5) {
      this.suppressSearchBottomUntilUserScroll = false;
      this.searchBottomUserTouchStarted = false;
    }
    if (offset <= 0 || atEnd) {
      this.showSearchScrollToBottom = false;
      return;
    }
    if (!this.suppressSearchBottomUntilUserScroll) {
      if (scrollOffset > 0) {
        this.showSearchScrollToBottom = true;
      } else if (scrollOffset < 0) {
        this.showSearchScrollToBottom = false;
      }
    }
  }

  /** 定位搜索 List 的底部占位项；空词与关键词列表均含一项顶部占位和分页提示。 */
  private scrollSearchToBottom(): void {
    const count: number = this.getSearchMessageCount();
    if (!this.searchPreviewMounted || count === 0) {
      return;
    }
    this.showSearchScrollToBottom = false;
    this.suppressSearchBottomUntilUserScroll = true;
    this.searchBottomUserTouchStarted = false;
    this.searchAutoScrollTarget = count + 2;
    // 无位移或布局中断时 stop 可能不触发；超时仅收尾状态，不再发起新的滚动。
    this.searchAutoScrollTimeout = setTimeout(() => this.finishSearchAutoScroll(), 1200);
    if (this.searchAutoScrollTarget - this.searchVisibleEndIndex <= SEARCH_BOTTOM_SMOOTH_RANGE) {
      this.startSearchBottomSmoothing();
    } else {
      this.searchScroller.scrollToIndex(this.searchAutoScrollTarget - SEARCH_BOTTOM_SMOOTH_RANGE,
        false, ScrollAlign.END);
    }
  }

  /** 长距离瞬跳到位后只平滑滚动末段，最后按底部占位项精确对齐。 */
  private startSearchBottomSmoothing(): void {
    this.searchAutoScrollSmoothing = true;
    this.searchScroller.scrollToIndex(this.searchAutoScrollTarget, true, ScrollAlign.END);
  }

  /** 用户触摸、结果变化或动画结束时，释放搜索自动滚动状态与兜底定时器。 */
  private finishSearchAutoScroll(): void {
    this.searchAutoScrollTarget = -1;
    this.searchAutoScrollSmoothing = false;
    if (this.searchAutoScrollTimeout >= 0) {
      clearTimeout(this.searchAutoScrollTimeout);
      this.searchAutoScrollTimeout = -1;
    }
  }

  /** 更换搜索内容或退出时清理旧按钮状态，防止旧回调滚动新结果或底层列表。 */
  private resetSearchBottomButton(): void {
    this.finishSearchAutoScroll();
    this.showSearchScrollToBottom = false;
    this.searchVisibleEndIndex = 0;
    this.suppressSearchBottomUntilUserScroll = false;
    this.searchBottomUserTouchStarted = false;
    if (this.scrollToBottomTimer >= 0) {
      clearTimeout(this.scrollToBottomTimer);
      this.scrollToBottomTimer = -1;
    }
  }

  /** 列表自动定位滚动结束（或用户手指滚动停止）回调：解除自动滚动屏蔽。 */
  private handleAutoScrollEnd(): void {
    this.isAutoScrolling = false;
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

  /** 切换当前列表的全选状态，供多选底栏回调使用。全选覆盖所有本地缓存消息，不受内存加载数量限制。 */
  private async toggleAllSelection(): Promise<void> {
    // 已选中全部缓存消息时取消全选
    if (this.selectedIds.length >= this.totalCachedCount && this.totalCachedCount > 0) {
      this.selectedIds = [];
      return;
    }
    // 从本地缓存查询所有消息身份，确保全选覆盖未加载到内存的历史消息
    const keys: string[] = this.getVisibleHistoryKeys();
    const allIds: string[] = await MessageCacheStore.getAllIdentities(keys);
    this.selectedIds = allIds;
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
        const queuedForce: boolean = this.forceRefreshQueued;
        this.forceRefreshQueued = false;
        this.loadMessages(queuedForce);
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

  /** 复制详情文字，并按点击区域提示所复制的内容类型。 */
  private async copyText(text: string, label: string): Promise<void> {
    if (text.length === 0) {
      return;
    }
    try {
      const data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      const sys: pasteboard.SystemPasteboard = pasteboard.getSystemPasteboard();
      await sys.setData(data);
      showToast(this.getUIContext(), `${label}已复制`, 1500);
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

  /** selectedIds 变化时异步刷新各 group 的真实选中计数。 */
  private onSelectedIdsChanged(): void {
    this.refreshSelectedGroupCounts();
  }

  /**
   * 查询本地缓存，计算每个 group_key 当前被选中的消息数。
   */
  private async refreshSelectedGroupCounts(): Promise<void> {
    if (this.selectedIds.length === 0) {
      this.selectedGroupCounts = new Map<string, number>();
      return;
    }
    const keys: string[] = this.getVisibleHistoryKeys();
    if (keys.length === 0) {
      return;
    }
    this.selectedGroupCounts = await MessageCacheStore.getSelectedGroupCounts(keys, this.selectedIds);
  }

  private handleMultiSelectClicked(): void {
    if (this.messages.length === 0) {
      showToast(this.getUIContext(), '暂无可多选的通知');
      return;
    }
    if (this.isEditing) {
      if (this.selectedIds.length > 0) {
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

  // ====== group 分组展示 ======

  /** Checkbox 的 onChange 可能由状态回显触发，仅在目标状态不同的时候写入。 */
  private setSelected(id: string, selected: boolean): void {
    const next: string[] = setSelectedMessage(this.selectedIds, id, selected);
    if (next !== this.selectedIds) {
      this.selectedIds = next;
    }
  }

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

  // ====== 分组/平铺模式切换（右下角浮动按钮） ======

  private toggleGroupExpanded(groupKey: string): void {
    const nextExpanded: boolean = !this.isGroupExpanded(groupKey);
    this.getUIContext().animateTo({ duration: 280, curve: Curve.EaseInOut }, () => {
      this.setGroupExpanded(groupKey, nextExpanded);
    });
  }

  /**
   * 切换分组显示模式并持久化。
   * 切到平铺时清空展开状态（平铺没有分组可展开）；
   * 切回分组时也清空，让用户重新选择展开哪些组。
   */
  private toggleGroupEnabled(): void {
    this.stopSearchScrollSampling();
    this.suppressBottomButtonUntilUserScroll = false;
    this.bottomButtonUserTouchStarted = false;
    this.groupEnabled = !this.groupEnabled;
    this.flatLoadedLimit = FLAT_PAGE_SIZE;
    // 两种模式的首屏取数方式不同，先移除旧模式快照，避免其尾项被当作平铺态游标。
    this.messages = [];
    this.expandedGroups = [];
    PreferencesUtil.putString(null, PreferencesUtil.KEY_GROUP_ENABLED,
      this.groupEnabled ? 'true' : 'false');
    // 平铺模式不展示展开态；重新开启分组时投影已保存的全局展开记录。
    if (this.groupEnabled) {
      this.restoreVisibleExpandedGroups();
    }
    this.refreshVisibleAfterSyncPage(-1);
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
      ? (this.savedExpandedGroups.indexOf(groupKey) >= 0 ? this.savedExpandedGroups :
        [...this.savedExpandedGroups, groupKey])
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

  /**
   * 切换某 group 的选中状态。与"全选"一致，覆盖该组全部本地缓存消息
   * （含未加载到列表内存的历史消息），而非仅操作已加载的 section.messages。
   */
  private async toggleGroupSelection(groupMessages: NotifyMessage[]): Promise<void> {
    if (groupMessages.length === 0) {
      return;
    }
    const groupKey: string = groupMessages[0].group;
    const groupIds: string[] = await MessageCacheStore.getGroupIdentities(this.getVisibleHistoryKeys(), groupKey);
    // 已加载消息全部选中时视为整组选中，此时取消选中该组全部缓存消息
    if (areGroupMessagesSelected(this.selectedIds, groupMessages)) {
      const removeSet: Set<string> = new Set<string>(groupIds);
      this.selectedIds = this.selectedIds.filter((id: string) => !removeSet.has(id));
    } else {
      const existing: Set<string> = new Set<string>(this.selectedIds);
      const next: string[] = [...this.selectedIds];
      for (let i = 0; i < groupIds.length; i++) {
        if (!existing.has(groupIds[i])) {
          next.push(groupIds[i]);
        }
      }
      this.selectedIds = next;
    }
  }

  // ====== 删除确认与执行 ======

  /**
   * 按 Checkbox 目标状态设置某 group 的选中状态，覆盖该组全部本地缓存消息。
   */
  private async setGroupSelection(groupMessages: NotifyMessage[], selected: boolean): Promise<void> {
    if (groupMessages.length === 0) {
      return;
    }
    const groupKey: string = groupMessages[0].group;
    const groupIds: string[] = await MessageCacheStore.getGroupIdentities(this.getVisibleHistoryKeys(), groupKey);
    if (selected) {
      const existing: Set<string> = new Set<string>(this.selectedIds);
      const next: string[] = [...this.selectedIds];
      for (let i = 0; i < groupIds.length; i++) {
        if (!existing.has(groupIds[i])) {
          next.push(groupIds[i]);
        }
      }
      this.selectedIds = next;
    } else {
      const removeSet: Set<string> = new Set<string>(groupIds);
      this.selectedIds = this.selectedIds.filter((id: string) => !removeSet.has(id));
    }
  }

  private async confirmDanger(title: string, message: string, confirmText: string): Promise<boolean> {
    try {
      const background = getDialogBackgroundOptions();
      return await new Promise<boolean>((resolve: (confirmed: boolean) => void) => {
        let controller: CustomDialogController | undefined;
        controller = new CustomDialogController({
          builder: DangerConfirmDialog({
            title: title,
            message: message,
            confirmText: confirmText,
            onResult: (confirmed: boolean): void => {
              controller?.close();
              resolve(confirmed);
            },
          }),
          alignment: DialogAlignment.Center,
          autoCancel: false,
          cornerRadius: 14,
          systemMaterial: background.systemMaterial,
          backgroundColor: background.backgroundColor,
          backgroundBlurStyle: background.backgroundBlurStyle,
        });
        controller.open();
      });
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'danger dialog 失败：%{public}s',
        err instanceof Error ? err.message : String(err));
      return false;
    }
  }

  /** 解析本地身份；不把不同服务器的相同数字 id 合并。 */
  private parseDeletePairs(ids: string[]): DeviceIdPair[] {
    const pairs: DeviceIdPair[] = [];
    for (let i: number = 0; i < ids.length; i++) {
      try {
        const parsed: Object = JSON.parse(ids[i]);
        if (parsed instanceof Array && parsed.length === 2 &&
          typeof parsed[0] === 'string' && parsed[0].length > 0 &&
          typeof parsed[1] === 'number' && parsed[1] > 0) {
          pairs.push({ deviceKey: parsed[0] as string, id: parsed[1] as number });
        }
      } catch (_ignore) {
        // 非法身份不应触发任何远端或本地删除。
      }
    }
    return pairs;
  }

  /** 解密失败项先删除当前实例的远端副本；失败项留在本地，其他项按原逻辑本地删除。 */
  private async deleteManualIds(ids: string[] | null, groupKey: string | null = null): Promise<ManualDeleteResult> {
    const sync: NotifySyncService = NotifySyncService.getInstance();
    try {
      await sync.beginManualDeletion();
      return await this.deleteManualIdsWhileSyncPaused(ids, groupKey);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, '手动删除通知失败：%{public}s', err instanceof Error ? err.message : String(err));
      return { deletedIds: [], remoteFailed: 0, localFailed: true };
    } finally {
      sync.endManualDeletion();
    }
  }

  private async deleteManualIdsWhileSyncPaused(ids: string[] | null,
    groupKey: string | null): Promise<ManualDeleteResult> {
    const result: ManualDeleteResult = { deletedIds: [], remoteFailed: 0, localFailed: false };
    const targetIds: string[] = ids ?? (groupKey === null
      ? await MessageCacheStore.getAllIdentities(this.getVisibleHistoryKeys())
      : await MessageCacheStore.getGroupIdentities(this.getVisibleHistoryKeys(), groupKey));
    if (targetIds.length === 0 && ids === null && this.totalCachedCount > 0) {
      result.localFailed = true;
      return result;
    }
    const pairs: DeviceIdPair[] = this.parseDeletePairs(targetIds);
    if (pairs.length !== targetIds.length) {
      result.localFailed = true;
      return result;
    }
    const selected: Set<string> = new Set<string>(targetIds);
    const failed: Set<string> = new Set<string>();
    let failures: NotifyMessage[];
    try {
      failures = await MessageCacheStore.loadDecryptionFailures(this.getVisibleHistoryKeys(), groupKey);
    } catch (_err) {
      result.localFailed = true;
      return result;
    }
    const servers: ServerEntry[] = ServerManager.getInstance().getList();
    const remoteTargets: NotifyMessage[] = [];
    const remoteServers: ServerEntry[] = [];
    for (let i: number = 0; i < failures.length; i++) {
      const message: NotifyMessage = failures[i];
      if (!selected.has(notifyIdentity(message))) {
        continue;
      }
      const server: ServerEntry | null = resolveCurrentRemoteServer(message, servers);
      if (server) {
        remoteTargets.push(message);
        remoteServers.push(server);
      }
      // 旧实例或来源不明的本地历史不具备安全的远端目标，只清本地，不猜测当前服务器 ID。
    }
    // 配置中的实例 ID 可能因服务器重建而过时；删除前再读取当前实例，避免数字 id 撞上新数据库。
    const verified: Map<string, boolean> = new Map<string, boolean>();
    for (let i: number = 0; i < remoteTargets.length; i++) {
      const server: ServerEntry = remoteServers[i];
      if (verified.has(server.id)) {
        continue;
      }
      if (!server.instanceId) {
        verified.set(server.id, false);
        continue;
      }
      const probe = await NotifyMessageService.getInstance().getMessages(null, 0, 0, 0, 0, server);
      verified.set(server.id, probe.ok && probe.instancePersistent && probe.instanceId === server.instanceId);
    }
    const concurrency: number = 4;
    for (let offset: number = 0; offset < remoteTargets.length; offset += concurrency) {
      const tasks: Promise<string>[] = [];
      for (let i: number = offset; i < Math.min(offset + concurrency, remoteTargets.length); i++) {
        if (verified.get(remoteServers[i].id) === true) {
          tasks.push(NotifyMessageService.getInstance().deleteMessage(remoteTargets[i].id, null, remoteServers[i]));
        } else {
          tasks.push(Promise.resolve('无法确认服务器实例'));
        }
      }
      const errors: string[] = await Promise.all(tasks);
      for (let i: number = 0; i < errors.length; i++) {
        if (errors[i].length > 0) {
          failed.add(notifyIdentity(remoteTargets[offset + i]));
        }
      }
    }
    result.remoteFailed = failed.size;
    result.deletedIds = targetIds.filter((id: string) => !failed.has(id));
    if (!(await MessageCacheStore.deleteByDeviceIdPairs(this.parseDeletePairs(result.deletedIds)))) {
      result.deletedIds = [];
      result.localFailed = true;
    }
    return result;
  }

  private async finishManualDeletion(result: ManualDeleteResult, uiCtx: UIContext): Promise<void> {
    if (result.deletedIds.length > 0) {
      await this.refreshVisibleAfterSyncPage(this.loadSeq);
      this.expandedGroups = retainExpandableGroups(this.messages, this.expandedGroups, this.groupTotals);
      this.exitEditMode();
    }
    if (result.localFailed) {
      showToast(uiCtx, '删除失败，请稍后重试');
    } else if (result.remoteFailed > 0) {
      showToast(uiCtx, `已删除 ${result.deletedIds.length} 条，${result.remoteFailed} 条删除失败，已保留待重试`);
    } else {
      showToast(uiCtx, `已删除 ${result.deletedIds.length} 条`);
    }
  }

  private confirmDeleteOne(m: NotifyMessage, closeDetailOnSuccess: boolean = false): void {
    const uiCtx: UIContext = this.getUIContext();
    this.confirmDanger(m.isDecryptionFailed() ? '删除解密失败的通知' : '删除通知',
      `${m.isDecryptionFailed() ?
        '删除后无法恢复；如果删除失败，此通知会保留以便重试。' :
        '删除后无法恢复。'}${m.title && m.title.length > 0 ?
        '\n\n「' + m.title + '」' : ''}`, '删除').then(async (confirmed: boolean) => {
      if (!confirmed) {
        return;
      }
      const outcome: ManualDeleteResult = await this.deleteManualIds([notifyIdentity(m)]);
      await this.finishManualDeletion(outcome, uiCtx);
      if (outcome.deletedIds.length > 0 && closeDetailOnSuccess) {
        this.showDetail = false;
      }
    });
  }

  private confirmDeleteGroup(section: NotifySection): void {
    const uiCtx: UIContext = this.getUIContext();
    const count: number = section.total;
    this.confirmDanger('删除整个分组',
      `将删除该分组的全部 ${count} 条通知，包括尚未加载的历史通知。删除后无法恢复；删除失败的通知会保留以便重试。`,
      '全部删除').then(async (confirmed: boolean) => {
      if (!confirmed) {
        return;
      }
      showToast(uiCtx, `正在删除 ${count} 条通知…`);
      const outcome: ManualDeleteResult = await this.deleteManualIds(null, section.groupKey);
      await this.finishManualDeletion(outcome, uiCtx);
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
    this.confirmDanger('删除选中通知',
      `将删除选中的 ${count} 条通知。删除后无法恢复；删除失败的通知会保留以便重试。`,
      '全部删除').then(async (confirmed: boolean) => {
      if (!confirmed) {
        return;
      }
      const ids: string[] = [...this.selectedIds];
      const outcome: ManualDeleteResult = await this.deleteManualIds(ids);
      await this.finishManualDeletion(outcome, uiCtx);
    });
  }

  private confirmDeleteAll(): void {
    const uiCtx: UIContext = this.getUIContext();
    // 本地无消息时无需调用清空接口
    if (this.totalCachedCount === 0) {
      showToast(uiCtx, '暂无可删除的通知');
      return;
    }
    this.confirmDanger('清空全部通知', this.viewAll
      ? '将删除所有服务器的通知，包括未加载的历史通知。删除后无法恢复；删除失败的通知会保留以便重试。'
      : '将删除当前服务器的全部通知，包括未加载的历史通知。删除后无法恢复；删除失败的通知会保留以便重试。',
      '全部删除').then(async (confirmed: boolean) => {
      if (!confirmed) {
        return;
      }
      showToast(uiCtx, `正在删除 ${this.totalCachedCount} 条通知…`);
      const outcome: ManualDeleteResult = await this.deleteManualIds(null);
      await this.finishManualDeletion(outcome, uiCtx);
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
        const keys: string[] = this.getVisibleHistoryKeys();
        const grouped: boolean = this.groupEnabled;
        let totals: Map<string, number>;
        let messages: NotifyMessage[];
        let requestedFlatLimit: number = this.flatLoadedLimit;
        if (grouped) {
          // 先取每组最新 500 条，再补回用户已加载的组内历史深度；同步刷新不能把追加的页抹掉。
          const refreshed = await MessageCacheStore.loadAllGroupedLatest(keys, 500);
          totals = refreshed.totals;
          messages = refreshed.messages;
          const loadedCounts: Map<string, number> = new Map<string, number>();
          for (let i = 0; i < this.messages.length; i++) {
            const groupKey: string = this.messages[i].group;
            loadedCounts.set(groupKey, (loadedCounts.get(groupKey) ?? 0) + 1);
          }
          const latestCounts: Map<string, number> = new Map<string, number>();
          const oldestByGroup: Map<string, NotifyMessage> = new Map<string, NotifyMessage>();
          for (let i = 0; i < messages.length; i++) {
            const message: NotifyMessage = messages[i];
            latestCounts.set(message.group, (latestCounts.get(message.group) ?? 0) + 1);
            const oldest: NotifyMessage | undefined = oldestByGroup.get(message.group);
            if (!oldest || compareNotifyOrder(oldest, message) < 0) {
              oldestByGroup.set(message.group, message);
            }
          }
          const loadedKeys: string[] = [];
          loadedCounts.forEach((_count: number, groupKey: string) => loadedKeys.push(groupKey));
          for (let i = 0; i < loadedKeys.length; i++) {
            const groupKey: string = loadedKeys[i];
            const oldest: NotifyMessage | undefined = oldestByGroup.get(groupKey);
            if (!oldest) {
              continue;
            }
            const total: number = totals.get(groupKey) ?? 0;
            const previousTotal: number = this.groupTotals.get(groupKey) ?? total;
            const targetCount: number = Math.min(total,
              (loadedCounts.get(groupKey) ?? 0) + Math.max(0, total - previousTotal));
            const extraCount: number = targetCount - (latestCounts.get(groupKey) ?? 0);
            if (extraCount > 0) {
              const older: NotifyMessage[] =
                await MessageCacheStore.loadAllGroupOlder(keys, groupKey, oldest, extraCount);
              messages = messages.concat(older);
            }
          }
          messages.sort(compareNotifyOrder);
        } else {
          totals = await MessageCacheStore.getAllGroupTotals(keys);
          let latestTotal: number = 0;
          totals.forEach((count: number) => latestTotal += count);
          // 新同步的通知位于顶部；增大读取深度以保住用户已经翻到的历史页。
          requestedFlatLimit = this.flatLoadedLimit + (this.messages.length > 0
            ? Math.max(0, latestTotal - this.totalCachedCount) : 0);
          const flatMessages: NotifyMessage[] | null =
            await MessageCacheStore.loadAllFlatLatest(keys, requestedFlatLimit);
          if (flatMessages === null) {
            return;
          }
          messages = flatMessages;
        }
        // 加载更多在查询期间提交了新页时，跳过这份旧快照并按最新深度重查，避免列表闪回。
        if (this.pageRefreshPending) {
          continue;
        }
        if (seq === this.loadSeq && grouped === this.groupEnabled) {
          this.messages = messages;
          this.groupTotals = totals;
          // 统计所有可见 device_keys 的缓存消息总数，供"全选"计数使用。
          let total: number = 0;
          totals.forEach((count: number) => {
            total += count;
          });
          this.totalCachedCount = total;
          if (!grouped) {
            // 若加载更多与刷新重叠，下一轮以较深的分页限额重新读取，防止旧快照覆盖新页。
            if (this.flatLoadedLimit > requestedFlatLimit) {
              this.pageRefreshPending = true;
            }
            this.flatLoadedLimit = Math.max(this.flatLoadedLimit, requestedFlatLimit);
          }
        } else if (seq === this.loadSeq && grouped !== this.groupEnabled) {
          this.pageRefreshPending = true;
        }
      } while (this.pageRefreshPending);
    } finally {
      this.pageRefreshInFlight = false;
    }
  }

  private async loadMessages(forceAll: boolean = false): Promise<void> {
    if (this.loading) {
      this.refreshing = false;
      this.loadQueued = true;
      this.forceRefreshQueued = this.forceRefreshQueued || forceAll;
      return;
    }
    this.loading = true;
    const seq: number = ++this.loadSeq;
    this.errorMsg = '';
    try {
      await ServerManager.getInstance().ensureLoaded();
      const expiredDeleted: number = await MessageCacheStore.purgeExpired();
      if (expiredDeleted > 0) {
        this.messages = [];
        this.groupTotals = new Map<string, number>();
      }
      await this.refreshVisibleAfterSyncPage(seq);
      await NotifySyncService.getInstance().requestSync(forceAll);
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
        const queuedForce: boolean = this.forceRefreshQueued;
        this.forceRefreshQueued = false;
        this.loadMessages(queuedForce); // 补拉：消费排队期间产生的最新拉取需求
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
    if (!this.groupEnabled || this.groupLoadingMore.has(groupKey)) {
      return;
    }
    const seq: number = this.loadSeq;
    const keys: string[] = this.getVisibleHistoryKeys();
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
      const PAGE_SIZE: number = 500;
      const older: NotifyMessage[] = await MessageCacheStore.loadAllGroupOlder(keys, groupKey, oldest, PAGE_SIZE);
      if (seq !== this.loadSeq || !this.groupEnabled || keys.join('|') !== this.getVisibleHistoryKeys().join('|')) {
        return;
      }
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
          // 若同步刷新正在查询，补读一次，避免旧快照覆盖刚追加的组内页。
          if (this.pageRefreshInFlight) {
            this.pageRefreshPending = true;
          }
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

  /** 平铺态触底时按全局时间顺序读取下一批本地历史；不触发网络同步。 */
  private async loadMoreFlat(): Promise<void> {
    if (this.groupEnabled || this.flatLoadingMore || this.messages.length === 0 ||
      this.messages.length >= this.totalCachedCount) {
      return;
    }
    const seq: number = this.loadSeq;
    const keys: string[] = this.getVisibleHistoryKeys();
    const oldest: NotifyMessage = this.messages[this.messages.length - 1];
    this.flatLoadingMore = true;
    try {
      const older: NotifyMessage[] | null =
        await MessageCacheStore.loadAllFlatOlder(keys, oldest, FLAT_PAGE_SIZE);
      if (seq !== this.loadSeq || this.groupEnabled || keys.join('|') !== this.getVisibleHistoryKeys().join('|')) {
        return;
      }
      if (older === null) {
        showToast(this.getUIContext(), '加载失败，请重试');
        return;
      }
      if (older.length > 0) {
        const existing: Set<string> = new Set<string>(this.messages.map((message: NotifyMessage) =>
          notifyIdentity(message)));
        const deduped: NotifyMessage[] = older.filter((message: NotifyMessage) =>
          !existing.has(notifyIdentity(message)));
        if (deduped.length > 0) {
          this.messages = this.messages.concat(deduped);
          this.flatLoadedLimit = Math.max(this.flatLoadedLimit, this.messages.length);
          if (this.pageRefreshInFlight) {
            this.pageRefreshPending = true;
          }
        }
      } else {
        // 总数与列表不一致时重新查询真实缓存数量，避免错误显示“加载更多”。
        this.refreshVisibleAfterSyncPage(-1);
      }
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'loadMoreFlat 异常：%{public}s', err instanceof Error ? err.message : String(err));
    } finally {
      this.flatLoadingMore = false;
    }
  }

  private handleMoreClicked(): void {
    try {
      // 「切换通知服务」弹窗：仅单选视图范围（全部通知/某服务器）。
      // 与详情 Sheet、服务器操作弹窗一致：API 26+ 且开关开启就传入统一的 THICK 材质。
      // 低算力设备即使材质 no-op，也保留系统弹窗的半透明背板；旧系统走轻量模糊。
      const dialogMaterial = getDialogMaterial(this.immersiveLightEnabled);
      this.dialogController = new CustomDialogController({
        builder: ServerSwitchDialog(),
        alignment: DialogAlignment.Center,
        autoCancel: true,
        offset: { dx: 0, dy: 0 },
        cornerRadius: 14,
        systemMaterial: dialogMaterial,
        backgroundColor: dialogMaterial ? Color.Transparent : undefined,
        backgroundBlurStyle: dialogMaterial ? undefined : BlurStyle.COMPONENT_ULTRA_THIN,
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
      const count: number =
        await NotifyExportService.exportSelected(abilityContext, this.getVisibleHistoryKeys(), this.selectedIds);
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
