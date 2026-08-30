import { hilog } from '@kit.PerformanceAnalysisKit';
import { ServerSettingsContent } from '../components/ServerSettingsContent';
import { resolveBlurStyle } from '../utils/ImmersiveUtil';
import { DOMAIN } from '../common/Constant';

const TAG: string = 'ServerSettingsPage';

// 服务器设置页（MineView 点击服务器卡片进入）
@Entry
@Component
struct ServerSettingsPage {
  // 状态栏/导航条高度（vp），EntryAbility 沉浸式布局初始化时写入 AppStorage（键值见 ImmersiveUtil）
  @StorageProp('statusBarHeight') statusBarHeight: number = 36;
  @StorageProp('navBarHeight') navBarHeight: number = 0;

  @Builder
  topBarContent() {
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

  build() {
    // ─── Stack + 自定义顶栏（barBackgroundBlurStyle 毛玻璃）───
    // （历史说明：曾有 API 26+ HdsNavigation 沉浸光感分支，因 AGC 拒绝 beta API 已移除）
    Stack({ alignContent: Alignment.Top }) {
      Scroll() {
        Column() {
          Row()
            .width('100%')
            .height(this.statusBarHeight + 72);

          ServerSettingsContent();
        }
        .width('100%')
        .padding({
          left: 16,
          right: 16,
          bottom: 16 + this.navBarHeight
        });
      }
      .width('100%')
      .height('100%')
      .edgeEffect(EdgeEffect.Spring)
      .align(Alignment.Top);

      Row() {
        this.topBarContent();
      }
      .width('100%')
      .padding({
        left: 8,
        right: 8,
        top: 16 + this.statusBarHeight,
        bottom: 12
      })
      .backgroundBlurStyle(resolveBlurStyle('bar')!, { scale: 1.0 })
      .backgroundColor($r('app.color.index_page_top_glass_background'));
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.index_page_body_background'));
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
