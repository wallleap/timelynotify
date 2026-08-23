import { hilog } from '@kit.PerformanceAnalysisKit';
import { promptAction, router } from '@kit.ArkUI';
import { ServerEntry } from '../model/ServerEntry';
import { ServerManager } from '../services/ServerManager';
import { extractHost } from '../components/ServerSettingsContent';
import { ClientTokenDialog } from '../components/ClientTokenDialog';
import { NotifyMessageService } from '../services/NotifyMessageService';

const DOMAIN: number = 0x0000;
const TAG: string = 'MineView';

function showToast(message: string, durationMs: number = 1500): void {
  try {
    promptAction.showToast({ message: message, duration: durationMs });
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    hilog.warn(DOMAIN, TAG, 'Toast 调用失败：%{public}s', msg);
  }
}

// 我的页 - 展示个人设置入口
@Component
export struct MineView {
  @State hostDisplay: string = '';
  @State serverName: string = '';
  @State serverCount: number = 0;
  @State clientTokenDisplay: string = '';
  private onChange: ((list: ServerEntry[], curId: string) => void) | null = null;

  // client token 弹窗（保存后刷新展示）
  private tokenDialogController: CustomDialogController = new CustomDialogController({
    builder: ClientTokenDialog({
      getInitToken: (): string => this.clientTokenDisplay,
      onSaved: (): void => { this.refreshClientToken(); },
    }),
    alignment: DialogAlignment.Center,
    autoCancel: true,
    offset: { dx: 0, dy: 0 },
  });

  aboutToAppear() {
    this.refreshSummary();
    this.refreshClientToken();
    this.onChange = (_list: ServerEntry[], _curId: string): void => {
      this.refreshSummary();
    };
    ServerManager.getInstance().addChangeListener(this.onChange);
  }

  aboutToDisappear() {
    if (this.onChange) {
      ServerManager.getInstance().removeChangeListener(this.onChange);
    }
  }

  build() {
    Column() {
      // 顶部标题栏
      Row() {
        Text('我的')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .width('100%')
          .textAlign(TextAlign.Center);
      }
      .width('100%')
      .padding(16)
      .backgroundColor($r('app.color.index_page_top_background'));

      Column({ space: 12 }) {
        // 服务器入口卡片
        Row({ space: 14 }) {
          Column({ space: 4 }) {
            Row() {
              Text('服务器')
                .fontSize(17)
                .fontWeight(FontWeight.Medium)
                .fontColor('#111111');
              Blank();
              Text(`共 ${this.serverCount} 个`)
                .fontSize(12)
                .fontColor('#999999');
            }
            .width('100%');

            Text(this.serverName)
              .fontSize(14)
              .fontColor('#666666')
              .width('100%')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis });

            Text(this.hostDisplay)
              .fontSize(12)
              .fontColor('#FF6F22')
              .width('100%')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis });
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1);

          Image($r('app.media.arrow_right'))
            .width(32)
            .height(32)
            .objectFit(ImageFit.Contain)
            .fillColor($r('app.color.text_primary_color'))
            .padding(4)
        }
        .width('100%')
        .padding(16)
        .backgroundColor('#FFFFFF')
        .borderRadius(12)
        .onClick(() => {
          this.handleCardClicked();
        });

        // 客户端 Token 卡片
        Row({ space: 14 }) {
          Column({ space: 4 }) {
            Text('客户端 Token')
              .fontSize(17)
              .fontWeight(FontWeight.Medium)
              .fontColor('#111111')
              .width('100%');

            Text(this.clientTokenDisplay.length > 0 ? this.clientTokenDisplay : '未配置')
              .fontSize(14)
              .fontColor(this.clientTokenDisplay.length > 0 ? '#666666' : '#999999')
              .width('100%')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis });
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1);

          Image($r('app.media.arrow_right'))
            .width(32)
            .height(32)
            .objectFit(ImageFit.Contain)
            .fillColor($r('app.color.text_primary_color'))
            .padding(4)
        }
        .width('100%')
        .padding(16)
        .backgroundColor('#FFFFFF')
        .borderRadius(12)
        .onClick(() => {
          this.openTokenDialog();
        });
      }
      .layoutWeight(1)
      .width('100%')
      .padding(16);
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.index_page_body_background'));
  }

  private refreshSummary(): void {
    const mgr: ServerManager = ServerManager.getInstance();
    const cur: ServerEntry | null = mgr.getCurrentServer();
    if (cur) {
      this.hostDisplay = extractHost(cur.baseURL);
      this.serverName = cur.name && cur.name.length > 0 ? cur.name : cur.baseURL;
    } else {
      this.hostDisplay = '';
      this.serverName = '';
    }
    this.serverCount = mgr.getList().length;
  }

  private async refreshClientToken(): Promise<void> {
    this.clientTokenDisplay = await NotifyMessageService.getInstance().getClientToken();
  }

  private handleCardClicked(): void {
    try {
      router.pushUrl({ url: 'pages/ServerSettingsPage' });
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, TAG, 'router push 失败：%{public}s', msg);
      showToast('页面无法打开');
    }
  }

  private openTokenDialog(): void {
    try {
      this.tokenDialogController.open();
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, TAG, 'token dialog open 失败：%{public}s', msg);
      showToast('弹窗无法打开');
    }
  }
}
