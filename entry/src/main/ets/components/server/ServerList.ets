import { hilog } from '@kit.PerformanceAnalysisKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { ServerEntry } from '../../model/ServerEntry';
import { ServerManager } from '../../services/ServerManager';
import { DeviceRegisterService } from '../../services/DeviceRegisterService';
import { ServerKeyDialog, ServerRenameDialog } from '../ServerActionDialogs';
import { ClientTokenDialog } from '../ClientTokenDialog';
import { EncryptionConfig } from '../../model/EncryptionConfig';
import { EncryptionConfigService } from '../../services/EncryptionConfigService';
import { NotifyMessageService, toShortSyncError } from '../../services/NotifyMessageService';
import { NotifySyncService } from '../../services/NotifySyncService';
import { DecryptionSettingsDialog } from '../DecryptionSettingsDialog';
import showToast from '../showToast';
import { DOMAIN, KEY_HOME_TAB_INDEX, KEY_NOTIFY_REFRESH_SIGNAL } from '../../common/Constant';
import {
  getDialogBackgroundOptions,
  getDialogMaterial,
  getEnabledSystemMaterial,
  KEY_IMMERSIVE_LIGHT_ENABLED,
  KEY_MATERIAL_LOADED,
  shouldUseLoadedMaterialStyle,
  shouldUseSystemMaterialPath
} from '../../utils/ImmersiveUtil';

const TAG: string = 'ServerList';

// 从 URL 中提取 host 展示
function extractHost(url: string): string {
  let s: string = url;
  const protoEnd: number = s.indexOf('://');
  if (protoEnd >= 0) {
    s = s.substring(protoEnd + 3);
  }
  const slashIdx: number = s.indexOf('/');
  if (slashIdx >= 0) {
    s = s.substring(0, slashIdx);
  }
  return s;
}

// 服务器列表组件（仅展示列表 + 切换/删除/操作菜单，不含添加表单与 viewAll 开关）
@Component
export struct ServerList {
  @State serverList: ServerEntry[] = [];
  @State currentId: string = '';
  // 当前操作目标服务器
  @State targetId: string = '';
  @State targetName: string = '';
  @State currentDeviceKey: string = '';
  @State currentEncryptionConfig: EncryptionConfig = new EncryptionConfig();
  // 详情 Sheet 状态
  @State showDetail: boolean = false;
  @State selectedServer: ServerEntry | null = null;
  // 沉浸光感开关与材质就绪
  @StorageProp(KEY_IMMERSIVE_LIGHT_ENABLED) immersiveLightEnabled: boolean = true;
  @StorageProp(KEY_MATERIAL_LOADED) immersiveMaterialLoaded: boolean = false;
  // 当前首页 Tab：切到「服务」时主动逐台检测一次
  @StorageProp(KEY_HOME_TAB_INDEX) @Watch('onHomeTabChanged') homeTabIndex: number = 0;
  // 主动检测得到的 per-server 错误（serverId → 简短错误文案）
  @State serverErrors: Record<string, string> = {};
  // 防止切 Tab 触发重入
  private checking: boolean = false;
  // Sheet 内滚动控制器
  private detailScroller: Scroller = new Scroller();
  private onChange: ((list: ServerEntry[], curId: string) => void) | null = null;
  // 弹窗 controller 延迟到打开时构造
  private renameController: CustomDialogController | null = null;
  private keyController: CustomDialogController | null = null;
  private clientTokenController: CustomDialogController | null = null;
  private encryptionController: CustomDialogController | null = null;

  aboutToAppear() {
    this.refresh();
    this.refreshDeviceKey();
    // TabContent 懒加载：组件首次创建即说明已切到「服务」Tab，立即检测一次
    this.checkServers();
    const mgr: ServerManager = ServerManager.getInstance();
    this.onChange = (_list: ServerEntry[], _curId: string): void => {
      this.refresh();
      // 新增/删除/切换等变更后重新探测错误标记
      this.checkServers();
    };
    mgr.addChangeListener(this.onChange);
  }

  aboutToDisappear() {
    if (this.onChange) {
      ServerManager.getInstance().removeChangeListener(this.onChange);
    }
  }

