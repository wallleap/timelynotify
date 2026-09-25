import { hilog } from '@kit.PerformanceAnalysisKit';
import { UIContext } from '@kit.ArkUI';
import { ServerEntry } from '../../model/ServerEntry';
import { ServerManager } from '../../services/ServerManager';
import { extractHost } from '../ServerSettingsContent';
import showToast from '../showToast';
import { resolveBlurStyle } from '../../utils/ImmersiveUtil';
import { DOMAIN } from '../../common/Constant';

const TAG: string = 'ServerEntrySec';

/**
 * 「配置」板块：服务器入口卡片（标题 + 当前服务器名称标签 + host + 数量 + 箭头）。
 * 全自治：自身监听 ServerManager 变更并刷新，点击跳转 ServerSettingsPage。
 */
@Component
export struct ServerEntrySection {
  @State hostDisplay: string = '';
  @State serverName: string = '';
  @State serverCount: number = 0;
  private onChange: ((list: ServerEntry[], curId: string) => void) | null = null;

  aboutToAppear() {
    this.refreshSummary();
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

  @Builder
  arrowRightIcon() {
    Image($r('app.media.arrow_right'))
      .width(20)
      .height(20)
      .objectFit(ImageFit.Contain)
      .fillColor($r('app.color.color_text_hint'))
      .draggable(false);
  }

  build() {
    Column({ space: 8 }) {
      Text('配置')
        .fontSize(12)
        .fontColor($r('app.color.color_text_hint'))
        .width('100%')
        .padding({ left: 12 });

      Column({ space: 10 }) {
        Row({ space: 14 }) {
          Column({ space: 4 }) {
            // 第一行：标题 + 当前服务器名称标签（仅有自定义名称时显示）；
            // 标题 flexShrink(0) 固定不压缩，标签 flexShrink(1) 允许压缩，超长时标签内省略号收尾
            Row({ space: 8 }) {
              Text('服务器')
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.color_text_primary'))
                .flexShrink(0);
              if (this.serverName.length > 0) {
                Text(this.serverName)
                  .fontSize(11)
                  .fontColor($r('app.color.color_brand'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .padding({
                    left: 6,
                    right: 6,
                    top: 2,
                    bottom: 2
                  })
                  .borderRadius(4)
                  .backgroundColor($r('app.color.color_state_selected'))
                  .flexShrink(1);
              }
            }.width('100%').alignItems(VerticalAlign.Center);

            // 第二行：仅展示服务器链接；Text 置于 Column 中宽度有界，超长自动省略号
            if (this.hostDisplay.length > 0) {
              Text(this.hostDisplay)
                .fontSize(12)
                .fontColor($r('app.color.color_text_hint'))
                .width('100%')
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis });
            }
          }.alignItems(HorizontalAlign.Start).layoutWeight(1);

          Row() {
            Text(`共 ${this.serverCount} 个`).fontSize(12).fontColor($r('app.color.color_text_hint'));
            this.arrowRightIcon();
          }
        }
        .width('100%')
        .padding(16)
        .backgroundBlurStyle(resolveBlurStyle('bar')!)
        .backgroundColor($r('app.color.color_bg_surface_glass'))
        .borderRadius(12)
        .onClick(() => {
          this.handleCardClicked();
        });
      }.width('100%')
    }.width('100%');
  }

  private refreshSummary(): void {
    const mgr: ServerManager = ServerManager.getInstance();
    const cur: ServerEntry | null = mgr.getCurrentServer();
    if (cur) {
      this.hostDisplay = extractHost(cur.baseURL);
      // 名称标签仅展示用户自定义名称；未命名时留空（标签不渲染），链接行单独展示 host
      this.serverName = cur.name && cur.name.length > 0 ? cur.name : '';
    } else {
      this.hostDisplay = '';
      this.serverName = '';
    }
    this.serverCount = mgr.getList().length;
  }

  private async handleCardClicked(): Promise<void> {
    const uiCtx: UIContext = this.getUIContext();
    try {
      await uiCtx.getRouter().pushUrl({ url: 'pages/ServerSettingsPage' });
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, TAG, 'router push 失败：%{public}s', msg);
      showToast(uiCtx, '页面无法打开');
    }
  }
}
