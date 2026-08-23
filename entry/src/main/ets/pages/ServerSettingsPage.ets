import { hilog } from '@kit.PerformanceAnalysisKit';
import { ServerSettingsContent } from '../components/ServerSettingsContent';

const DOMAIN: number = 0x0000;
const TAG: string = 'ServerSettingsPage';

// 服务器设置页（MineView 点击服务器卡片进入）
@Entry
@Component
struct ServerSettingsPage {
  build() {
    Column() {
      // 顶部栏：返回 + 标题
      Row() {
        Image($r('app.media.arrow_left'))
          .width(32)
          .height(32)
          .objectFit(ImageFit.Contain)
          .fillColor($r('app.color.text_primary_color'))
          .padding(4)
          .onClick(() => {
            this.handleBack();
          });

        Text('服务器设置')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary_color'))
          .layoutWeight(1)
          .textAlign(TextAlign.Center);

        // 占位，平衡标题居中
        Text('')
          .width(56);
      }
      .width('100%')
      .padding({
        left: 8,
        right: 8,
        top: 12,
        bottom: 12
      })
      .backgroundColor($r('app.color.index_page_top_background'))
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP]);

      // 内容区
      Scroll() {
        Column() {
          ServerSettingsContent();
        }
        .width('100%')
        .padding(16);
      }
      .layoutWeight(1)
      .width('100%')
      .backgroundColor($r('app.color.index_page_body_background'))
      .align(Alignment.Top);
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Start)
    .backgroundColor($r('app.color.index_page_body_background'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM]);
  }

  private handleBack(): void {
    try {
      this.getUIContext().getRouter().back();
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, TAG, 'router back 失败：%{public}s', msg);
    }
  }
}
