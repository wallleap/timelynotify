import { hilog } from '@kit.PerformanceAnalysisKit';
import { ServerSettingsContent } from '../components/ServerSettingsContent';
import { resolveBlurStyle } from '../utils/ImmersiveUtil';

const DOMAIN: number = 0x0000;
const TAG: string = 'ServerSettingsPage';

// 服务器设置页（MineView 点击服务器卡片进入）
@Entry
@Component
struct ServerSettingsPage {
  build() {
    // Stack 层叠：内容层在下、顶栏在上，滚动内容从顶栏下方穿过，毛玻璃才有内容可糊
    Stack({ alignContent: Alignment.Top }) {
      // 内容层（先声明，位于下层）：铺满安全区，滚动时内容滑入顶栏下方
      Scroll() {
        Column() {
          // 顶部占位：随内容一起滚动，内容才能滑入顶栏毛玻璃下方（padding 是硬边界做不到）
          Row()
            .width('100%')
            .height(72);

          ServerSettingsContent();
        }
        .width('100%')
        .padding({
          left: 16,
          right: 16,
          bottom: 16
        });
      }
      .width('100%')
      .height('100%')
      .align(Alignment.Top);

      // 顶栏（后声明，覆盖在上层）：毛玻璃 + 半透明底色，绘制延伸到状态栏
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
      .backgroundBlurStyle(resolveBlurStyle('bar'), { scale: 1.0 })
      .backgroundColor($r('app.color.index_page_top_background'))
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP]);
    }
    .width('100%')
    .height('100%')
    // 根容器铺不透明底色（含状态栏/导航条区域），body 模糊无内容可糊已移除
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
