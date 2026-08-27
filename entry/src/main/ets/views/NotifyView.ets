import { hilog } from '@kit.PerformanceAnalysisKit';
import { UIContext } from '@kit.ArkUI';
import { ServerEntry } from '../model/ServerEntry';
import { ServerManager } from '../services/ServerManager';
import { NotifyMessage } from '../model/NotifyMessage';
import { NotifyMessageService } from '../services/NotifyMessageService';
import {
  ServerSettingsDialog
} from '../components/ServerSettingsDialog';

const DOMAIN: number = 0x0000;
const TAG: string = 'NotifyView';

function showToast(ctx: UIContext, message: string, durationMs: number = 1500): void {
  try {
    ctx.getPromptAction().showToast({ message: message, duration: durationMs });
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
  // 触底分页加载更老消息
  @State loadingMore: boolean = false;
  @State hasMore: boolean = true;
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
    // ServerManager 可能还在异步 load，必须先 await ensureLoaded 再读当前 server，
    // 否则 currentId='' 会走兜底生产 URL，显示/请求错误的地址。
    this.initAfterServerManagerReady();
    this.onChange = (_list: ServerEntry[], _curId: string): void => {
      this.refresh();
      // 服务器切换后重新拉取消息
      this.loadMessages();
    };
    ServerManager.getInstance().addChangeListener(this.onChange);
  }

  /** aboutToAppear 是同步签名，这里 fire-and-forget 初始化链 */
  private async initAfterServerManagerReady(): Promise<void> {
    try {
      await ServerManager.getInstance().ensureLoaded();
      this.refresh();
      this.loadMessages();
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, TAG, '初始化失败：%{public}s', msg);
    }
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
            showToast(this.getUIContext(), '删除（待实现）');
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
        .fontColor($r('app.color.text_tertiary_color'));
      Text('查询历史消息需要客户端 Token 认证，请到「我的」页面配置')
        .fontSize(13)
        .fontColor($r('app.color.text_quinary_color'))
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
        .color($r('app.color.text_accent_color'));
      Text('加载中…')
        .fontSize(13)
        .fontColor($r('app.color.text_quinary_color'));
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
        .fontColor($r('app.color.text_error_color'))
        .textAlign(TextAlign.Center)
        .width('80%');
      Text('下拉重试')
        .fontSize(13)
        .fontColor($r('app.color.text_accent_color'))
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
        .fontColor($r('app.color.text_quinary_color'));
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

      // 触底加载指示器
      if (this.loadingMore) {
        ListItem() {
          Row({ space: 6 }) {
            LoadingProgress()
              .width(18)
              .height(18)
              .color($r('app.color.text_accent_color'));
            Text('加载更多…')
              .fontSize(12)
              .fontColor($r('app.color.text_quinary_color'));
          }
          .width('100%')
          .height(44)
          .justifyContent(FlexAlign.Center);
        }
      } else if (!this.hasMore && this.messages.length > 0) {
        ListItem() {
          Text('没有更多了')
            .fontSize(12)
            .fontColor($r('app.color.text_quinary_color'))
            .width('100%')
            .height(40)
            .textAlign(TextAlign.Center);
        }
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
    .align(Alignment.Top)
    .onReachEnd(() => {
      // 列表按时间倒序（新→旧），末尾是最旧消息；取末尾消息 ID 作 since 加载更老的
      this.loadMore();
    });
  }

  @Builder
  messageRow(m: NotifyMessage) {
    Column({ space: 6 }) {
      if (m.title && m.title.length > 0) {
        Text(m.title)
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary_color'))
          .width('100%')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
      }
      if (m.subtitle && m.subtitle.length > 0) {
        Text(m.subtitle)
          .fontSize(13)
          .fontColor($r('app.color.text_accent_color'))
          .width('100%')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
      }
      if (m.body && m.body.length > 0) {
        Text(m.body)
          .fontSize(14)
          .fontColor($r('app.color.text_secondary_color'))
          .width('100%')
          .maxLines(4)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
      }
      Text(this.formatTime(m.timestamp))
        .fontSize(11)
        .fontColor($r('app.color.text_quinary_color'))
        .width('100%')
        .textAlign(TextAlign.End);
    }
    .width('100%')
    .padding(12)
    .backgroundColor($r('app.color.card_background'))
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
        // 首次拉取/下拉刷新 → 重置分页状态，允许后续触底加载
        this.hasMore = this.messages.length > 0;
      } else {
        this.errorMsg = result.errorMsg;
        // 仅首次拉取失败清空列表；刷新失败保留旧数据
        if (this.messages.length === 0) {
          this.messages = [];
        }
      }
      // 是否有可用 client token（用户自定义 or 内置默认），用于引导态判断
      this.hasClientToken = await NotifyMessageService.getInstance().hasEffectiveClientToken();
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, TAG, 'loadMessages 异常：%{public}s', msg);
      this.errorMsg = '加载失败';
    } finally {
      this.loading = false;
      this.refreshing = false;
    }
  }

  // 触底加载更多：取当前列表末尾（最旧）消息的 ID 作 since，请求更老的消息
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
      const result = await NotifyMessageService.getInstance().getMessages(null, oldest.id, PAGE_SIZE);
      if (result.ok) {
        const newItems: NotifyMessage[] = result.messages.sort((a: NotifyMessage, b: NotifyMessage) => b.timestamp - a.timestamp);
        if (newItems.length === 0) {
          this.hasMore = false;
        } else {
          // 去重：过滤掉已经存在的 ID（避免后端返回包含 oldest.id 本身导致重复）
          const existingIds: Set<number> = new Set<number>();
          for (let i = 0; i < this.messages.length; i++) {
            existingIds.add(this.messages[i].id);
          }
          const deduped: NotifyMessage[] = [];
          for (let i = 0; i < newItems.length; i++) {
            const m: NotifyMessage = newItems[i];
            if (!existingIds.has(m.id)) {
              deduped.push(m);
            }
          }
          if (deduped.length === 0) {
            // 全部重复 → 后端实际没有更老消息
            this.hasMore = false;
          } else {
            // 列表按时间倒序（新→旧），追加到末尾保持顺序
            this.messages = this.messages.concat(deduped);
            // 返回不足一页（< limit）→ 已到底；否则保持 hasMore=true 允许继续翻
            if (newItems.length < PAGE_SIZE) {
              this.hasMore = false;
            }
          }
        }
      }
      // loadMore 失败不弹错误提示，避免打扰用户；日志已由 service 层打印
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, TAG, 'loadMore 异常：%{public}s', msg);
    } finally {
      this.loadingMore = false;
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
      showToast(this.getUIContext(), '弹窗无法打开');
    }
  }
}
