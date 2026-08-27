import { hilog } from '@kit.PerformanceAnalysisKit';
import { webview } from '@kit.ArkWeb';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { SOURCE_CODE_URL } from '../views/MineView';

const DOMAIN: number = 0x0000;
const TAG: string = 'SharePage';

// 开源代码内嵌 WebView 页（MineView 关于板块点击进入）
@Entry
@Component
struct SharePage {
  private controller: webview.WebviewController = new webview.WebviewController();
  @State loadingProgress: number = 0;

  build() {
    Column() {
      // 顶部栏：返回 + 标题 + 分享
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

        Text('开源代码')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary_color'))
          .layoutWeight(1)
          .textAlign(TextAlign.Center);

        Image($r('app.media.share'))
          .width(32)
          .height(32)
          .objectFit(ImageFit.Contain)
          .fillColor($r('app.color.text_primary_color'))
          .padding(4)
          .onClick(() => {
            this.handleShare();
          });
      }
      .width('100%')
      .padding({ left: 8, right: 8, top: 12, bottom: 12 })
      .backgroundColor($r('app.color.index_page_top_background'))
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP]);

      // 加载进度条
      Progress({ value: this.loadingProgress, total: 100, type: ProgressType.Linear })
        .width('100%')
        .height(2)
        .color($r('app.color.text_accent_color'))
        .backgroundColor($r('app.color.divider_color'))
        .opacity(this.loadingProgress < 100 ? 1 : 0);

      // WebView 内容区
      Web({ src: SOURCE_CODE_URL, controller: this.controller })
        .width('100%')
        .layoutWeight(1)
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .databaseAccess(false)
        .cacheMode(CacheMode.None)
        .zoomAccess(true)
        .darkMode(WebDarkMode.Auto)
        .onProgressChange((data) => {
          this.loadingProgress = data.newProgress;
        });
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
      if (this.controller.accessBackward()) {
        this.controller.backward();
      } else {
        this.getUIContext().getRouter().back();
      }
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, TAG, '返回失败：%{public}s', msg);
    }
  }

  private handleShare(): void {
    try {
      const shareData: systemShare.SharedData = new systemShare.SharedData({
        utd: utd.UniformDataType.HYPERLINK,
        content: SOURCE_CODE_URL,
        title: 'TimelyNotify 开源代码',
        description: 'https://github.com/wallleap/timelynotify'
      });
      const controller: systemShare.ShareController = new systemShare.ShareController(shareData);
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      controller.show(context, {
        previewMode: systemShare.SharePreviewMode.DEFAULT,
        selectionMode: systemShare.SelectionMode.SINGLE
      }).then(() => {
        hilog.info(DOMAIN, TAG, '分享面板展示成功');
      }).catch((err: BusinessError) => {
        hilog.warn(DOMAIN, TAG, '分享面板展示失败：code=%{public}d msg=%{public}s', err.code, err.message);
      });
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, TAG, '分享调用异常：%{public}s', msg);
    }
  }
}
