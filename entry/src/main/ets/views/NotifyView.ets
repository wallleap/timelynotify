import { hilog } from '@kit.PerformanceAnalysisKit';
import { promptAction } from '@kit.ArkUI';
import { ServerEntry } from '../model/ServerEntry';
import { ServerManager } from '../services/ServerManager';
import { NotifyMessage } from '../model/NotifyMessage';
import { NotifyMessageService } from '../services/NotifyMessageService';
import {
  ServerSettingsDialog
} from '../components/ServerSettingsDialog';

const DOMAIN: number = 0x0000;
const TAG: string = 'NotifyView';

function showToast(message: string, durationMs: number = 1500): void {
  try {
    promptAction.showToast({ message: message, duration: durationMs });
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    hilog.warn(DOMAIN, TAG, 'Toast 调用失败：%{public}s', msg);
  }
}

// 通知页 - 展示接收到的 HTTP 推送消息列表
@Component
export struct NotifyView {
  @State title: string = '';
  @State messages: NotifyMessage[] = [];
  @State loading: boolean = false;
  @State errorMsg: string = '';
  @State refreshing: boolean = false;
  @State hasClientToken: boolean = false;
  // ⚠️ ArkUI 官方模式：CustomDialogController 必须在 struct 字段声明时直接初始化
  private dialogController: CustomDialogController = new CustomDialogController({
    builder: ServerSettingsDialog(),
    alignment: DialogAlignment.Center,
    autoCancel: true,
    offset: { dx: 0, dy: 0 },
  });
  private onChange: ((list: ServerEntry[], curId: string) => void) | null = null;
  private scroller: Scroller = new Scroller();

  aboutToAppear() {
    this.refresh();
    this.loadMessages();
    this.onChange = (_list: ServerEntry[], _curId: string): void => {
      this.refresh();
      // 服务器切换后重新拉取消息
      this.loadMessages();
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
      // 顶部栏：内层 Row（title + select_more，长域名省略）+ delete 图标
      Row({ space: 8 }) {
        Row({ space: 2 }) {
          Text(this.title)
            .fontSize(24)
            .fontColor($r('app.color.text_primary_color'))
            .fontWeight(FontWeight.Bold)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis });

          Image($r('app.media.select_more'))
            .width(24)
            .height(24)
            .objectFit(ImageFit.Contain)
            .fillColor($r('app.color.text_primary_color'))
            .flexShrink(0)
            .onClick(() => {
              this.handleMoreClicked();
            });
        }
        .layoutWeight(1)
        .width(0)
        .padding({ right: 48 })
        .alignItems(VerticalAlign.Center)
        .onClick(() => {
          this.handleMoreClicked();
        });

        Image($r('app.media.delete'))
          .width(32)
          .height(32)
          .objectFit(ImageFit.Contain)
          .fillColor($r('app.color.text_primary_color'))
          .padding(4)
          .onClick(() => {
            showToast('删除（待实现）');
          });
      }
      .width('100%')
      .padding(16)
      .alignItems(VerticalAlign.Center)
      .backgroundColor($r('app.color.index_page_top_background'));

