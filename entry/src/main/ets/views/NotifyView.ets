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
import { extractHost } from '../utils/ServerUrlUtil';
import { ServerSwitchDialog } from '../components/notify/ServerSwitchDialog';
import { ServerKeyDialog, ServerActionMenuDialog, ServerRenameDialog } from '../components/ServerActionDialogs';
import { ClientTokenDialog } from '../components/ClientTokenDialog';
import { DecryptionSettingsDialog } from '../components/DecryptionSettingsDialog';
import { EncryptionConfig } from '../model/EncryptionConfig';
import { EncryptionConfigService } from '../services/EncryptionConfigService';
import { DeviceRegisterService } from '../services/DeviceRegisterService';
import {
  getDialogBackgroundOptions,
  getDialogMaterial,
  getEnabledSystemMaterial,
  KEY_IMMERSIVE_LIGHT_ENABLED,
  KEY_MATERIAL_LOADED,
  resolveBlurStyle,
  shouldUseLoadedMaterialStyle,
  shouldUseSystemMaterialPath
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
import { NotifyExportService } from '../services/NotifyExportService';
import { belongsToPushInstance, compareNotifyOrder, notifyIdentity, resolveCurrentRemoteServer } from '../utils/NotifyIdentity';

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
  // 「跳到底部」浮动按钮显隐：上滑离开首屏时显示，下滑、在首屏或到达底部时隐藏。
  @State showScrollToBottom: boolean = false;
  // 「跳到底部」触发信号：每次自增传给列表，列表 Watch 后执行两段式定位滚动。
  @State scrollToBottomSignal: number = 0;
  // 「切换通知服务」弹窗：点击时（材质必已就绪）才构造，以便 systemMaterial 读取到最新就绪态
  private dialogController: CustomDialogController | null = null;
  private onChange: ((list: ServerEntry[], curId: string) => void) | null = null;
  private loadSeq: number = 0;
  private loadQueued: boolean = false;
  private forceRefreshQueued: boolean = false;
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
  private fixEncryptionController: CustomDialogController | null = null;
  private fixRenameController: CustomDialogController | null = null;

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
      top: shouldUseSystemMaterialPath(this.immersiveLightEnabled)
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
          onCopy: () => { this.handleCopyServer(server); },
          onResetKey: () => { this.openKeyDialogFor(server); },
          onClientToken: () => { this.openClientTokenDialogFor(server); },
          onEncryption: () => { this.openEncryptionDialogFor(server); },
          onRename: () => { this.openRenameDialogFor(server); },
          onDelete: () => { this.confirmDeleteServer(server); },
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
      const result = await this.getUIContext().getPromptAction().showDialog({
        title: '删除服务器',
        message: `确定删除「${server.name || server.baseURL}」吗？`,
        buttons: [
          { text: '取消', color: $r('app.color.color_text_tertiary') },
          { text: '确定', color: $r('app.color.color_error') },
        ],
        systemMaterial: getDialogBackgroundOptions().systemMaterial,
      });
      if (result.index !== 1) {
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
   * - 在首屏（yOffset <= 0）或已到达底部：隐藏按钮。
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
    if (this.scroller.isAtEnd()) {
      if (this.showScrollToBottom) {
        this.showScrollToBottom = false;
      }
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
    if (shouldUseSystemMaterialPath(this.immersiveLightEnabled)) {
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
    NotifyRefreshHeader({ refreshState: this.refreshState,
      topInset: this.getListTopInset() });
  }

  @Builder
  listView() {
    NotifyMessageList({ messages: this.messages, isEditing: this.isEditing, selectedIds: this.selectedIds,
      expandedGroups: this.expandedGroups, groupCardHeights: this.groupCardHeights,
      groupTotals: this.groupTotals, selectedGroupCounts: this.selectedGroupCounts,
      groupLoadingMore: this.groupLoadingMore,
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
      onListReachEnd: () => {
        if (this.showScrollToBottom) {
          this.showScrollToBottom = false;
        }
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
    NotifyEditActionBar({ selectedCount: this.selectedIds.length, messageCount: this.totalCachedCount,
      exporting: this.exportingSelected, navBarHeight: this.navBarHeight,
      immersiveLightEnabled: this.immersiveLightEnabled,
      onCancel: () => this.exitEditMode(),
      onToggleAll: () => this.toggleAllSelection(),
      onExport: () => this.handleExportSelected(),
      onDelete: () => this.handleDeleteSelected() });
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

  /** 详情正文；沉浸/降级两种 MODAL 标题栏样式共用同一内容。 */
  @Builder
  detailContent() {
    NotifyMessageDetail({
      message: this.selectedMessage,
      useImmersiveMaterial: shouldUseLoadedMaterialStyle(this.immersiveLightEnabled, this.immersiveMaterialLoaded),
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

  // ====== 删除确认与执行 ======
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

  private async deleteManualIdsWhileSyncPaused(ids: string[] | null, groupKey: string | null): Promise<ManualDeleteResult> {
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
      showToast(uiCtx, '本地删除失败，请稍后重试');
    } else if (result.remoteFailed > 0) {
      showToast(uiCtx, `已删除 ${result.deletedIds.length} 条，${result.remoteFailed} 条远端删除失败，已保留待重试`);
    } else {
      showToast(uiCtx, `已删除 ${result.deletedIds.length} 条`);
    }
  }

  private confirmDeleteOne(m: NotifyMessage, closeDetailOnSuccess: boolean = false): void {
    const uiCtx: UIContext = this.getUIContext();
    uiCtx.getPromptAction().showDialog({
      title: m.isDecryptionFailed() ? '删除解密失败的通知' : '从本机删除通知',
      message: `${m.isDecryptionFailed() ?
        '此通知的密文仍在服务器。将先删除远程记录，再删除本地；远程删除失败时保留此通知以便重试。' :
        '此通知已从服务器迁移到本机。删除后无法恢复。'}${m.title && m.title.length > 0 ?
        '\n\n「' + m.title + '」' : ''}`,
      buttons: [
        { text: '取消', color: $r('app.color.color_text_tertiary') },
        { text: '删除', color: $r('app.color.color_error') },
      ],
      // API 26+ 且开关开启时系统确认框走统一的 THICK 沉浸材质，旧系统缺省纯色
      systemMaterial: getDialogMaterial(),
    }, async (err: BusinessError, result: promptAction.ShowDialogSuccessResponse) => {
      if (err || result.index !== 1) {
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
    uiCtx.getPromptAction().showDialog({
      title: '删除整个分组',
      message: `将删除该分组的全部 ${count} 条本地通知，包括尚未加载的历史通知。解密失败的通知会先删除远程副本；远程删除失败的条目将保留。其余通知删除后无法恢复。`,
      buttons: [
        { text: '取消', color: $r('app.color.color_text_tertiary') },
        { text: '全部删除', color: $r('app.color.color_error') },
      ],
      // API 26+ 且开关开启时系统确认框走统一的 THICK 沉浸材质，旧系统缺省纯色
      systemMaterial: getDialogMaterial(),
    }, async (err: BusinessError, result: promptAction.ShowDialogSuccessResponse) => {
      if (err || result.index !== 1) {
        return;
      }
      showToast(uiCtx, `正在删除 ${count} 条本地通知…`);
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
    uiCtx.getPromptAction().showDialog({
      title: '删除选中通知',
      message: `将删除选中的 ${count} 条通知。解密失败的通知会先删除远程副本；远程删除失败的条目将保留。其余通知删除后无法恢复。`,
      buttons: [
        { text: '取消', color: $r('app.color.color_text_tertiary') },
        { text: '全部删除', color: $r('app.color.color_error') },
      ],
      // API 26+ 且开关开启时系统确认框走统一的 THICK 沉浸材质，旧系统缺省纯色
      systemMaterial: getDialogMaterial(),
    }, async (err: BusinessError, result: promptAction.ShowDialogSuccessResponse) => {
      if (err || result.index !== 1) {
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
    uiCtx.getPromptAction().showDialog({
      title: '清空全部通知',
      message: this.viewAll
        ? '将删除本机保存的所有服务器通知，包括未加载的历史通知。解密失败的通知会先删除远程副本；远程删除失败的条目将保留。其余通知删除后无法恢复。'
        : '将删除本机保存的当前服务器全部通知，包括未加载的历史通知。解密失败的通知会先删除远程副本；远程删除失败的条目将保留。其余通知删除后无法恢复。',
      buttons: [
        { text: '取消', color: $r('app.color.color_text_tertiary') },
        { text: '全部删除', color: $r('app.color.color_error') },
      ],
      // API 26+ 且开关开启时系统确认框走统一的 THICK 沉浸材质，旧系统缺省纯色
      systemMaterial: getDialogMaterial(),
    }, async (err: BusinessError, result: promptAction.ShowDialogSuccessResponse) => {
      if (err || result.index !== 1) {
        return;
      }
      showToast(uiCtx, `正在删除 ${this.totalCachedCount} 条本地通知…`);
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
        const keys: string[] = this.viewAll ? this.getAllDeviceKeys() : this.getCurrentHistoryKeys();
        // 本地缓存加载上限：提高到 500，使更多已缓存消息可被全选/分组选中（网络同步 PAGE_SIZE 仍为 100）
        const refreshed = await MessageCacheStore.loadAllGroupedLatest(keys, 500);
        if (seq === this.loadSeq) {
          this.messages = refreshed.messages;
          this.groupTotals = refreshed.totals;
          // 统计所有可见 device_keys 的缓存消息总数，供"全选"计数使用
          let total: number = 0;
          refreshed.totals.forEach((count: number) => { total += count; });
          this.totalCachedCount = total;
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
      const PAGE_SIZE: number = 500;
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
      const count: number = await NotifyExportService.exportSelected(abilityContext, this.getVisibleHistoryKeys(), this.selectedIds);
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
