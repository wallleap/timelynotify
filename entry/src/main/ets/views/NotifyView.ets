import { hilog } from '@kit.PerformanceAnalysisKit';
import { promptAction, UIContext } from '@kit.ArkUI';
import { BusinessError, pasteboard } from '@kit.BasicServicesKit';
import { common, Want } from '@kit.AbilityKit';
import { fileIo, picker } from '@kit.CoreFileKit';
import { ServerEntry } from '../model/ServerEntry';
import { ServerManager } from '../services/ServerManager';
import { NotifyMessage } from '../model/NotifyMessage';
import { NotifyMessageService } from '../services/NotifyMessageService';
import { MessageCacheStore } from '../services/MessageCacheStore';
import { ServerSettingsDialog } from '../components/ServerSettingsDialog';
import {
  KEY_IMMERSIVE_LIGHT_ENABLED,
  SUPPORTS_IMMERSIVE_MATERIAL
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

const TAG: string = 'NotifyView';

// 前台轮询间隔（ms）：「通知」Tab 可见期间静默拉取新消息，
// 补齐"用户停留列表页时新消息不及时出现"的场景
const POLL_INTERVAL_MS: number = 15000;


// 通知页 - 展示接收到的 HTTP 推送消息列表
@Component
export struct NotifyView {
  @State title: string = '';
  @State messages: NotifyMessage[] = [];
  @State loading: boolean = false;
  @State errorMsg: string = '';
  @State refreshing: boolean = false;
  @State hasClientToken: boolean = false;
  // 触底分页加载更老消息
  @State loadingMore: boolean = false;
  @State hasMore: boolean = true;
  // 点击查看的消息详情（bindContentCover 全屏模态）
  @State showDetail: boolean = false;
  @State selectedMessage: NotifyMessage | null = null;
  // 多选模式状态：经 @StorageLink 同步到 AppStorage，Index.onBackPress 读取以拦截系统返回退出编辑
  @StorageLink(KEY_NOTIFY_EDITING) @Watch('onIsEditingChanged') isEditing: boolean = false;
  @State selectedIds: number[] = [];
  // 导出选中消息：防重复触发
  @State exportingSelected: boolean = false;
  // 当前展开的 group 标识集合；折叠状态只属于 UI 展示层，数据源仍以 messages 为准
  @State expandedGroups: string[] = [];
  // 折叠态分组主卡片的实测高度（vp），按 groupKey 缓存。空壳层高度必须显式与主卡片一致：
  // 在虚拟化 List 中给空壳设 height('100%') 会被解析成接近整个列表视口的高度，空壳会拉成通屏大面板
  @State groupCardHeights: Map<string, number> = new Map<string, number>();
  // 左滑互斥：当前展开左滑的消息 ID（-1 表示无）
  // 状态栏高度（vp），详情模态标题栏顶部避让用；EntryAbility 沉浸式布局初始化时写入 AppStorage（键值见 ImmersiveUtil）
  @StorageProp('statusBarHeight') statusBarHeight: number = 36;
  // 底部导航条高度（vp），编辑操作栏与列表底部占位避让用
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  // 沉浸光感用户开关（API 26+ 生效；MineView Toggle 切换后经 AppStorage 同步，此处自动重渲染切换分支）
  @StorageProp(KEY_IMMERSIVE_LIGHT_ENABLED) immersiveLightEnabled: boolean = true;
  // 主页当前选中 Tab 索引（Index 经 @StorageLink 写入）：切走「通知」Tab 时自动退出多选模式；
  // 切回「通知」Tab（值为 0）时自动刷新列表
  @StorageProp(KEY_HOME_TAB_INDEX) @Watch('onHomeTabIndexChanged') homeTabIndex: number = 0;
  // 通知列表刷新信号（EntryAbility 回前台/点击通知拉起时自增）：@Watch 变化后自动拉取最新消息，
  // 保证用户回到列表/点通知进来时列表始终是最新的
  @StorageProp(KEY_NOTIFY_REFRESH_SIGNAL) @Watch('onRefreshSignalChanged') refreshSignal: number = 0;
  // 主页页面可见状态（Index onPageShow/onPageHide 写入）：Index 被 router 跳转覆盖/退后台时组件
  // 自身不会销毁（aboutToDisappear 不触发），需借助页面级显隐信号停止/恢复前台轮询
  @StorageProp(KEY_INDEX_PAGE_VISIBLE) @Watch('onPageVisibleChanged') indexPageVisible: boolean = true;
  // 下拉刷新状态：自定义刷新指示器不会自动隐藏，需按状态控制显隐
  @State refreshState: RefreshStatus = RefreshStatus.Inactive;
  // ⚠️ ArkUI 官方模式：CustomDialogController 必须在 struct 字段声明时直接初始化
  private dialogController: CustomDialogController = new CustomDialogController({
    builder: ServerSettingsDialog(),
    alignment: DialogAlignment.Center,
    autoCancel: true,
    offset: { dx: 0, dy: 0 },
  });
  private onChange: ((list: ServerEntry[], curId: string) => void) | null = null;
  // 请求代际：服务器切换/新请求发起后递增，过期响应直接丢弃，防止旧服务器数据写入列表
  private loadSeq: number = 0;
  // 补拉标志：loadMessages 在请求进行中被调用时置 true，当前请求结束后补拉一次
  private loadQueued: boolean = false;
  private scroller: Scroller = new Scroller();
  // 前台轮询定时器句柄（setTimeout 链式循环；-1 表示当前无待执行任务）
  private pollTimer: number = -1;
  // 轮询启用开关：「通知」Tab 可见时为 true；与 pollTimer 配合，
  // 防止飞行中的轮询请求在切走 Tab 后又重启循环
  private pollingEnabled: boolean = false;
  // 轮询请求进行中标记：防止慢网络下请求堆积
  private pollInFlight: boolean = false;

  aboutToAppear() {
    // ServerManager 可能还在异步 load，必须先 await ensureLoaded 再读当前 server，
    // 否则 currentId='' 会走兜底生产 URL，显示/请求错误的地址。
    this.initAfterServerManagerReady();
    this.onChange = (_list: ServerEntry[], _curId: string): void => {
      // 切换服务器后列表会整体刷新，selectedIds 属于旧服务器的消息 ID，继续操作会错删/报错，必须退出多选
      this.exitEditMode();
      this.refresh();
      // 旧服务器的消息不属于新服务器：立即清空列表与分页状态（新服务器拉取失败时也不残留旧数据），
      // 并递增代际使飞行中的旧请求响应过期丢弃
      this.messages = [];
      this.hasMore = false;
      // 展开状态属于当前服务器，切换后一并清空
      this.expandedGroups = [];
      this.groupCardHeights = new Map<string, number>();
      this.loadSeq++;
      // 服务器切换后重新拉取消息
      this.loadMessages();
    };
    ServerManager.getInstance().addChangeListener(this.onChange);
    // 「通知」Tab 为默认首 Tab，组件创建即可见时启动前台轮询
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

  // 降级顶栏：低版本 SDK 手工 Stack 叠层，blurStyle + 半透明底色实现毛玻璃
  @Builder
  fallbackTitleBar() {
    NotifyTitleBar({ title: this.title, isEditing: this.isEditing, statusBarHeight: this.statusBarHeight,
      onOpenSettings: () => this.handleMoreClicked(), onToggleSelection: () => this.handleMultiSelectClicked(),
      onDelete: () => this.handleDeletePillClicked() });
  }

  // HDS 顶栏自定义内容（塞入 HdsNavigation.titleBar.content.stackBuilder）。
  // 状态栏避让由 titleBar 级 avoidLayoutSafeArea: true 负责（系统将内容整体下移 statusBarHeight）；
  // 此处 padding 只留纯视觉余量，不得再叠加 statusBarHeight（titleBar 高度固定，会溢出裁剪 → 文字消失）。
  // ⚠️ stackBuilder 是全宽叠层，与右侧系统 menu 槽位区域重叠：
  //   1. 标题 Row 与透明占位节点都必须设 hitTestBehavior(None)（默认 Default 会阻塞兄弟节点），
  //      否则点击 menu 的「多选/删除」会误触发 title 事件；None 不阻塞子节点，标题/图标的 onClick 仍生效；
  //   2. menu 悬浮叠加不参与 Row 布局，标题 Row 末尾由 NotifyTitleBar 放等宽透明占位，
  //      标题区宽度才会被真实约束，长标题省略号在按钮前收尾，不会钻到按钮下方。
  @Builder
  customTitleContent() {
    NotifyTitleBar({ title: this.title, isEditing: this.isEditing, useHdsLayout: true,
      onOpenSettings: () => this.handleMoreClicked() });
  }

  // NotifyView Refresh 主体（含分支 view），两条渲染路径共用
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
    // ⚠️ 官方 HDS 动态模糊必配：Refresh 外层也不裁剪溢出，否则穿出 titleBar 背面的内容会被 Refresh 边界裁掉
    .clip(false)
    .width('100%')
    .height('100%')
    .onStateChange((state: RefreshStatus) => {
      // 同步刷新状态给自定义指示器，控制其显隐
      // Done（刷新结束）不会自动回到 Inactive，需直接视为隐藏，避免加载完成后指示器常驻
      this.refreshState = state === RefreshStatus.Done ? RefreshStatus.Inactive : state;
    })
    .onRefreshing(() => {
      this.refreshing = true;
      this.loadMessages();
    });
  }

  // NotifyView 主体（Refresh + 多选底部操作栏），两条渲染路径共用
  @Builder
  viewportBody() {
    Column() {
      Column() {
        this.refreshContentBody();
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
    if (SUPPORTS_IMMERSIVE_MATERIAL && this.immersiveLightEnabled) {
      // ─── API 26+: HdsNavigation 原生沉浸光感（titleBar 内置 systemMaterialEffect）───
      HdsNavigation() {
        this.viewportBody();
      }
      .titleBar({
        enableComponentSafeArea: true,
        // ⚠️ stackBuilder 全自定义区域系统不做状态栏避让（系统 mainTitle 槽位才自带避让），
        // 必须显式开启 avoidLayoutSafeArea，titleBar 内容整体下移 statusBarHeight，总高自动变为 statusBarHeight+56；
        // stackBuilder 内部不要再手工加 statusBarHeight（titleBar 高度固定会溢出裁剪）
        avoidLayoutSafeArea: true,
        content: {
          // 全自定义标题区：服务器标题 + 更多入口（胶囊按钮已迁至系统 menu 槽位获得沉浸光感）
          stackBuilder: (): void => {
            this.customTitleContent();
          },
          // 系统槽位按钮：系统渲染胶囊/图标样式，自动跟随 titleBar 沉浸光感材质
          menu: {
            value: [
              {
                content: {
                  // 文字按钮必须显式指定 TextStyleMode.NORMAL（胶囊样式），默认为图标渲染模式
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
          // 滚动到顶栏下方时触发 GradientBlur 渐变模糊：采样下层内容做动态光感模糊
          scrollEffectOpts: {
            enableScrollEffect: true,
            scrollEffectType: ScrollEffectType.GRADIENT_BLUR
          },
          systemMaterialEffect: {
            materialType: hdsMaterial.MaterialType.ADAPTIVE,
            // 官方推荐 ADAPTIVE：系统按设备算力自适应档位，避免低端机卡顿/发热
            //（EXQUISITE 需 getSystemMaterialTypes() 检测支持后才可硬编码）
            materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
          },
        }
      })
      .hideBackButton(true)
      .titleMode(HdsNavigationTitleMode.MINI)
      // 官方：绑定 List 滚动 → scrollEffectOpts 才会根据滚动偏移激活 GradientBlur 渐变模糊
      .bindToScrollable([this.scroller])
      .width('100%')
      .height('100%')
      // 点击消息卡片弹出全屏详情模态（内部已做状态栏避让 + 顶部圆角）
      .bindContentCover(this.showDetail, this.detailBuilder(), {
        onDisappear: () => {
          this.showDetail = false;
        }
      })
      .backgroundColor($r('app.color.index_page_body_background'));
    } else {
      // ─── API < 26: Stack + 手工顶栏叠层（backgroundBlurStyle 降级）───
      Column() {
        Stack({ alignContent: Alignment.Top }) {
          this.refreshContentBody();
          // 顶栏层（上层）：blurStyle + 半透明底色糊住下层滚动内容
          this.fallbackTitleBar();
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
      .backgroundColor($r('app.color.index_page_body_background'));
    }
  }

  // 仅在下拉/刷新过程中显示，静止（Inactive）时隐藏
  @Builder
  refreshHeaderBuilder() {
    NotifyRefreshHeader({ refreshState: this.refreshState, statusBarHeight: this.statusBarHeight,
      immersiveEnabled: SUPPORTS_IMMERSIVE_MATERIAL && this.immersiveLightEnabled });
  }

  @Builder
  listView() {
    NotifyMessageList({ messages: this.messages, isEditing: this.isEditing, selectedIds: this.selectedIds,
      expandedGroups: this.expandedGroups, groupCardHeights: this.groupCardHeights, loadingMore: this.loadingMore,
      hasMore: this.hasMore, statusBarHeight: this.statusBarHeight, navBarHeight: this.navBarHeight,
      immersiveLightEnabled: this.immersiveLightEnabled, listScroller: this.scroller,
      onLoadMore: () => this.loadMore(), onToggleSelect: (id: number) => this.toggleSelect(id),
      onToggleGroupSelection: (messages: NotifyMessage[]) => this.toggleGroupSelection(messages),
      onToggleGroupExpanded: (groupKey: string) => this.toggleGroupExpanded(groupKey),
      onOpenMessage: (message: NotifyMessage) => this.openMessageDetail(message),
      onOpenGroup: (section: NotifySection) => this.handleGroupHeaderClick(section),
      onHeightChange: (groupKey: string, height: number) => this.updateGroupCardHeight(groupKey, height),
      onDeleteOne: (message: NotifyMessage) => this.confirmDeleteOne(message),
      onDeleteGroup: (section: NotifySection) => this.confirmDeleteGroup(section),
      onOpenUrl: (url: string) => this.openUrl(url), onCopyCode: (code: string) => this.copyCode(code) });
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
      showToast(this.getUIContext(), '请先选择要导出的消息');
      return;
    }
    this.exportSelectedMessages();
  }

  /** 处理删除入口，保留空选择提示。 */
  private handleDeleteSelected(): void {
    if (this.selectedIds.length === 0) {
      showToast(this.getUIContext(), '请先选择要删除的消息');
      return;
    }
    this.confirmDeleteSelected();
  }

  // 消息详情全屏模态视图：完整展示标题/副标题/正文/时间，不截断
  @Builder
  detailBuilder() {
    NotifyMessageDetail({
      message: this.selectedMessage,
      statusBarHeight: this.statusBarHeight,
      navBarHeight: this.navBarHeight,
      onDismiss: () => { this.showDetail = false; },
      onOpenUrl: (url: string) => { this.openUrl(url); },
      onCopyCode: (code: string) => { this.copyCode(code); }
    });
  }

  /** aboutToAppear 是同步签名，这里 fire-and-forget 初始化链 */
  private async initAfterServerManagerReady(): Promise<void> {
    try {
      await ServerManager.getInstance().ensureLoaded();
      this.refresh();
      // 缓存优先：先从本地 RDB 读最新一页立即渲染，避免冷启动白屏等网络
      const deviceKey: string = await ServerManager.getInstance().getCurrentDeviceKey(null);
      if (deviceKey && deviceKey.length > 0) {
        const cached: NotifyMessage[] = await MessageCacheStore.loadLatest(deviceKey, 100);
        if (cached.length > 0) {
          this.messages = cached;
          this.hasMore = true;
        }
      }
      // 后台增量同步服务端（合并新消息 + 删除事件）
      this.syncFromServer(false);
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, TAG, '初始化失败：%{public}s', msg);
    }
  }

  private openUrl(url: string): void {
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const want: Want = {
        action: 'ohos.want.action.viewData',
        uri: url,
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

  // 未配置 client token 或未注册 → 引导到"我的"页配置
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

  // Tab 切换监听（homeTabIndex 的 @Watch 回调）：切走「通知」Tab 后列表不可见，
  // 多选状态保留无意义，自动退出编辑；切回「通知」Tab 时全量刷新，
  // 且仅在页面可见（未被其它页面覆盖/未退后台）时恢复前台轮询
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

  // 页面显隐监听（indexPageVisible 的 @Watch 回调）：Index 被 router 跳转其它页面覆盖或应用
  // 退后台时停止轮询；返回页面/回前台且停留在「通知」Tab 时恢复轮询
  private onPageVisibleChanged(): void {
    if (this.indexPageVisible) {
      if (this.homeTabIndex === 0) {
        this.startPolling();
      }
    } else {
      this.stopPolling();
    }
  }

  // 刷新信号监听（refreshSignal 的 @Watch 回调）：App 回前台或点击通知拉起时自动刷新列表
  private onRefreshSignalChanged(): void {
    this.loadMessages();
  }

  // ====== 前台轮询（「通知」Tab 可见期间保持列表增量更新）======

  // 启动轮询：幂等，重复调用不会叠加定时器
  private startPolling(): void {
    if (this.pollingEnabled) {
      return;
    }
    this.pollingEnabled = true;
    this.scheduleNextPoll();
  }

  // 停止轮询：清除待执行任务并关闭开关，飞行中的请求完成后不再续排
  private stopPolling(): void {
    this.pollingEnabled = false;
    if (this.pollTimer >= 0) {
      clearTimeout(this.pollTimer);
      this.pollTimer = -1;
    }
  }

  // 调度下一轮轮询：15s 后执行一次增量拉取，请求完成后再续排，
  // 间隔从请求结束时起算，慢网络下不会出现请求堆积
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

  // 静默增量拉取：走 after + deletedSince 协议，只拉本地没有的新消息并应用删除事件，
  // 不清空列表/不重置分页；失败静默，等下一轮
  private async pollNewMessages(): Promise<void> {
    // 有全量请求/翻页/轮询进行中 → 本轮跳过；未配置 Token 的引导态 → 不发无谓请求
    if (this.pollInFlight || this.loading || this.loadingMore || this.needGuideToConfig()) {
      return;
    }
    this.pollInFlight = true;
    try {
      await this.syncFromServer(false);
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, TAG, '轮询异常：%{public}s', msg);
    } finally {
      this.pollInFlight = false;
    }
  }

  // 编辑态变化监听（isEditing 的 @Watch 回调）：任何来源退出编辑（自身退出/Tab 切换/
  // Index.onBackPress 返回拦截）时，同步清空选中项，保证状态一致
  private onIsEditingChanged(): void {
    if (!this.isEditing && this.selectedIds.length > 0) {
      this.selectedIds = [];
    }
  }

  // 顶栏「多选」按钮的点击逻辑：无消息时提示不可多选；
  // 非编辑态进入多选；编辑态有选中时清空选择，无选中时退出编辑
  private handleMultiSelectClicked(): void {
    // 空列表无可多选，避免进入编辑态后底部操作栏不显示的"假编辑"状态
    if (this.messages.length === 0) {
      showToast(this.getUIContext(), '暂无可多选的消息');
      return;
    }
    if (this.isEditing) {
      // 多选模式下，选中有内容时清空，全选时取消全选，否则退出编辑
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

  // 顶栏删除胶囊按钮的点击逻辑：非编辑态清空全部消息（二次确认）；
  // 编辑态删除选中消息（有选中才触发，未选中时提示，与底部「删除(N)」按钮一致）
  private handleDeletePillClicked(): void {
    if (this.isEditing) {
      if (this.selectedIds.length > 0) {
        this.confirmDeleteSelected();
      } else {
        showToast(this.getUIContext(), '请先选择要删除的消息');
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

  // ====== group 分组展示 ======

  // 依据当前消息顺序构建展示分组：messages 已按时间倒序维护，分组位置取组内最新消息首次出现的位置；
  // 这是渲染层唯一的分组顺序来源，轮询/分页/删除后均重新从 messages 派生，避免多处各自排序造成漂移
  private isGroupExpanded(groupKey: string): boolean {
    return NotifyGroupStateUtils.isExpanded(this.expandedGroups, groupKey);
  }

  // 缓存某个分组主卡片的实测高度（vp）；不可变更新 Map 以触发空壳层重渲染
  private updateGroupCardHeight(groupKey: string, heightVp: number): void {
    if (heightVp <= 0) {
      return;
    }
    this.groupCardHeights = NotifyGroupStateUtils.updateCardHeight(this.groupCardHeights, groupKey, heightVp);
  }

  // 设置某个分组的展开状态（展开态数组不可变更新，确保 ForEach 刷新）
  private setGroupExpanded(groupKey: string, expanded: boolean): void {
    if (this.isGroupExpanded(groupKey) === expanded) {
      return;
    }
    this.expandedGroups = NotifyGroupStateUtils.toggleExpanded(this.expandedGroups, groupKey);
  }

  // 切换分组展开/收起，并在动画上下文中更新状态：
  // animateTo 期间 ListItemGroup 子 ListItem 的增删由 List 插值布局（高度展开/下方项让位），
  // header 内折叠卡/展开顶栏两形态通过各自的 TransitionEffect 交叉淡入淡出
  private toggleGroupExpanded(groupKey: string): void {
    const nextExpanded: boolean = !this.isGroupExpanded(groupKey);
    this.getUIContext().animateTo({ duration: 280, curve: Curve.EaseInOut }, () => {
      this.setGroupExpanded(groupKey, nextExpanded);
    });
  }

  // 分组头内容区点击：编辑态整组勾选；非编辑态折叠时展开，已展开时打开最新消息详情
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

  // 分组复选框是否应显示为选中：组内消息全部选中才选中
  private isGroupAllSelected(groupMessages: NotifyMessage[]): boolean {
    return areGroupMessagesSelected(this.selectedIds, groupMessages);
  }

  // 整组勾选/取消勾选：全选状态下取消整组，否则补齐组内未选中的消息
  private toggleGroupSelection(groupMessages: NotifyMessage[]): void {
    this.selectedIds = toggleGroupMessages(this.selectedIds, groupMessages);
  }

  // 从本地列表移除（UI 即时更新，不刷新整个列表）
  private removeFromList(ids: number[]): void {
    const idSet: Set<number> = new Set<number>(ids);
    const newList: NotifyMessage[] = [];
    for (let i = 0; i < this.messages.length; i++) {
      if (!idSet.has(this.messages[i].id)) {
        newList.push(this.messages[i]);
      }
    }
    this.messages = newList;
    // 清理已不存在，或删到只剩 1 条（已退回普通卡片）的分组展开状态，
    // 避免后续再次聚合成组时意外沿用展开态
    this.expandedGroups = retainExpandableGroups(this.messages, this.expandedGroups);
    // 如果删光了，退出编辑模式
    if (this.messages.length === 0) {
      this.exitEditMode();
    }
  }

  // ====== 删除确认与执行 ======
  private confirmDeleteOne(m: NotifyMessage): void {
    const uiCtx: UIContext = this.getUIContext();
    uiCtx.getPromptAction().showDialog({
      title: '确认删除',
      message: `确定要删除这条消息吗？${m.title && m.title.length > 0 ? '\n「' + m.title + '」' : ''}`,
      buttons: [
        { text: '取消', color: '#666666' },
        { text: '删除', color: '#F53F3F' },
      ],
    }, async (err: BusinessError, result: promptAction.ShowDialogSuccessResponse) => {
      if (err || result.index !== 1) {
        return;
      }
      const svc = NotifyMessageService.getInstance();
      const errMsg: string = await svc.deleteMessage(m.id);
      if (errMsg.length > 0) {
        showToast(uiCtx, errMsg);
        return;
      }
      // 同步删除本地缓存
      await ServerManager.getInstance().ensureLoaded();
      const deviceKey: string = await ServerManager.getInstance().getCurrentDeviceKey(null);
      if (deviceKey && deviceKey.length > 0) {
        await MessageCacheStore.deleteByIds(deviceKey, [m.id]);
      }
      this.removeFromList([m.id]);
      this.exitEditMode();
      showToast(uiCtx, '已删除');
    });
  }

  // 折叠态分组卡片左滑删除：删除该分组内全部消息
  private confirmDeleteGroup(section: NotifySection): void {
    const uiCtx: UIContext = this.getUIContext();
    const ids: number[] = [];
    for (let i = 0; i < section.messages.length; i++) {
      ids.push(section.messages[i].id);
    }
    const count: number = ids.length;
    uiCtx.getPromptAction().showDialog({
      title: '删除整个分组',
      message: `确定要删除该分组的 ${count} 条消息吗？此操作不可恢复。`,
      buttons: [
        { text: '取消', color: '#666666' },
        { text: '全部删除', color: '#F53F3F' },
      ],
    }, async (err: BusinessError, result: promptAction.ShowDialogSuccessResponse) => {
      if (err || result.index !== 1) {
        return;
      }
      // 多条逐个删（服务端无批量删除 API）；失败的 id 收集后提示
      const svc = NotifyMessageService.getInstance();
      let failCount = 0;
      for (let i = 0; i < ids.length; i++) {
        const errMsg: string = await svc.deleteMessage(ids[i]);
        if (errMsg.length > 0) {
          failCount++;
          hilog.warn(DOMAIN, TAG, '删除分组消息 %{public}d 失败：%{public}s', ids[i], errMsg);
        }
      }
      this.removeFromList(ids);
      if (failCount > 0) {
        showToast(uiCtx, `删除完成，${failCount} 条失败`);
      } else {
        showToast(uiCtx, `已删除 ${count} 条`);
      }
    });
  }

  private confirmDeleteSelected(): void {
    const uiCtx: UIContext = this.getUIContext();
    const count: number = this.selectedIds.length;
    uiCtx.getPromptAction().showDialog({
      title: '确认删除',
      message: `确定要删除选中的 ${count} 条消息吗？此操作不可恢复。`,
      buttons: [
        { text: '取消', color: '#666666' },
        { text: '全部删除', color: '#F53F3F' },
      ],
    }, async (err: BusinessError, result: promptAction.ShowDialogSuccessResponse) => {
      if (err || result.index !== 1) {
        return;
      }
      const ids: number[] = [...this.selectedIds];
      // 多条逐个删（服务端无批量删除 API）；失败的 id 收集后跳过
      const svc = NotifyMessageService.getInstance();
      let failCount = 0;
      for (let i = 0; i < ids.length; i++) {
        const errMsg: string = await svc.deleteMessage(ids[i]);
        if (errMsg.length > 0) {
          failCount++;
          hilog.warn(DOMAIN, TAG, '删除消息 %{public}d 失败：%{public}s', ids[i], errMsg);
        }
      }
      // 同步删除本地缓存（成功删除的 id 才删缓存；失败的保留，下次同步由删除流水兜底）
      await ServerManager.getInstance().ensureLoaded();
      const deviceKey: string = await ServerManager.getInstance().getCurrentDeviceKey(null);
      if (deviceKey && deviceKey.length > 0) {
        await MessageCacheStore.deleteByIds(deviceKey, ids);
      }
      this.removeFromList(ids);
      this.exitEditMode();
      if (failCount > 0) {
        showToast(uiCtx, `删除完成，${failCount} 条失败`);
      } else {
        showToast(uiCtx, `已删除 ${ids.length} 条`);
      }
    });
  }

  // 清空全部消息：弹窗二次确认并重点提示不可恢复，确认后调用服务端删除全部消息接口
  private confirmDeleteAll(): void {
    const uiCtx: UIContext = this.getUIContext();
    // 本地无消息时无需调用清空接口
    if (this.messages.length === 0) {
      showToast(uiCtx, '暂无可删除的消息');
      return;
    }
    uiCtx.getPromptAction().showDialog({
      title: '清空全部消息',
      message: `将删除当前设备的全部消息（包括未加载的历史消息），删除后无法找回。\n\n注意：此操作不可恢复！`,
      buttons: [
        { text: '取消', color: '#666666' },
        { text: '全部删除', color: '#F53F3F' },
      ],
    }, async (err: BusinessError, result: promptAction.ShowDialogSuccessResponse) => {
      if (err || result.index !== 1) {
        return;
      }
      const svc = NotifyMessageService.getInstance();
      const errMsg: string = await svc.deleteAllMessages();
      if (errMsg.length > 0) {
        showToast(uiCtx, errMsg);
        return;
      }
      // 清空成功：移除本地列表、清空本地缓存并退出多选模式
      await ServerManager.getInstance().ensureLoaded();
      const deviceKey: string = await ServerManager.getInstance().getCurrentDeviceKey(null);
      if (deviceKey && deviceKey.length > 0) {
        await MessageCacheStore.clearDevice(deviceKey);
      }
      this.exitEditMode();
      this.messages = [];
      this.expandedGroups = [];
      this.groupCardHeights = new Map<string, number>();
      showToast(uiCtx, '已清空全部消息');
    });
  }

  private refresh(): void {
    const cur: ServerEntry | null = ServerManager.getInstance().getCurrentServer();
    if (cur && cur.name && cur.name.length > 0) {
      this.title = cur.name;
    } else {
      this.title = ServerManager.getInstance().getCurrentHostDisplay();
    }
  }

  private async loadMessages(): Promise<void> {
    if (this.loading) {
      this.refreshing = false;
      // 已有请求在跑（如切换服务器时旧请求未完成）：排队补拉，保证新服务器数据最终被拉取
      this.loadQueued = true;
      return;
    }
    this.loading = true;
    // 请求代际：响应到达时与最新代际不符（期间已切换服务器/发起新请求）→ 过期丢弃
    const seq: number = ++this.loadSeq;
    // 清空旧错误，避免短暂闪烁旧错误态
    this.errorMsg = '';
    try {
      await this.syncFromServer(true, seq);
      // 是否有可用 client token（用户自定义 or 内置默认），用于引导态判断
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
   * 与服务端同步（增量协议）。
   * - forceFull=true：清空本地缓存，从 after=0 重新播种最新一页（下拉刷新/切服务器用）
   * - forceFull=false：以本地 maxId 为 after、delCursor 为 deletedSince，只拉新消息 + 删除事件
   * expectedSeq：请求代际，与 this.loadSeq 不符则丢弃结果（服务器切换防串数据）
   */
  private async syncFromServer(forceFull: boolean, expectedSeq: number = -1): Promise<void> {
    const svc = NotifyMessageService.getInstance();
    await ServerManager.getInstance().ensureLoaded();
    const deviceKey: string = await ServerManager.getInstance().getCurrentDeviceKey(null);
    if (!deviceKey || deviceKey.length === 0) {
      return;
    }

    // 代际校验：期间已切换服务器 → 丢弃
    if (expectedSeq >= 0 && expectedSeq !== this.loadSeq) {
      return;
    }

    // 读取同步基线
    let after: number = 0;
    let delCursor: number = 0;
    if (forceFull) {
      await MessageCacheStore.clearDevice(deviceKey);
    } else {
      const meta = await MessageCacheStore.getMeta(deviceKey);
      after = meta.maxId;
      delCursor = meta.delCursor;
      if (after === 0) {
        after = await MessageCacheStore.getMaxId(deviceKey);
      }
    }

    let newMaxId: number = after;
    let newDelCursor: number = delCursor;

    // 增量翻页循环（after 升序），最多 20 页防异常死循环
    const MAX_PAGES: number = 20;
    for (let page = 0; page < MAX_PAGES; page++) {
      if (expectedSeq >= 0 && expectedSeq !== this.loadSeq) {
        return;
      }
      const result = await svc.getMessages(null, 0, 100, after, newDelCursor);
      if (!result.ok) {
        // 失败：保留本地缓存，静默结束；forceFull 且本地为空时透出错误
        hilog.warn(DOMAIN, TAG, 'syncFromServer 失败：%{public}s', result.errorMsg);
        if (forceFull && this.messages.length === 0) {
          this.errorMsg = result.errorMsg;
        }
        return;
      }

      // 处理删除事件
      if (result.reset) {
        // 游标落在流水保留期缺口：清空本地重新播种
        hilog.info(DOMAIN, TAG, 'syncFromServer reset：清空本地缓存重新播种');
        await MessageCacheStore.clearDevice(deviceKey);
        after = 0;
        newMaxId = 0;
      } else {
        if (result.deletionIds.length > 0) {
          await MessageCacheStore.deleteByIds(deviceKey, result.deletionIds);
        }
        if (result.purges.length > 0) {
          let maxCeiling: number = 0;
          for (let i = 0; i < result.purges.length; i++) {
            if (result.purges[i] > maxCeiling) {
              maxCeiling = result.purges[i];
            }
          }
          if (maxCeiling > 0) {
            await MessageCacheStore.purgeBefore(deviceKey, maxCeiling);
          }
        }
      }
      if (result.delCursor > 0) {
        newDelCursor = result.delCursor;
      }

      // 写入新消息并推进 maxId
      if (result.messages.length > 0) {
        await MessageCacheStore.upsertMessages(deviceKey, result.messages);
        for (let i = 0; i < result.messages.length; i++) {
          if (result.messages[i].id > newMaxId) {
            newMaxId = result.messages[i].id;
          }
        }
      }

      if (!result.hasMore) {
        break;
      }
      // 下一页：用当前最大 id 作 after，删除游标只在首请求拉一次即可
      after = newMaxId;
    }

    // 持久化同步元信息
    await MessageCacheStore.saveMeta(deviceKey, newMaxId, newDelCursor);

    // 代际校验后从缓存重新加载列表（含删除结果，与本地一致）
    if (expectedSeq >= 0 && expectedSeq !== this.loadSeq) {
      return;
    }
    const refreshed: NotifyMessage[] = await MessageCacheStore.loadLatest(deviceKey, 100);
    this.messages = refreshed;
    this.hasMore = refreshed.length > 0;
    this.errorMsg = '';
  }

  // 触底加载更多：优先读本地缓存（秒出），缓存不足一页再走服务端 since 翻页并落库
  // limit 默认 100，返回少于 100 条说明已到底，置 hasMore=false
  private async loadMore(): Promise<void> {
    if (this.loadingMore || !this.hasMore || this.messages.length === 0) {
      return;
    }
    const oldest: NotifyMessage = this.messages[this.messages.length - 1];
    if (!oldest || oldest.id <= 0) {
      this.hasMore = false;
      return;
    }
    this.loadingMore = true;
    const PAGE_SIZE: number = 100;
    try {
      const deviceKey: string = await ServerManager.getInstance().getCurrentDeviceKey(null);
      const existingIds: Set<number> = new Set<number>();
      for (let i = 0; i < this.messages.length; i++) {
        existingIds.add(this.messages[i].id);
      }

      // 1) 优先从本地缓存读更老的消息
      let cached: NotifyMessage[] = [];
      if (deviceKey && deviceKey.length > 0) {
        cached = await MessageCacheStore.loadOlder(deviceKey, oldest.id, PAGE_SIZE);
      }
      const cachedDeduped: NotifyMessage[] = [];
      for (let i = 0; i < cached.length; i++) {
        if (!existingIds.has(cached[i].id)) {
          cachedDeduped.push(cached[i]);
          existingIds.add(cached[i].id);
        }
      }
      if (cachedDeduped.length > 0) {
        this.messages = this.messages.concat(cachedDeduped);
      }

      // 2) 缓存不足一页 → 走网络 since 翻页补齐，并落库供下次离线浏览
      if (cached.length < PAGE_SIZE) {
        const result = await NotifyMessageService.getInstance().getMessages(null, oldest.id, PAGE_SIZE);
        if (result.ok) {
          const newItems: NotifyMessage[] =
            result.messages.sort((a: NotifyMessage, b: NotifyMessage) => b.timestamp - a.timestamp);
          const deduped: NotifyMessage[] = [];
          for (let i = 0; i < newItems.length; i++) {
            if (!existingIds.has(newItems[i].id)) {
              deduped.push(newItems[i]);
              existingIds.add(newItems[i].id);
            }
          }
          if (deduped.length > 0) {
            this.messages = this.messages.concat(deduped);
            if (deviceKey && deviceKey.length > 0) {
              await MessageCacheStore.upsertMessages(deviceKey, deduped);
            }
          }
          if (newItems.length < PAGE_SIZE) {
            this.hasMore = false;
          }
        }
        // loadMore 失败不弹错误提示，避免打扰用户；日志已由 service 层打印
      }
      // 缓存满一页 → 仍可能有更多缓存，保持 hasMore=true 让用户继续下拉
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, TAG, 'loadMore 异常：%{public}s', msg);
    } finally {
      this.loadingMore = false;
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

  // 生成导出文件名时间后缀：yyyyMMdd_HHmmss
  private formatExportTime(d: Date): string {
    const p = (n: number): string => (n < 10 ? '0' + n : String(n));
    return `${d.getFullYear()}${p(d.getMonth() + 1)}${p(d.getDate())}_${p(d.getHours())}${p(d.getMinutes())}${p(
      d.getSeconds())}`;
  }

  // 将 NotifyMessage 转为可 JSON 序列化的原始对象（严格匹配服务端全量导出格式）
  // 字段：id, appid, title, message, priority, extras{device_key, subtitle?}, date
  private messageToRaw(m: NotifyMessage, deviceKey: string): Object {
    const raw: Record<string, Object> = {
      'id': m.id,
      'appid': m.appid,
      'title': m.title,
      'message': m.body,
      'priority': m.priority,
      'date': m.date.length > 0 ? m.date : (m.createdAt.length > 0 ? m.createdAt : ''),
    };
    // extras：固定放 device_key（与服务端一致）；有 subtitle 时也补在 extras 下
    const extras: Record<string, Object> = { 'device_key': deviceKey };
    if (m.subtitle && m.subtitle.length > 0) {
      extras['subtitle'] = m.subtitle;
    }
    raw['extras'] = extras as Object;
    return raw as Object;
  }

  // 导出当前选中的消息：
  // 1. 读取当前 device_key（放入 extras，与服务端全量导出格式一致）
  // 2. 从 this.messages 按 selectedIds 过滤
  // 3. 转为与全量导出同结构的 JSON 数组文本（2 空格缩进）
  // 4. DocumentViewPicker 拉起系统保存对话框（无需权限），用户选择位置后写入 txt
  private async exportSelectedMessages(): Promise<void> {
    if (this.exportingSelected || this.selectedIds.length === 0) {
      return; // 防重复触发
    }
    const uiCtx: UIContext = this.getUIContext();
    this.exportingSelected = true;
    try {
      // 预先加载 device_key：ServerManager 可能还在初始化，先 ensureLoaded
      await ServerManager.getInstance().ensureLoaded();
      const deviceKey: string = await ServerManager.getInstance().getCurrentDeviceKey(null);
      if (!deviceKey || deviceKey.length === 0) {
        showToast(uiCtx, '设备未注册，无法导出');
        return;
      }

      // 按 selectedIds 过滤当前列表中的消息（保持列表原有展示顺序：新→旧）
      const idSet: Set<number> = new Set<number>(this.selectedIds);
      const selected: NotifyMessage[] = [];
      for (let i = 0; i < this.messages.length; i++) {
        if (idSet.has(this.messages[i].id)) {
          selected.push(this.messages[i]);
        }
      }
      if (selected.length === 0) {
        showToast(uiCtx, '没有可导出的消息');
        return;
      }

      // 转成原始对象数组后 JSON 序列化（字段与服务端全量导出一致）
      const rawArr: Object[] = [];
      for (let i = 0; i < selected.length; i++) {
        rawArr.push(this.messageToRaw(selected[i], deviceKey));
      }
      const text: string = JSON.stringify(rawArr, null, 2);

      // 系统保存对话框：预设文件名 + txt 过滤；Picker 保存无需申请权限
      const saveOptions = new picker.DocumentSaveOptions();
      saveOptions.newFileNames = [`timelynotify_selected_${this.formatExportTime(new Date())}.txt`];
      saveOptions.fileSuffixChoices = ['文档|.txt'];
      const abilityCtx = this.getAbilityContext();
      if (!abilityCtx) {
        showToast(uiCtx, '上下文获取失败');
        return;
      }
      const docPicker = new picker.DocumentViewPicker(abilityCtx);
      const uris: string[] = await docPicker.save(saveOptions);
      if (uris.length === 0) {
        return; // 用户取消保存，静默结束
      }

      // Picker 返回的 URI 需以 READ_WRITE 模式打开后写入
      const file = fileIo.openSync(uris[0], fileIo.OpenMode.READ_WRITE);
      try {
        fileIo.writeSync(file.fd, text);
      } finally {
        fileIo.closeSync(file);
      }

      showToast(uiCtx, `已导出 ${selected.length} 条消息`, 1500);
      hilog.info(DOMAIN, TAG, '选中消息导出完成：count=%{public}d', String(selected.length));
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, TAG, '导出选中消息失败：%{public}s', msg);
      showToast(uiCtx, '导出失败');
    } finally {
      this.exportingSelected = false;
    }
  }
}