      // 内容区域
      Refresh({ refreshing: $$this.refreshing }) {
        if (this.needGuideToConfig()) {
          this.guideView();
        } else if (this.loading && this.messages.length === 0) {
          this.loadingView();
        } else if (this.errorMsg.length > 0 && this.messages.length === 0) {
          this.errorView();
        } else if (this.messages.length === 0) {
          this.emptyView();
        } else {
          this.listView();
        }
      }
      .layoutWeight(1)
      .width('100%')
      .onRefreshing(() => {
        this.loadMessages();
      });
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.index_page_body_background'));
  }

  // 未配置 client token 或未注册 → 引导到"我的"页配置
  private needGuideToConfig(): boolean {
    return !this.loading && !this.hasClientToken && this.errorMsg.length > 0;
  }

  @Builder
  guideView() {
    Column({ space: 12 }) {
      Text('未配置客户端 Token')
        .fontSize(16)
        .fontColor('#666666');
      Text('查询历史消息需要客户端 Token 认证，请到「我的」页面配置')
        .fontSize(13)
        .fontColor('#999999')
        .textAlign(TextAlign.Center)
        .width('70%');
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center);
  }

  @Builder
  loadingView() {
    Column({ space: 8 }) {
      LoadingProgress()
        .width(40)
        .height(40)
        .color('#FF6F22');
      Text('加载中…')
        .fontSize(13)
        .fontColor('#999999');
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center);
  }

  @Builder
  errorView() {
    Column({ space: 12 }) {
      Text(this.errorMsg)
        .fontSize(14)
        .fontColor('#FF3B30')
        .textAlign(TextAlign.Center)
        .width('80%');
      Text('下拉重试')
        .fontSize(13)
        .fontColor('#FF6F22')
        .padding(8)
        .onClick(() => {
          this.loadMessages();
        });
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center);
  }

  @Builder
  emptyView() {
    Column({ space: 8 }) {
      Text('暂无消息')
        .fontSize(15)
        .fontColor('#999999');
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center);
  }

  @Builder
  listView() {
    List({ space: 8, scroller: this.scroller }) {
      ForEach(this.messages, (m: NotifyMessage) => {
        ListItem() {
          this.messageRow(m);
        }
      }, (m: NotifyMessage) => `${m.id}|${m.timestamp}`);
    }
    .width('100%')
    .height('100%')
    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
    .align(Alignment.Top);
  }

  @Builder
  messageRow(m: NotifyMessage) {
    Column({ space: 6 }) {
      if (m.title && m.title.length > 0) {
        Text(m.title)
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor('#111111')
          .width('100%')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
      }
      if (m.subtitle && m.subtitle.length > 0) {
        Text(m.subtitle)
          .fontSize(13)
          .fontColor('#FF6F22')
          .width('100%')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
      }
      if (m.body && m.body.length > 0) {
        Text(m.body)
          .fontSize(14)
          .fontColor('#333333')
          .width('100%')
          .maxLines(4)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
      }
      Text(this.formatTime(m.timestamp))
        .fontSize(11)
        .fontColor('#999999')
        .width('100%')
        .textAlign(TextAlign.End);
    }
    .width('100%')
    .padding(12)
    .backgroundColor('#FFFFFF')
    .borderRadius(10)
    .alignItems(HorizontalAlign.Start);
  }

  private refresh(): void {
    this.title = ServerManager.getInstance().getCurrentHostDisplay();
  }

  private async loadMessages(): Promise<void> {
    if (this.loading) {
      this.refreshing = false;
      return;
    }
    this.loading = true;
    // 清空旧错误，避免短暂闪烁旧错误态
    this.errorMsg = '';
    try {
      const result = await NotifyMessageService.getInstance().getMessages(null);
      if (result.ok) {
        // 按时间倒序（新消息在上）
        this.messages = result.messages.sort((a: NotifyMessage, b: NotifyMessage) => b.timestamp - a.timestamp);
        this.errorMsg = '';
      } else {
        this.errorMsg = result.errorMsg;
        // 仅首次拉取失败清空列表；刷新失败保留旧数据
        if (this.messages.length === 0) {
          this.messages = [];
        }
      }
      // 是否已配置 client token（用于引导态判断）
      this.hasClientToken = (await NotifyMessageService.getInstance().getClientToken()).length > 0;
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, TAG, 'loadMessages 异常：%{public}s', msg);
      this.errorMsg = '加载失败';
    } finally {
      this.loading = false;
      this.refreshing = false;
    }
  }

  private formatTime(ts: number): string {
    if (!ts) {
      return '';
    }
    const d = new Date(ts);
    const y: number = d.getFullYear();
    const mo: string = String(d.getMonth() + 1).padStart(2, '0');
    const da: string = String(d.getDate()).padStart(2, '0');
    const h: string = String(d.getHours()).padStart(2, '0');
    const mi: string = String(d.getMinutes()).padStart(2, '0');
    return `${y}-${mo}-${da} ${h}:${mi}`;
  }

  private handleMoreClicked(): void {
    try {
      this.dialogController.open();
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, TAG, 'dialog open 失败：%{public}s', msg);
      showToast('弹窗无法打开');
    }
  }
}
