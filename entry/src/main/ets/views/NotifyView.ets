import { hilog } from '@kit.PerformanceAnalysisKit';
import { promptAction } from '@kit.ArkUI';
import { ServerEntry } from '../model/ServerEntry';
import { ServerManager } from '../services/ServerManager';
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
  // ⚠️ ArkUI 官方模式：CustomDialogController 必须在 struct 字段声明时直接初始化
  // 此时 ArkUI 在构建组件实例时会把 controller 和组件绑定（attach），之后任意时刻 open 都不会 native 崩
  private dialogController: CustomDialogController = new CustomDialogController({
    builder: ServerSettingsDialog(),
    alignment: DialogAlignment.Center,
    autoCancel: true,
    offset: { dx: 0, dy: 0 },
  });
  private onChange: ((list: ServerEntry[], curId: string) => void) | null = null;

  aboutToAppear() {
    this.refresh();
    this.onChange = (_list: ServerEntry[], _curId: string): void => {
      this.refresh();
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

      // 内容区域（待填充消息列表）
      Column() {
        Blank();
      }
      .layoutWeight(1)
      .width('100%');
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.index_page_body_background'));
  }

  private refresh(): void {
    this.title = ServerManager.getInstance().getCurrentHostDisplay();
  }

  private handleMoreClicked(): void {
    // 声明期已经初始化好并 attach 的 controller，直接 open。同步调用不会崩。
    try {
      this.dialogController.open();
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, TAG, 'dialog open 失败：%{public}s', msg);
      showToast('弹窗无法打开');
    }
  }
}
