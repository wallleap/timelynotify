import { hilog } from '@kit.PerformanceAnalysisKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { ServerEntry } from '../model/ServerEntry';
import { ServerManager } from '../services/ServerManager';
import { DeviceRegisterService } from '../services/DeviceRegisterService';
import { ServerActionMenuDialog, ServerKeyDialog, ServerRenameDialog, } from './ServerActionDialogs';
import { ClientTokenDialog } from './ClientTokenDialog';
import showToast from './showToast';
import { DOMAIN } from '../common/Constant';
import { KEY_NOTIFY_REFRESH_SIGNAL } from '../common/Constant';
import { EncryptionConfig } from '../model/EncryptionConfig';
import { EncryptionConfigService } from '../services/EncryptionConfigService';
import { NotifyMessageService } from '../services/NotifyMessageService';
import { EncryptionSettingsDialog } from './EncryptionSettingsDialog';

const TAG: string = 'ServerContent';

// 抽出 extractHost 到文件级（MineView/ServerSettingsPage 都可以复用）
export function extractHost(url: string): string {
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

// 服务器设置内容（NotifyView 弹窗、MineView 页面共享）
@Component
export struct ServerSettingsContent {
  @Prop maxListHeight: number = 0; // 列表最大高度（0 = 不限制，Page 模式）
  @State serverList: ServerEntry[] = [];
  @State currentId: string = '';
  @State viewAll: boolean = true;
  @State inputURL: string = '';
  @State inputName: string = '';
  // 当前操作目标服务器（操作菜单/重命名/删除共用）
  @State targetId: string = '';
  @State targetName: string = '';
  // 当前 device_key（Key 弹窗参考用）
  @State currentDeviceKey: string = '';
  // 当前 server 的 per-server client token（客户端 Token 弹窗预填/参考用）
  @State currentClientToken: string = '';
  @State currentEncryptionConfig: EncryptionConfig = new EncryptionConfig();
  private onChange: ((list: ServerEntry[], curId: string) => void) | null = null;
  // 操作菜单 controller（目标由 targetId 持有，回调闭包捕获 this 取最新值）
  private actionMenuController: CustomDialogController = new CustomDialogController({
    builder: ServerActionMenuDialog({
      onCopy: () => {
        this.handleCopy();
      },
      onResetKey: () => {
        this.openKeyDialog();
      },
      onClientToken: () => {
        this.openClientTokenDialog();
      },
      onEncryption: () => {
        this.openEncryptionDialog();
      },
      onRename: () => {
        this.openRenameDialog();
      },
      onDelete: () => {
        this.handleDelete(this.targetId);
      },
    }),
    alignment: DialogAlignment.Center,
    autoCancel: true,
    offset: { dx: 0, dy: 0 },
  });
  private renameController: CustomDialogController = new CustomDialogController({
    builder: ServerRenameDialog({
      getInitName: (): string => this.targetName,
      onConfirm: (newName: string): void => {
        this.handleRename(newName);
      },
    }),
    alignment: DialogAlignment.Center,
    autoCancel: true,
    offset: { dx: 0, dy: 0 },
  });
  private keyController: CustomDialogController = new CustomDialogController({
    builder: ServerKeyDialog({
      getCurrentKey: (): string => this.currentDeviceKey,
      onConfirm: (inputKey: string): void => {
        this.handleResetOrRestore(inputKey);
      },
    }),
    alignment: DialogAlignment.Center,
    autoCancel: true,
    offset: { dx: 0, dy: 0 },
  });
  // per-server 客户端 Token 弹窗（getInitToken 回填当前 server 已配置 token；保存后写入当前 server）
  private clientTokenController: CustomDialogController = new CustomDialogController({
    builder: ClientTokenDialog({
      getInitToken: (): string => this.currentClientToken,
      onSaved: (): void => {
        // 保存后刷新本地缓存，便于再次打开时回填最新值
        this.refreshClientToken();
      },
    }),
    alignment: DialogAlignment.Center,
    autoCancel: true,
    offset: { dx: 0, dy: 0 },
  });
  private encryptionController: CustomDialogController = new CustomDialogController({
    builder: EncryptionSettingsDialog({
      getConfig: (): EncryptionConfig => this.currentEncryptionConfig,
      getServerName: (): string => this.targetName,
      onSave: (config: EncryptionConfig): void => {
        this.saveEncryption(config);
      },
      onClear: (): void => {
        this.clearEncryption();
      },
    }),
    alignment: DialogAlignment.Center,
    autoCancel: true,
  });

  aboutToAppear() {
    this.refresh();
    this.refreshDeviceKey();
    const mgr: ServerManager = ServerManager.getInstance();
    this.onChange = (_list: ServerEntry[], _curId: string): void => {
      this.refresh();
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
        Row({ space: 8 }) {
          if (this.isCurrent(s.id)) {
            Text('●')
              .fontSize(10)
              .fontColor($r('app.color.color_brand'));
          }

          Text(s.name && s.name.length > 0 ? s.name : extractHost(s.baseURL))
            .fontSize(16)
            .fontWeight(this.titleWeight(s.id))
            .fontColor(this.titleColor(s.id))
            .layoutWeight(1);
        }
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

      if (this.isCurrent(s.id)) {
        Text('操作')
          .fontSize(13)
          .fontColor($r('app.color.color_brand'))
          .padding({
            left: 10,
            right: 10,
            top: 6,
            bottom: 6
          })
          .onClick(() => {
            this.openActionMenu(s);
          });
      } else {
        Text('删除')
          .fontSize(13)
          .fontColor($r('app.color.color_error'))
          .padding({
            left: 10,
            right: 10,
            top: 6,
            bottom: 6
          })
          .onClick(() => {
            this.handleDelete(s.id);
          });
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor(this.rowBg(s.id))
    .borderRadius(10)
    .border({ width: 1, color: this.rowBorder(s.id) })
    .onClick(() => {
      this.handleSwitch(s.id);
    });
  }

  build() {
    Column({ space: 14 }) {
      Column({ space: 8 }) {
        TextInput({ placeholder: 'http://host:port 或域名', text: this.inputURL })
          .width('100%')
          .height(48)
          .backgroundColor($r('app.color.color_bg_input'))
          .borderRadius(8)
          .padding({ left: 12, right: 12 })
          .onChange((val: string) => {
            this.inputURL = val;
          });

        TextInput({ placeholder: '名称（可选）', text: this.inputName })
          .width('100%')
          .height(48)
          .backgroundColor($r('app.color.color_bg_input'))
          .borderRadius(8)
          .padding({ left: 12, right: 12 })
          .onChange((val: string) => {
            this.inputName = val;
          });

        Button('添加服务器')
          .width('100%')
          .height(48)
          .fontSize(14)
          .backgroundColor($r('app.color.color_brand'))
          .borderRadius(8)
          .onClick(() => {
            this.handleAdd();
          });
      }
      .width('100%');

      Column({ space: 8 }) {
        // 显示所有服务器通知的开关
        Row() {
          Column({ space: 2 }) {
            Text('显示所有服务器通知')
              .fontSize(15)
              .fontColor($r('app.color.color_text_primary'));
            Text('开启后将聚合展示所有服务器的通知')
              .fontSize(12)
              .fontColor($r('app.color.color_text_hint'));
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1);

          Toggle({ type: ToggleType.Switch, isOn: this.viewAll })
            .selectedColor($r('app.color.color_brand'))
            .onChange((isOn: boolean) => {
              ServerManager.getInstance().setViewAllMode(isOn);
            });
        }
        .width('100%')
        .padding(12)
        .backgroundColor($r('app.color.color_bg_surface'))
        .borderRadius(10)
        .border({ width: 1, color: $r('app.color.color_border_subtle') });

        Text('已保存的服务器（点击切换）')
          .fontSize(13)
          .fontColor($r('app.color.color_text_tertiary'))
          .width('100%');
        if (this.maxListHeight > 0) {
          List({ space: 8 }) {
            ForEach(this.serverList, (s: ServerEntry) => {
              ListItem() {
                this.itemRow(s);
              }
            }, (s: ServerEntry) => `${s.id}|${s.name}`);
          }
          .width('100%')
          .constraintSize({ maxHeight: this.maxListHeight });
        } else {
          List({ space: 8 }) {
            ForEach(this.serverList, (s: ServerEntry) => {
              ListItem() {
                this.itemRow(s);
              }
            }, (s: ServerEntry) => `${s.id}|${s.name}`);
          }
          .width('100%');
        }
      }
      .width('100%');
    }
    .width('100%')
    .align(Alignment.Top);
  }

  private refresh(): void {
    const mgr: ServerManager = ServerManager.getInstance();
    const list: ServerEntry[] = mgr.getList();
    const cur: ServerEntry | null = mgr.getCurrentServer();
    this.currentId = cur ? cur.id : '';
    // 同步视图模式
    this.viewAll = mgr.getViewAllMode();

    // 强制把当前服务器放在列表第一个
    if (cur) {
      const idx: number = list.findIndex((s: ServerEntry) => s.id === cur.id);
      if (idx > 0) {
        const current: ServerEntry = list.splice(idx, 1)[0];
        list.unshift(current);
      }
    }
    this.serverList = list;
  }

  private async refreshDeviceKey(): Promise<void> {
    const k: string | null = await DeviceRegisterService.getInstance().ensureRegistered(null);
    this.currentDeviceKey = k && k.length > 0 ? k : '';
  }

  // 刷新当前 server 的 per-server client token（弹窗预填用；空串 = 未配置，走内置默认）
  private async refreshClientToken(): Promise<void> {
    await ServerManager.getInstance().ensureLoaded();
    this.currentClientToken = ServerManager.getInstance().getCurrentClientToken();
  }

  private findTarget(): ServerEntry | null {
    for (let i = 0; i < this.serverList.length; i++) {
      if (this.serverList[i].id === this.targetId) {
        return this.serverList[i];
      }
    }
    return null;
  }

  private openActionMenu(server: ServerEntry): void {
    this.targetId = server.id;
    this.targetName = server.name;
    try {
      this.actionMenuController.open();
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'action menu open 失败');
      showToast(this.getUIContext(), '操作菜单无法打开');
    }
  }

  private async openRenameDialog(): Promise<void> {
    // targetName 已在 openActionMenu 时设置；直接打开重命名弹窗
    try {
      this.renameController.open();
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'rename dialog open 失败');
      showToast(this.getUIContext(), '弹窗无法打开');
    }
  }

  private async openKeyDialog(): Promise<void> {
    // 刷新当前 device_key 供 Key 弹窗显示参考
    await this.refreshDeviceKey();
    try {
      this.keyController.open();
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'key dialog open 失败');
      showToast(this.getUIContext(), '弹窗无法打开');
    }
  }

  // 打开 per-server 客户端 Token 弹窗：先刷新当前 server 的 token 供预填
  private async openClientTokenDialog(): Promise<void> {
    await this.refreshClientToken();
    try {
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
    this.currentEncryptionConfig = await EncryptionConfigService.get(null, server.id);
    try {
      this.encryptionController.open();
    } catch (_err) {
      hilog.warn(DOMAIN, TAG, 'encryption dialog open 失败');
      showToast(this.getUIContext(), '弹窗无法打开');
    }
  }

  private async saveEncryption(config: EncryptionConfig): Promise<void> {
    const server: ServerEntry | null = this.findTarget();
    if (!server) {
      return;
    }
    config.deviceKey = server.deviceKey;
    const ok: boolean = await EncryptionConfigService.save(null, server.id, config);
    if (ok) {
      this.currentEncryptionConfig = config;
      await this.refreshEncryptedMessages(server.deviceKey);
    }
    showToast(this.getUIContext(), ok ? '加密设置已保存' : '保存失败');
  }

  private async clearEncryption(): Promise<void> {
    const server: ServerEntry | null = this.findTarget();
    if (!server) {
      return;
    }
    const ok: boolean = await EncryptionConfigService.remove(null, server.id);
    if (ok) {
      this.currentEncryptionConfig = new EncryptionConfig();
      await this.refreshEncryptedMessages(server.deviceKey);
    }
    showToast(this.getUIContext(), ok ? '加密设置已清除' : '清除失败');
  }

  private async refreshEncryptedMessages(deviceKey: string): Promise<void> {
    const server: ServerEntry | null = this.findTarget();
    if (server && deviceKey.length > 0) {
      // 远程历史在成功迁移后会删除；配置变更时直接用本地保留的密文重新解密，不能清空缓存。
      await NotifyMessageService.getInstance().redecryptCachedMessages(server);
    }
    const current: number = AppStorage.get<number>(KEY_NOTIFY_REFRESH_SIGNAL) ?? 0;
    AppStorage.setOrCreate(KEY_NOTIFY_REFRESH_SIGNAL, current + 1);
  }

  // 复制 {baseURL}/{device_key} 到剪贴板
  private async handleCopy(): Promise<void> {
    const server: ServerEntry | null = this.findTarget();
    if (!server) {
      showToast(this.getUIContext(), '服务器信息缺失');
      return;
    }
    const key: string | null = await DeviceRegisterService.getInstance().ensureRegistered(null);
    if (!key || key.length === 0) {
      showToast(this.getUIContext(), '未获取到 Key');
      return;
    }
    const text: string = `${server.baseURL}/${key}`;
    const ok: boolean = await this.copyText(text);
    if (ok) {
      showToast(this.getUIContext(), '已复制地址和 Key', 1200);
    } else {
      showToast(this.getUIContext(), '复制失败');
    }
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
    const mgr: ServerManager = ServerManager.getInstance();
    const ok: boolean = await mgr.renameServer(null, this.targetId, newName);
    showToast(this.getUIContext(), ok ? '已重命名' : '重命名失败');
  }

  // inputKey 为空 = 重置；有值 = 还原
  private async handleResetOrRestore(inputKey: string): Promise<void> {
    const svc = DeviceRegisterService.getInstance();
    const key: string | null = await svc.register(null, inputKey.length > 0 ? inputKey : undefined);
    if (key && key.length > 0) {
      this.currentDeviceKey = key;
      showToast(this.getUIContext(), inputKey.length > 0 ? '已还原 Key' : '已重置 Key');
    } else {
      showToast(this.getUIContext(), '操作失败');
    }
  }

  private async handleSwitch(id: string): Promise<void> {
    // 开关状态独立：切换服务器不改变"显示所有服务器通知"开关
    if (id === this.currentId) {
      return;
    }
    // context 传 null，ServerManager 会从 AppContextStore 兜底取
    const mgr: ServerManager = ServerManager.getInstance();
    const ok: boolean = await mgr.switchTo(null, id);
    if (!ok) {
      showToast(this.getUIContext(), '切换失败');
    } else {
      showToast(this.getUIContext(), '已切换服务器', 1200);
    }
  }

  private async handleAdd(): Promise<void> {
    const url: string = this.inputURL.trim();
    if (!url) {
      showToast(this.getUIContext(), '请输入服务器地址');
      return;
    }
    const mgr: ServerManager = ServerManager.getInstance();
    // 先校验格式 + ping 服务器
    const errMsg: string = await mgr.validateAndPing(url);
    if (errMsg.length > 0) {
      showToast(this.getUIContext(), errMsg);
      return;
    }
    const entry: ServerEntry | null = await mgr.addServer(null, url, this.inputName.trim());
    if (entry) {
      showToast(this.getUIContext(), '已添加并切换', 1200);
      this.inputURL = '';
      this.inputName = '';
    } else {
      showToast(this.getUIContext(), '添加失败');
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
      // 服务器删除后同时清除其本地密钥，避免孤立的敏感配置长期残留。
      await EncryptionConfigService.remove(null, id);
      showToast(this.getUIContext(), '已删除', 1200);
    } else {
      showToast(this.getUIContext(), '删除失败');
    }
  }

  private isCurrent(id: string): boolean {
    return id === this.currentId;
  }

  private rowBg(id: string): ResourceColor {
    return this.isCurrent(id) ? $r('app.color.color_state_selected') : $r('app.color.color_bg_surface');
  }

  private rowBorder(id: string): ResourceColor {
    return this.isCurrent(id) ? $r('app.color.color_brand') : $r('app.color.color_border_subtle');
  }

  private titleColor(id: string): ResourceColor {
    return this.isCurrent(id) ? $r('app.color.color_brand') : $r('app.color.color_text_primary');
  }

  private titleWeight(id: string): FontWeight {
    return this.isCurrent(id) ? FontWeight.Bold : FontWeight.Medium;
  }
}
