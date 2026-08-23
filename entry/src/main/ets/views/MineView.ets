import { hilog } from '@kit.PerformanceAnalysisKit';
import { UIContext } from '@kit.ArkUI';
import { ServerEntry } from '../model/ServerEntry';
import { ServerManager } from '../services/ServerManager';
import { extractHost } from '../components/ServerSettingsContent';
import { ClientTokenDialog } from '../components/ClientTokenDialog';
import { NotifyMessageService } from '../services/NotifyMessageService';

const DOMAIN: number = 0x0000;
const TAG: string = 'MineView';

function showToast(ctx: UIContext, message: string, durationMs: number = 1500): void {
  try {
    ctx.getPromptAction().showToast({ message: message, duration: durationMs });
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
  // 用户自定义的 token 原文（持久化层内容）；内置默认时空串
  @State customClientToken: string = '';
  // 是否正在使用内置默认 token
  @State isDefaultClientToken: boolean = true;
  private onChange: ((list: ServerEntry[], curId: string) => void) | null = null;

  // client token 弹窗（打开时回填用户自定义内容；内置默认时显示空 placeholder，用户填即覆盖）
  private tokenDialogController: CustomDialogController = new CustomDialogController({
    builder: ClientTokenDialog({
      getInitToken: (): string => this.customClientToken,
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

            Text(this.buildClientTokenDisplay())
              .fontSize(14)
              .fontColor(this.isDefaultClientToken ? '#FF6F22' : '#666666')
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
    const svc = NotifyMessageService.getInstance();
    this.customClientToken = await svc.getClientToken();
    this.isDefaultClientToken = await svc.isClientTokenDefault();
  }

  /** 卡片展示用：区分内置默认 / 用户自定义两态；token 全程不显示明文 */
  private buildClientTokenDisplay(): string {
    if (this.isDefaultClientToken) {
      return '•••••••• (内置默认 · 可修改)';
    }
    const t: string = this.customClientToken;
    // 用户自定义：只显示占位 + 长度，不暴露原文任何片段
    const masked: string = '••••••••';
    return `${masked} (已配置 · ${t.length} 位)`;
  }

  private handleCardClicked(): void {
    try {
      this.getUIContext().getRouter().pushUrl({ url: 'pages/ServerSettingsPage' });
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, TAG, 'router push 失败：%{public}s', msg);
      showToast(this.getUIContext(), '页面无法打开');
    }
  }

  private openTokenDialog(): void {
    try {
      this.tokenDialogController.open();
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, TAG, 'token dialog open 失败：%{public}s', msg);
      showToast(this.getUIContext(), '弹窗无法打开');
    }
  }
}
