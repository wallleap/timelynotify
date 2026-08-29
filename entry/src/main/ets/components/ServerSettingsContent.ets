import { hilog } from '@kit.PerformanceAnalysisKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { ServerEntry } from '../model/ServerEntry';
import { ServerManager } from '../services/ServerManager';
import { DeviceRegisterService } from '../services/DeviceRegisterService';
import { ServerActionMenuDialog, ServerKeyDialog, ServerRenameDialog, } from './ServerActionDialogs';
import showToast from './showToast';
import { DOMAIN } from '../common/Constant';

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
  @State inputURL: string = '';
  @State inputName: string = '';
  // 当前操作目标服务器（操作菜单/重命名/删除共用）
  @State targetId: string = '';
  @State targetName: string = '';
  // 当前 device_key（Key 弹窗参考用）
  @State currentDeviceKey: string = '';
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
              .fontColor($r('app.color.text_accent_color'));
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
          .fontColor($r('app.color.text_quinary_color'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%');
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1);

      if (this.isCurrent(s.id)) {
        Text('操作')
          .fontSize(13)
          .fontColor($r('app.color.text_accent_color'))
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
          .fontColor($r('app.color.text_error_color'))
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
          .backgroundColor($r('app.color.input_background_color'))
          .borderRadius(8)
          .padding({ left: 12, right: 12 })
          .onChange((val: string) => {
            this.inputURL = val;
          });

        TextInput({ placeholder: '名称（可选）', text: this.inputName })
          .width('100%')
          .height(48)
          .backgroundColor($r('app.color.input_background_color'))
          .borderRadius(8)
          .padding({ left: 12, right: 12 })
          .onChange((val: string) => {
            this.inputName = val;
          });

        Button('添加服务器')
          .width('100%')
          .height(48)
          .fontSize(14)
          .backgroundColor($r('app.color.text_accent_color'))
          .borderRadius(8)
          .onClick(() => {
            this.handleAdd();
          });
      }
      .width('100%');

      Column({ space: 8 }) {
        Text('已保存的服务器（点击切换）')
          .fontSize(13)
          .fontColor($r('app.color.text_tertiary_color'))
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
          { text: '取消', color: $r('app.color.text_tertiary_color') },
          { text: '确定', color: $r('app.color.text_error_color') },
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
      showToast(this.getUIContext(), '已删除', 1200);
    } else {
      showToast(this.getUIContext(), '删除失败');
    }
  }

  private isCurrent(id: string): boolean {
    return id === this.currentId;
  }

  private rowBg(id: string): ResourceColor {
    return this.isCurrent(id) ? $r('app.color.selected_row_background') : $r('app.color.card_background');
  }

  private rowBorder(id: string): ResourceColor {
    return this.isCurrent(id) ? $r('app.color.text_accent_color') : $r('app.color.divider_color');
  }

  private titleColor(id: string): ResourceColor {
    return this.isCurrent(id) ? $r('app.color.text_accent_color') : $r('app.color.text_primary_color');
  }

  private titleWeight(id: string): FontWeight {
    return this.isCurrent(id) ? FontWeight.Bold : FontWeight.Medium;
  }
}
