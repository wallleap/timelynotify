import { hilog } from '@kit.PerformanceAnalysisKit';
import { webview } from '@kit.ArkWeb';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { SOURCE_CODE_URL } from '../views/MineView';
import { resolveBlurStyle } from '../utils/ImmersiveUtil';
import { DOMAIN } from '../common/Constant';

const TAG: string = 'SharePage';

// 内嵌 WebView 页（开源代码 / 使用文档）
@Entry
@Component
struct SharePage {
  // 状态栏/导航条高度（vp），EntryAbility 沉浸式布局初始化时写入 AppStorage（键值见 ImmersiveUtil）
  @StorageProp('statusBarHeight') statusBarHeight: number = 36;
  @StorageProp('navBarHeight') navBarHeight: number = 24;
  @State loadingProgress: number = 0;
  @State pageTitle: string = '开源代码';
  @State targetUrl: string = SOURCE_CODE_URL;
  // 下拉刷新状态：单向绑定 + 手动控制（ArkTS 双向绑定 $$ 当前 SDK 不支持）
  @State refreshing: boolean = false;
  // 自定义刷新指示器不会自动隐藏，需按状态控制显隐（Done 不会自动回到 Inactive，需视为隐藏）
  @State refreshState: RefreshStatus = RefreshStatus.Inactive;
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

  // 自定义刷新指示器：仅在下拉/刷新过程中显示（Inactive 隐藏）；
  // 顶部 spacer 让转圈下移到毛玻璃顶栏（高 = statusBarHeight + 56）下方，避免被遮挡
  @Builder
  refreshHeaderBuilder() {
    Column() {
      Row().height(this.statusBarHeight + 56 + 16);

      if (this.refreshState !== RefreshStatus.Inactive) {
        LoadingProgress()
          .width(28)
          .height(28)
          .color($r('app.color.text_accent_color'));
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center);
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

        // 下拉刷新容器：Web 触顶后下拉手势才交给 Refresh，页面中间下拉仍是网页正常滚动
        Refresh({ refreshing: this.refreshing, builder: this.refreshHeaderBuilder() }) {
          Web({ src: this.targetUrl, controller: this.controller })
            .width('100%')
            .height('100%')
            .javaScriptAccess(true)
            .domStorageAccess(true)
            .databaseAccess(false)
            .cacheMode(CacheMode.None)
            .zoomAccess(true)
            .darkMode(WebDarkMode.Auto)
            // 嵌套滚动：Web 自身先滚动，到边界（触顶）后交给父容器 Refresh 触发下拉刷新
            .nestedScroll({
              scrollForward: NestedScrollMode.SELF_FIRST,
              scrollBackward: NestedScrollMode.SELF_FIRST
            })
            .onProgressChange((data) => {
              this.loadingProgress = data.newProgress;
            })
            .onPageEnd(() => {
              // 刷新/加载完成：收起下拉刷新指示器
              this.refreshing = false;
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
        .layoutWeight(1)
        .onStateChange((state: RefreshStatus) => {
          // 同步刷新状态给自定义指示器，控制其显隐
          // Done（刷新结束）不会自动回到 Inactive，需直接视为隐藏，避免加载完成后指示器常驻
          this.refreshState = state === RefreshStatus.Done ? RefreshStatus.Inactive : state;
        })
        .onRefreshing(() => {
          // 触顶下拉触发：刷新 WebView 当前页；失败时立即收起指示器
          this.refreshing = true;
          try {
            this.controller.refresh();
          } catch (err) {
            const msg = err instanceof Error ? err.message : String(err);
            hilog.warn(DOMAIN, TAG, 'WebView 刷新失败：%{public}s', msg);
            this.refreshing = false;
          }
        });
      }
      .width('100%')
      .height('100%')

      // 顶栏层（上层）：毛玻璃模糊，糊住下层 WebView 内容
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
