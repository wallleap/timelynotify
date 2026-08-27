import { hilog } from '@kit.PerformanceAnalysisKit';
import { webview } from '@kit.ArkWeb';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { SOURCE_CODE_URL, USE_DOCS_URL } from '../views/MineView';
import { resolveBlurStyle } from '../utils/ImmersiveUtil';

const DOMAIN: number = 0x0000;
const TAG: string = 'SharePage';

// 内嵌 WebView 页（开源代码 / 使用文档）
@Entry
@Component
struct SharePage {
  private controller: webview.WebviewController = new webview.WebviewController();
  @State loadingProgress: number = 0;
  @State pageTitle: string = '开源代码';
  @State targetUrl: string = SOURCE_CODE_URL;

  aboutToAppear() {
    try {
      const params = this.getUIContext().getRouter().getParams() as Record<string, string> | undefined;
      if (params && params['url']) {
        this.targetUrl = params['url'];
      }
      if (params && params['title']) {
        this.pageTitle = params['title'];
      }
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, TAG, '读取路由参数失败：%{public}s', msg);
    }
  }

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

        Text(this.pageTitle)
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
      .backgroundBlurStyle(resolveBlurStyle('bar'), { scale: 1.0 })
      .backgroundColor($r('app.color.index_page_top_background'))
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP]);

      // 加载进度条
      Progress({ value: this.loadingProgress, total: 100, type: ProgressType.Linear })
        .width('100%')
        .height(2)
        .color($r('app.color.text_accent_color'))
        .backgroundColor($r('app.color.divider_color'))
        .opacity(this.loadingProgress < 100 ? 1 : 0);

      // WebView 内容区（单独扩展到导航栏后面）
      Web({ src: this.targetUrl, controller: this.controller })
        .width('100%')
        .layoutWeight(1)
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .databaseAccess(false)
        .cacheMode(CacheMode.None)
        .zoomAccess(true)
        .darkMode(WebDarkMode.Auto)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
        .onProgressChange((data) => {
          this.loadingProgress = data.newProgress;
        });
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Start)
    // 保持 Column 布局：WebView 网页头部不能被顶栏遮挡，顶栏玻璃糊的是底色（网页内容不穿过）
    // 根容器铺不透明底色，body 模糊无内容可糊已移除
    .backgroundColor($r('app.color.index_page_body_background'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP]);
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
        content: this.targetUrl,
        title: this.pageTitle,
        description: this.targetUrl
      });
      const controller: systemShare.ShareController = new systemShare.ShareController(shareData);
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      controller.show(context, {} as systemShare.ShareControllerOptions).then(() => {
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
