import { hilog } from '@kit.PerformanceAnalysisKit';
import { promptAction } from '@kit.ArkUI';
import { ServerEntry } from '../model/ServerEntry';
import { ServerManager } from '../services/ServerManager';

const DOMAIN: number = 0x0000;
const TAG: string = 'ServerDlg';

// Toast 统一封装（捕获异常 + 消除 deprecated/抛错 WARN）
function showToast(message: string, durationMs: number = 1500): void {
  try {
    promptAction.showToast({ message: message, duration: durationMs });
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    hilog.warn(DOMAIN, TAG, 'Toast 调用失败：%{public}s', msg);
  }
}

// 空 builder 占位（用于给 controller 字段做默认值，避免 SDK 注入前的空引用崩溃）
@Builder
function emptyDialogBuilder(): void {
}

// 服务器设置弹窗（NotifyView、MineView 共享）
// 不再通过构造参数传 context：持久化所需 context 从 AppContextStore 全局取（EntryAbility.onCreate 已注入）
@CustomDialog
export struct ServerSettingsDialog {
  // controller 由 SDK 自动注入；放一个占位实例作默认值，避免"未初始化/注入未生效"NPE
  controller: CustomDialogController = new CustomDialogController({
    builder: emptyDialogBuilder(),
    autoCancel: true,
    alignment: DialogAlignment.Center,
    offset: { dx: 0, dy: 0 },
  });

  @State serverList: ServerEntry[] = [];
  @State currentId: string = '';
  @State inputURL: string = '';
  @State inputName: string = '';

  private onChange: ((list: ServerEntry[], curId: string) => void) | null = null;

  aboutToAppear() {
    this.refresh();
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

  private refresh(): void {
    const mgr: ServerManager = ServerManager.getInstance();
    this.serverList = mgr.getList();
    const cur: ServerEntry | null = mgr.getCurrentServer();
    this.currentId = cur ? cur.id : '';
  }

  private async handleSwitch(id: string): Promise<void> {
    if (id === this.currentId) {
      return;
    }
    // context 传 null，ServerManager 会从 AppContextStore 兜底取
    const mgr: ServerManager = ServerManager.getInstance();
    const ok: boolean = await mgr.switchTo(null, id);
    if (!ok) {
      showToast('切换失败');
    } else {
      showToast('已切换服务器', 1200);
    }
  }

  private async handleAdd(): Promise<void> {
    const url: string = this.inputURL.trim();
    if (!url) {
      showToast('请输入服务器地址');
      return;
    }
    const mgr: ServerManager = ServerManager.getInstance();
    // 先校验格式 + ping 服务器
    const errMsg: string = await mgr.validateAndPing(url);
    if (errMsg.length > 0) {
      showToast(errMsg);
      return;
    }
    const entry: ServerEntry | null = await mgr.addServer(null, url, this.inputName.trim());
    if (entry) {
      showToast('已添加并切换', 1200);
      this.inputURL = '';
      this.inputName = '';
    } else {
      showToast('添加失败');
    }
  }

  private async handleDelete(id: string): Promise<void> {
    const mgr: ServerManager = ServerManager.getInstance();
    if (mgr.getList().length <= 1) {
      showToast('至少保留一个服务器');
      return;
    }
    const ok: boolean = await mgr.deleteServer(null, id);
    if (ok) {
      showToast('已删除', 1200);
    } else {
      showToast('删除失败');
    }
  }

  private isCurrent(id: string): boolean {
    return id === this.currentId;
  }

  private rowBg(id: string): ResourceColor {
    return this.isCurrent(id) ? '#FFF3E8' : '#FFFFFF';
  }

  private rowBorder(id: string): ResourceColor {
    return this.isCurrent(id) ? '#FF6F22' : '#EEEEEE';
  }

  private titleColor(id: string): ResourceColor {
    return this.isCurrent(id) ? '#FF6F22' : '#111111';
  }

  private titleWeight(id: string): FontWeight {
    return this.isCurrent(id) ? FontWeight.Bold : FontWeight.Medium;
  }

  @Builder
  itemRow(s: ServerEntry) {
    Row({ space: 12 }) {
      Column({ space: 2 }) {
        Row({ space: 8 }) {
          Text(s.name && s.name.length > 0 ? s.name : extractHost(s.baseURL))
            .fontSize(16)
            .fontWeight(this.titleWeight(s.id))
            .fontColor(this.titleColor(s.id))
            .layoutWeight(1);

          if (this.isCurrent(s.id)) {
            Text('●')
              .fontSize(10)
              .fontColor('#FF6F22');
          }
        }
        .width('100%');

        Text(s.baseURL)
          .fontSize(12)
          .fontColor('#999999')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%');
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1);

      Text('删除')
        .fontSize(13)
        .fontColor('#FF3B30')
        .padding({ left: 10, right: 10, top: 6, bottom: 6 })
        .onClick(() => {
          this.handleDelete(s.id);
        });
    }
    .width('100%')
    .padding(14)
    .backgroundColor(this.rowBg(s.id))
    .borderRadius(10)
    .border({ width: 1, color: this.rowBorder(s.id) })
    .onClick(() => {
      this.handleSwitch(s.id);
    });
  }

  build() {
    Column({ space: 14 }) {
      Text('服务器设置')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .width('100%')
        .textAlign(TextAlign.Center);

      Column({ space: 8 }) {
        TextInput({ placeholder: 'http://host:port 或域名', text: this.inputURL })
          .width('100%')
          .height(40)
          .backgroundColor('#F5F5F5')
          .borderRadius(8)
          .padding({ left: 12, right: 12 })
          .onChange((val: string) => {
            this.inputURL = val;
          });

        TextInput({ placeholder: '名称（可选）', text: this.inputName })
          .width('100%')
          .height(40)
          .backgroundColor('#F5F5F5')
          .borderRadius(8)
          .padding({ left: 12, right: 12 })
          .onChange((val: string) => {
            this.inputName = val;
          });

        Button('添加服务器')
          .width('100%')
          .height(42)
          .fontSize(14)
          .backgroundColor('#FF6F22')
          .borderRadius(8)
          .onClick(() => {
            this.handleAdd();
          });
      }
      .width('100%');

      Column({ space: 8 }) {
        Text('已保存的服务器（点击切换）')
          .fontSize(13)
          .fontColor('#666666')
          .width('100%');
        List({ space: 8 }) {
          ForEach(this.serverList, (s: ServerEntry) => {
            ListItem() {
              this.itemRow(s);
            }
          }, (s: ServerEntry) => s.id);
        }
        .width('100%')
        .constraintSize({ maxHeight: 280 });
      }
      .width('100%');

      Text('关闭')
        .fontSize(14)
        .fontColor('#999999')
        .padding(8)
        .onClick(() => {
          try {
            if (this.controller) {
              this.controller.close();
            }
          } catch (err) {
            hilog.warn(DOMAIN, TAG, 'close dialog 调用失败');
          }
        });
    }
    .width('92%')
    .padding(18)
    .backgroundColor('#FFFFFF')
    .borderRadius(14);
  }
}

// 抽出 extractHost 到文件级（MineView/NotifyView 都可以复用）
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
