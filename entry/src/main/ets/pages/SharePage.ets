import { hilog } from '@kit.PerformanceAnalysisKit';
import { webview } from '@kit.ArkWeb';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { SOURCE_CODE_URL } from '../views/MineView';
import { getSystemMaterial, resolveBlurStyle } from '../utils/ImmersiveUtil';
import { DOMAIN } from '../common/Constant';

const TAG: string = 'SharePage';

// 内嵌 WebView 页（开源代码 / 使用文档）
@Entry
@Component
struct SharePage {
  // 状态栏/导航条高度（vp），EntryAbility 沉浸式布局初始化时写入 AppStorage（键值见 ImmersiveUtil）
  @StorageProp('statusBarHeight') statusBarHeight: number = 36;
  @StorageProp('navBarHeight') navBarHeight: number = 24;
  // 沉浸光感材质就绪信号：uiMaterial 模块（API 26+）动态加载成功后置 true，触发重渲染切换到材质分支
  @StorageProp('immersiveMaterialReady') materialReady: boolean = false;
  @State loadingProgress: number = 0;
  @State pageTitle: string = '开源代码';
  @State targetUrl: string = SOURCE_CODE_URL;
  private controller: webview.WebviewController = new webview.WebviewController();

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

  @Builder
  titleBar() {
    if (this.materialReady) {
      Row() {
        this.topBarContent();
      }
      .width('100%')
      .padding({
        left: 8,
        right: 8,
        top: 12 + this.statusBarHeight,
        bottom: 12
      })
      .systemMaterial(getSystemMaterial('bar'))
      .backgroundColor($r('app.color.index_page_top_glass_background'));
    } else {
      Row() {
        this.topBarContent();
      }
      .width('100%')
      .padding({
        left: 8,
        right: 8,
        top: 12 + this.statusBarHeight,
        bottom: 12
      })
      .backgroundBlurStyle(resolveBlurStyle('bar')!)
      .backgroundColor($r('app.color.index_page_top_glass_background'));
    }
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      // 内容层（下层）：Progress + WebView 铺满 Stack，顶部延伸到状态栏
      Column() {
        Progress({ value: this.loadingProgress, total: 100, type: ProgressType.Linear })
          .width('100%')
          .height(2)
          .color($r('app.color.text_accent_color'))
          .backgroundColor($r('app.color.divider_color'))
          .opacity(this.loadingProgress < 100 ? 1 : 0);

        Web({ src: this.targetUrl, controller: this.controller })
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
          })
          .onPageEnd(() => {
            const topSafe = this.statusBarHeight + 56;
            this.controller.runJavaScript(
              `document.documentElement.style.setProperty('--safe-area-top', '${topSafe}px');` +
                `document.documentElement.style.setProperty('--safe-area-bottom', '${this.navBarHeight}px');` +
                `let s=document.createElement('style');` +
                `s.textContent='body{padding-top:var(--safe-area-top) !important;padding-bottom:var(--safe-area-bottom) !important;}';` +
                `document.head.appendChild(s);`
            ).catch((err: Error) => {
              const msg = err instanceof Error ? err.message : String(err);
              hilog.warn(DOMAIN, TAG, '注入安全区 CSS 失败：%{public}s', msg);
            });
          });
      }
      .width('100%')
      .height('100%')

      // 顶栏层（上层）：systemMaterial 沉浸光感，糊住下层 WebView 内容
      this.titleBar()
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.index_page_body_background'));
  }

  // 系统返回手势：WebView 优先后退
  onBackPress(): boolean {
    try {
      if (this.controller.accessBackward()) {
        this.controller.backward();
        return true;
      }
    } catch (error) {
      // TODO: Implement error handling.
    }
    return false;
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