  @Builder
  itemRow(s: ServerEntry) {
    Row({ space: 12 }) {
      Column({ space: 2 }) {
        if (this.badgeTextFor(s).length > 0) {
          Text(this.badgeTextFor(s))
            .fontSize(10)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.color_error'))
            .padding({
              left: 8,
              right: 8,
              top: 2,
              bottom: 2
            })
            .borderRadius(9)
            .backgroundColor($r('app.color.color_error_bg'))
            .margin({ bottom: 6 });
        }

        Text(s.name && s.name.length > 0 ? s.name : extractHost(s.baseURL))
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.color_text_primary'))
          .width('100%');

        Text(s.baseURL)
          .fontSize(12)
          .fontColor($r('app.color.color_text_hint'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%');

      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1);

      Image($r('app.media.arrow_right'))
        .width(18)
        .height(18)
        .fillColor($r('app.color.color_text_hint'))
        .draggable(false);
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.color_bg_surface'))
    .borderRadius(10)
    .onClick(() => {
      this.openDetail(s);
    });
  }

  build() {
    Column({ space: 12 }) {
      Row({ space: 6 }) {
        Image($r('app.media.more_colorful'))
          .width(32)
          .height(32)
          .objectFit(ImageFit.Contain)
          .draggable(false);

        Text('服务器列表')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.color_text_primary'));
      }
      .width('100%')
      .alignItems(VerticalAlign.Center);

      // 外层已有 Scroll，直接 ForEach 渲染行（避免 List 嵌套 Scroll 需显式高度的告警与嵌套滚动冲突）
      ForEach(this.serverList, (s: ServerEntry) => {
        this.itemRow(s);
      }, (s: ServerEntry) => `${s.id}|${s.name}`);
    }
    .width('100%')
    .align(Alignment.Top)
    .bindSheet(this.showDetail, this.detailBuilder(), {
      // detents 定义停靠档位：打开时自适应内容高度，可上拖到全屏（首项为初始高度）
      detents: [SheetSize.FIT_CONTENT, SheetSize.LARGE],
      preferType: SheetType.BOTTOM,
      showClose: false,
      enableFloatingDragBar: true,
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
    });
  }

  @Builder
  detailBuilder() {
    if (this.selectedServer !== null) {
      // FIT_CONTENT 自适应要求根节点随内容包裹；HdsNavigation 基于系统 Navigation，
      // 测量时强制填满父约束会让自适应退化为全屏。根节点改用普通 Column + 玻璃化自定义标题栏。
      Column() {
        Row() {
          Text('服务器详情')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.color_text_primary'));
          Blank();
          Button() {
            SymbolGlyph($r('sys.symbol.xmark'))
              .fontSize(18)
              .fontColor([$r('app.color.color_text_primary')]);
          }
          .type(ButtonType.Normal)
          .width(36)
          .height(36)
          .borderRadius(18)
          .backgroundColor($r('app.color.color_bg_control_glass'))
          .onClick(() => {
            this.showDetail = false;
          });
        }
        .width('100%')
        // top 预留悬浮拖拽条区域（默认距顶 8vp、高约 16vp）
        .padding({
          left: 16,
          right: 12,
          top: 28,
          bottom: 10
        });

        this.detailContent()
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start);
    }
  }

  @Builder
  detailContent() {
    Scroll(this.detailScroller) {
      Column({ space: 16 }) {
        // 服务器信息
        this.detailServerInfo();

        // 操作列表
        Column({ space: 0 }) {
          this.detailActionItem('复制地址和 Key', () => {
            this.handleCopy();
          });
          this.detailDivider();
          this.detailActionItem('重置 / 还原 Key', () => {
            this.openKeyDialog();
          });
          this.detailDivider();
          this.detailActionItem('客户端 Token', () => {
            this.openClientTokenDialog();
          });
          this.detailDivider();
          this.detailActionItem('解密设置', () => {
            this.openEncryptionDialog();
          });
          this.detailDivider();
          this.detailActionItem('重命名', () => {
            this.openRenameDialog();
          });
          this.detailDivider();
          this.detailActionItem('删除服务器', () => {
            this.handleDelete(this.targetId);
          }, true);
        }
        .width('100%')
        .backgroundColor(
          shouldUseLoadedMaterialStyle(this.immersiveLightEnabled, this.immersiveMaterialLoaded)
            ? $r('app.color.color_bg_surface_glass') : $r('app.color.color_bg_surface'))
        .borderRadius(12)
        .clip(true);

        // 底部透明占位
        Column()
          .width('100%')
          .height(16)
          .backgroundColor(Color.Transparent);
      }
      .width('100%')
      .padding({
        left: 16,
        right: 16,
        top: 4,
        bottom: 20
      });
    }
    .width('100%')
    // 无固定/百分比高度：FIT_CONTENT 下 Scroll 随内容包裹（自适应生效）；
    // 拖到 LARGE 全屏档时根 Column 获得确定高度，内容超高由此 Scroll 内部滚动
    .scrollBar(BarState.Off)
    .align(Alignment.Top);
  }

  @Builder
  detailServerInfo() {
    Column({ space: 8 }) {
      Text(this.selectedServer && this.selectedServer.name && this.selectedServer.name.length > 0
        ? this.selectedServer.name : extractHost(this.selectedServer ? this.selectedServer.baseURL : ''))
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.color_text_primary'));

      Text(this.selectedServer ? this.selectedServer.baseURL : '')
        .fontSize(13)
        .fontColor($r('app.color.color_text_hint'))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis });
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(16)
    .backgroundColor(
      shouldUseLoadedMaterialStyle(this.immersiveLightEnabled, this.immersiveMaterialLoaded)
        ? $r('app.color.color_bg_surface_glass') : $r('app.color.color_bg_surface'))
    .borderRadius(12);
  }

  @Builder
  detailActionItem(label: string, action: () => void, isDestructive?: boolean) {
    Row() {
      Text(label)
        .fontSize(16)
        .fontColor(isDestructive ? $r('app.color.color_error') : $r('app.color.color_text_primary'))
        .layoutWeight(1);

      Image($r('app.media.arrow_right'))
        .width(16)
        .height(16)
        .fillColor($r('app.color.color_text_hint'))
        .draggable(false);
    }
    .width('100%')
    .padding({
      left: 16,
      right: 16,
      top: 14,
      bottom: 14
    })
    .onClick(() => {
      action();
    });
  }

  @Builder
  detailDivider() {
    Divider()
      .strokeWidth(1)
      .color($r('app.color.color_border_subtle'))
      .margin({ left: 16 });
  }

  // 每次切回「服务」Tab 重新检测所有服务器
  private onHomeTabChanged(): void {
    if (this.homeTabIndex === 1) {
      this.checkServers();
    }
  }

  /**
   * 主动逐台做一次最轻量探测（limit=1 的消息拉取，只读不落库）：
   * 成功清除该服务器错误标记，失败映射为简短文案展示在标题上方。
   */
  private async checkServers(): Promise<void> {
    if (this.checking) {
      return;
    }
    this.checking = true;
    try {
      const mgr: ServerManager = ServerManager.getInstance();
      await mgr.ensureLoaded();
      const list: ServerEntry[] = mgr.getList();
      const next: Record<string, string> = {};
      const svc: NotifyMessageService = NotifyMessageService.getInstance();
      for (let i = 0; i < list.length; i++) {
        const s: ServerEntry = list[i];
        const result = await svc.getMessages(null, 0, 1, 0, 0, s, false);
        const c_t = await svc.getEffectiveClientToken(null, s)
        if (!result.ok && result.errorMsg.length > 0) {
          next[s.id] = toShortSyncError(result.errorMsg, c_t);
        }
      }
      this.serverErrors = next;
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'checkServers 异常');
    } finally {
      this.checking = false;
    }
  }

  // 列表项错误胶囊：仅展示主动检测错误与设备未注册；默认 Token 可用不提示
  private badgeTextFor(s: ServerEntry): string {
    const detected: string | undefined = this.serverErrors[s.id];
    if (detected && detected.length > 0) {
      return detected;
    }
    if (!s.deviceKey || s.deviceKey.length === 0) {
      return '设备 Key 未注册';
    }
    return '';
  }

  private openDetail(s: ServerEntry): void {
    this.targetId = s.id;
    this.targetName = s.name;
    this.selectedServer = s;
    this.showDetail = true;
  }

  private refresh(): void {
    const mgr: ServerManager = ServerManager.getInstance();
    const list: ServerEntry[] = mgr.getList();
    const cur: ServerEntry | null = mgr.getCurrentServer();
    this.currentId = cur ? cur.id : '';

    // 强制把当前服务器放在列表第一个
    if (cur) {
      const idx: number = list.findIndex((s: ServerEntry) => s.id === cur.id);
      if (idx > 0) {
        const current: ServerEntry = list.splice(idx, 1)[0];
        list.unshift(current);
      }
    }
    this.serverList = list;

    // 若详情 Sheet 正打开，同步刷新选中服务器引用，避免重命名后展示旧名称
    if (this.showDetail && this.targetId.length > 0) {
      const fresh: ServerEntry | undefined = list.find((s: ServerEntry) => s.id === this.targetId);
      this.selectedServer = fresh ? fresh : null;
    }
  }

  private async refreshDeviceKey(): Promise<void> {
    const k: string | null = await DeviceRegisterService.getInstance().ensureRegistered(null);
    this.currentDeviceKey = k && k.length > 0 ? k : '';
  }

  private findTarget(): ServerEntry | null {
    for (let i = 0; i < this.serverList.length; i++) {
      if (this.serverList[i].id === this.targetId) {
        return this.serverList[i];
      }
    }
    return null;
  }

  private async openRenameDialog(): Promise<void> {
    const target: ServerEntry | null = this.findTarget();
    if (!target) {
      showToast(this.getUIContext(), '服务器信息缺失');
      return;
    }
    try {
      // 背板与「服务器操作」「切换通知服务」弹窗统一：API 26+ 且开关开启即传 ULTRA_THIN 材质，
      // 不以设备 supported 结果拦截，材质分支透明；旧系统或开关关闭走系统容器轻量模糊。
      const dialogMaterial = getDialogMaterial(this.immersiveLightEnabled);
      this.renameController = new CustomDialogController({
        builder: ServerRenameDialog({
          getInitName: (): string => this.targetName,
          serverDomain: extractHost(target.baseURL),
          onConfirm: (newName: string): void => {
            this.handleRename(newName);
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
      this.renameController.open();
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'rename dialog open 失败');
      showToast(this.getUIContext(), '弹窗无法打开');
    }
  }

  private async openKeyDialog(): Promise<void> {
    const server: ServerEntry | null = this.findTarget();
    if (!server) {
      showToast(this.getUIContext(), '服务器信息缺失');
      return;
    }
    try {
      // 背板与「服务器操作」「切换通知服务」弹窗统一：API 26+ 且开关开启即传 ULTRA_THIN 材质，
      // 不以设备 supported 结果拦截，材质分支透明；旧系统或开关关闭走系统容器轻量模糊。
      const dialogMaterial = getDialogMaterial(this.immersiveLightEnabled);
      this.keyController = new CustomDialogController({
        builder: ServerKeyDialog({
          getCurrentKey: (): string => server.deviceKey,
          onConfirm: (inputKey: string): void => {
            this.handleResetOrRestore(inputKey);
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
      this.keyController.open();
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'key dialog open 失败');
      showToast(this.getUIContext(), '弹窗无法打开');
    }
  }

  private async openClientTokenDialog(): Promise<void> {
    const server: ServerEntry | null = this.findTarget();
    if (!server) {
      showToast(this.getUIContext(), '服务器信息缺失');
      return;
    }
    try {
      // 背板与「服务器操作」「切换通知服务」弹窗统一：API 26+ 且开关开启即传 ULTRA_THIN 材质，
      // 不以设备 supported 结果拦截，材质分支透明；旧系统或开关关闭走系统容器轻量模糊。
      const dialogMaterial = getDialogMaterial(this.immersiveLightEnabled);
      this.clientTokenController = new CustomDialogController({
        builder: ClientTokenDialog({
          getInitToken: (): string => server.clientToken,
          saveToken: async (token: string): Promise<boolean> => {
            const target: ServerEntry | null = this.findTarget();
            if (!target) {
              return false;
            }
            await ServerManager.getInstance().updateServerClientToken(null, target.id, token);
            return true;
          },
          onSaved: (): void => {
            this.refresh();
            this.checkServers();
            const current: number = AppStorage.get<number>(KEY_NOTIFY_REFRESH_SIGNAL) ?? 0;
            AppStorage.setOrCreate(KEY_NOTIFY_REFRESH_SIGNAL, current + 1);
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
      this.clientTokenController.open();
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'client token dialog open 失败');
      showToast(this.getUIContext(), '弹窗无法打开');
    }
  }

  private async openEncryptionDialog(): Promise<void> {
    const server: ServerEntry | null = this.findTarget();
    if (!server) {
      showToast(this.getUIContext(), '服务器信息缺失');
      return;
    }
    try {
      const dialogMaterial = getDialogMaterial(this.immersiveLightEnabled);
      this.encryptionController = new CustomDialogController({
        builder: DecryptionSettingsDialog({
          serverLabel: this.targetName,
          loadConfig: (): Promise<EncryptionConfig> => EncryptionConfigService.get(null, server.id),
          onSave: (config: EncryptionConfig): Promise<boolean> => this.saveEncryption(config),
          onClear: (): Promise<boolean> => this.clearEncryption(),
        }),
        alignment: DialogAlignment.Center,
        autoCancel: true,
        offset: { dx: 0, dy: 0 },
        cornerRadius: 14,
        systemMaterial: dialogMaterial,
        backgroundColor: dialogMaterial ? Color.Transparent : undefined,
        backgroundBlurStyle: dialogMaterial ? undefined : BlurStyle.COMPONENT_ULTRA_THIN,
      });
      this.encryptionController.open();
    } catch (_err) {
      hilog.warn(DOMAIN, TAG, 'encryption dialog open 失败');
      showToast(this.getUIContext(), '弹窗无法打开');
    }
  }

  private async saveEncryption(config: EncryptionConfig): Promise<boolean> {
    const server: ServerEntry | null = this.findTarget();
    if (!server) {
      showToast(this.getUIContext(), '服务器信息缺失');
      return false;
    }
    config.deviceKey = server.deviceKey;
    try {
      const ok: boolean = await EncryptionConfigService.save(null, server.id, config);
      if (ok) {
        this.currentEncryptionConfig = config;
        try {
          await this.refreshEncryptedMessages(server.deviceKey);
        } catch (_err) {
          hilog.warn(DOMAIN, TAG, '刷新已解密消息失败');
        }
        try {
          NotifySyncService.getInstance().retryServer(server.id);
        } catch (_err) {
          hilog.warn(DOMAIN, TAG, '重试服务器同步失败');
        }
      }
      showToast(this.getUIContext(), ok ? '解密设置已保存' : '保存失败');
      return ok;
    } catch (_err) {
      hilog.warn(DOMAIN, TAG, '保存解密设置失败');
      showToast(this.getUIContext(), '保存失败');
      return false;
    }
  }

  private async clearEncryption(): Promise<boolean> {
    const server: ServerEntry | null = this.findTarget();
    if (!server) {
      showToast(this.getUIContext(), '服务器信息缺失');
      return false;
    }
    try {
      const ok: boolean = await EncryptionConfigService.remove(null, server.id);
      if (ok) {
        this.currentEncryptionConfig = new EncryptionConfig();
        try {
          await this.refreshEncryptedMessages(server.deviceKey);
        } catch (_err) {
          hilog.warn(DOMAIN, TAG, '清除后刷新已解密消息失败');
        }
        try {
          NotifySyncService.getInstance().retryServer(server.id);
        } catch (_err) {
          hilog.warn(DOMAIN, TAG, '清除后重试服务器同步失败');
        }
      }
      showToast(this.getUIContext(), ok ? '解密设置已清除' : '清除失败');
      return ok;
    } catch (_err) {
      hilog.warn(DOMAIN, TAG, '清除解密设置失败');
      showToast(this.getUIContext(), '清除失败');
      return false;
    }
  }

  private async refreshEncryptedMessages(deviceKey: string): Promise<void> {
    const server: ServerEntry | null = this.findTarget();
    if (server && deviceKey.length > 0) {
      await NotifyMessageService.getInstance().redecryptCachedMessages(server);
    }
    const current: number = AppStorage.get<number>(KEY_NOTIFY_REFRESH_SIGNAL) ?? 0;
    AppStorage.setOrCreate(KEY_NOTIFY_REFRESH_SIGNAL, current + 1);
  }

  private async handleCopy(): Promise<void> {
    const server: ServerEntry | null = this.findTarget();
    if (!server) {
      showToast(this.getUIContext(), '服务器信息缺失');
      return;
    }
    let key: string = server.deviceKey;
    if (!key || key.length === 0) {
      // 目标服务器尚未注册，先为该服务器注册获取 key
      const fresh: string | null = await DeviceRegisterService.getInstance()
        .syncKeyForServer(null, server.id, server.baseURL, '');
      key = fresh && fresh.length > 0 ? fresh : '';
      this.refresh();
    }
    if (!key || key.length === 0) {
      showToast(this.getUIContext(), '未获取到 Key');
      return;
    }
    const text: string = `${server.baseURL}/${key}`;
    const ok: boolean = await this.copyText(text);
    showToast(this.getUIContext(), ok ? '已复制地址和 Key' : '复制失败', ok ? 1200 : undefined);
  }

  private async copyText(text: string): Promise<boolean> {
    try {
      const data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      const sys: pasteboard.SystemPasteboard = pasteboard.getSystemPasteboard();
      await sys.setData(data);
      return true;
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, TAG, 'copyText 失败：%{public}s', msg);
      return false;
    }
  }

  private async handleRename(newName: string): Promise<void> {
    if (this.targetId.length === 0) {
      return;
    }
    const ok: boolean = await ServerManager.getInstance().renameServer(null, this.targetId, newName);
    showToast(this.getUIContext(), ok ? '已重命名' : '重命名失败');
  }

  private async handleResetOrRestore(inputKey: string): Promise<void> {
    const server: ServerEntry | null = this.findTarget();
    if (!server) {
      showToast(this.getUIContext(), '服务器信息缺失');
      return;
    }
    const key: string | null = await DeviceRegisterService.getInstance()
      .syncKeyForServer(null, server.id, server.baseURL, inputKey.length > 0 ? inputKey : '');
    if (key && key.length > 0) {
      this.refresh();
      this.checkServers();
      showToast(this.getUIContext(), inputKey.length > 0 ? '已还原 Key' : '已重置 Key');
    } else {
      showToast(this.getUIContext(), '操作失败');
    }
  }

  private async confirmDialog(title: string, message: string): Promise<boolean> {
    try {
      const res = await this.getUIContext().getPromptAction().showDialog({
        title: title,
        message: message,
        buttons: [
          { text: '取消', color: $r('app.color.color_text_tertiary') },
          { text: '确定', color: $r('app.color.color_error') },
        ],
        systemMaterial: getDialogBackgroundOptions().systemMaterial,
      });
      return res.index === 1;
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, TAG, 'showDialog 失败：%{public}s', msg);
      return false;
    }
  }

  private async handleDelete(id: string): Promise<void> {
    const mgr: ServerManager = ServerManager.getInstance();
    if (mgr.getList().length <= 1) {
      showToast(this.getUIContext(), '至少保留一个服务器');
      return;
    }
    const confirmed: boolean = await this.confirmDialog('删除服务器', '确定删除该服务器吗？');
    if (!confirmed) {
      return;
    }
    const ok: boolean = await mgr.deleteServer(null, id);
    if (ok) {
      await EncryptionConfigService.remove(null, id);
      showToast(this.getUIContext(), '已删除', 1200);
    } else {
      showToast(this.getUIContext(), '删除失败');
    }
  }
}
