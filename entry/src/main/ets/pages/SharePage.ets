import { hilog } from '@kit.PerformanceAnalysisKit';
import { webview } from '@kit.ArkWeb';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { SOURCE_CODE_URL } from '../views/MineView';
import {
  KEY_IMMERSIVE_LIGHT_ENABLED,
  resolveBlurStyle,
  SUPPORTS_IMMERSIVE_MATERIAL
} from '../utils/ImmersiveUtil';
import { hdsMaterial, HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit';
import { DOMAIN } from '../common/Constant';

const TAG: string = 'SharePage';

// 内嵌 WebView 页（开源代码 / 使用文档）
@Entry
@Component
struct SharePage {
  // 状态栏/导航条高度（vp），EntryAbility 沉浸式布局初始化时写入 AppStorage（键值见 ImmersiveUtil）
  @StorageProp('statusBarHeight') statusBarHeight: number = 36;
  @StorageProp('navBarHeight') navBarHeight: number = 24;
  // 沉浸光感用户开关（API 26+ 生效；MineView Toggle 切换后经 AppStorage 同步，此处自动重渲染切换分支）
  @StorageProp(KEY_IMMERSIVE_LIGHT_ENABLED) immersiveLightEnabled: boolean = true;
  @State loadingProgress: number = 0;
  @State pageTitle: string = '开源代码';
  // 标题显隐：网页下滑超过阈值后隐藏顶栏标题，滚回顶部附近恢复（由 Web.onScroll 驱动）
  @State titleVisible: boolean = true;
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
      .textAlign(TextAlign.Center)
      // 与 HDS 分支联动：网页下滑后隐藏标题；用 opacity 保持 layoutWeight 占位，
      // visibility(None) 会使占位消失导致左右图标错位
      .opacity(this.titleVisible ? 1 : 0);

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

  // 降级顶栏：低版本 SDK 手工 Stack 叠层，blurStyle + 半透明底色实现毛玻璃
  @Builder
  fallbackTitleBar() {
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
    // blurStyle 只做模糊不调色 → 必须叠加半透明底色才看得到毛玻璃
    .backgroundBlurStyle(resolveBlurStyle('bar')!)
    .backgroundColor($r('app.color.index_page_top_glass_background'));
  }

  // 自定义刷新指示器：仅在下拉/刷新过程中显示（Inactive 隐藏）；
  // 顶部 spacer 让转圈下移到 titleBar 下方避免被遮挡：
  // 铺满方案下内容区从窗口顶开始（enableComponentSafeArea: false），Refresh 顶部贴近窗口顶，
  // HDS 分支 spacer = statusBarHeight + 56 - 4（titleBar 总高微调 -4）；降级分支 = statusBarHeight + 56 + 16
  @Builder
  refreshHeaderBuilder() {
    Column() {
      Row()
        .height(SUPPORTS_IMMERSIVE_MATERIAL && this.immersiveLightEnabled ? this.statusBarHeight + 56 - 4 :
          this.statusBarHeight + 56 + 16);

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

  // WebView 主体（Progress + Refresh { Web }），两条渲染路径共用内容体
  @Builder
  webBody() {
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
        // HDS bindToNestedScrollable 需要通过组件 id 绑定嵌套滚动源
          .id('shareWeb')
          .width('100%')
          .height('100%')
          .javaScriptAccess(true)
          .domStorageAccess(true)
          .databaseAccess(false)
          // ⚠️ ArkWeb CacheMode 命名陷阱：None 不是"不用缓存"，而是"优先用缓存(连过期都用)"；
          // 真正"强制走网络不读缓存"的是 Online，否则服务器更新后真机仍显示旧内容
          .cacheMode(CacheMode.Online)
          .zoomAccess(true)
          .darkMode(WebDarkMode.Auto)
          // ⚠️ 官方 HDS 动态模糊必配：Web 不裁剪溢出，内容才能向上穿出至 titleBar 背面被材质采样
          .clip(false)
          // 嵌套滚动：Web 自身先滚动，到边界（触顶）后交给父容器 Refresh 触发下拉刷新
          .nestedScroll({
            scrollForward: NestedScrollMode.SELF_FIRST,
            scrollBackward: NestedScrollMode.SELF_FIRST
          })
          .onProgressChange((data) => {
            this.loadingProgress = data.newProgress;
          })
          // 滚动联动标题显隐：网页下滑超过 64vp 隐藏顶栏标题，滚回顶部（< 64vp）恢复
          .onScroll((event) => {
            this.titleVisible = event.yOffset < 64;
          })
          .onPageEnd(() => {
            // 刷新/加载完成：收起下拉刷新指示器
            this.refreshing = false;
            // --safe-area-top 让网页 body 顶部留出 titleBar 区域（内容区避让 titleBar 后，
            // 网页正文已从顶栏下缘开始，注入 padding-top 仅为顶栏高度兜底）
            const topSafe: number = this.statusBarHeight + 56;
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
      // ⚠️ 官方 HDS 动态模糊必配：Refresh 外层也不裁剪溢出，否则穿出 titleBar 背面的 Web 内容会被 Refresh 边界裁掉
      .clip(false)
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
    .height('100%');
  }

  build() {
    if (SUPPORTS_IMMERSIVE_MATERIAL && this.immersiveLightEnabled) {
      // ─── API 26+: HdsNavigation 原生沉浸光感（titleBar 内置 systemMaterialEffect）───
      HdsNavigation() {
        this.webBody();
      }
      .titleBar({
        // 铺满方案（复刻降级分支已验证布局）：内容区不避让标题栏 → Web 铺满全窗，
        // 网页顶进状态栏后面，titleBar 毛玻璃悬浮其上透出+模糊下层内容；
        // 网页正文起点由 onPageEnd 注入的 body padding-top 兜底（与降级分支一致）
        enableComponentSafeArea: false,
        // 标题栏内容（系统槽位 mainTitle/backIcon/menu）避让状态栏
        avoidLayoutSafeArea: true,
        content: {
          // 系统 MINI 标题槽位：18vp 粗体居中，绑定 @State 动态标题（路由参数传入）；
          // 网页下滑超过阈值后置空隐藏标题，滚回顶部恢复
          title: { mainTitle: this.titleVisible ? this.pageTitle : '' },
          // 系统返回键槽位：backIcon 支持自定义 action（d.ts: HdsNavigationIconOptions.action），
          // 保留「先 Web 历史后退、再路由返回」逻辑
          backIcon: {
            icon: $r('app.media.arrow_left'),
            action: (): void => {
              this.handleBack();
            }
          },
          // 系统菜单槽位：右上分享按钮
          menu: {
            value: [{
              content: {
                icon: $r('app.media.share'),
                action: (): void => {
                  this.handleShare();
                }
              }
            }]
          }
        },
        style: {
          // 常驻半透明毛玻璃材质：Web 无 ArkTS Scroller 控制器，无法绑定滚动联动，
          // 仅保留静态沉浸光感（titleBar 实时采样下层内容模糊）
          systemMaterialEffect: {
            materialType: hdsMaterial.MaterialType.ADAPTIVE,
            // 官方推荐 ADAPTIVE：系统按设备算力自适应档位，避免低端机卡顿/发热
            //（EXQUISITE 需 getSystemMaterialTypes() 检测支持后才可硬编码）
            materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
          },
        }
      })
      // 返回键走 backIcon 自定义 action（「先 Web 后退、再路由返回」），系统返回键保持显示
      .hideBackButton(false)
      .titleMode(HdsNavigationTitleMode.MINI)
      // Web 本身无 ArkTS Scroller 控制器（NestedScrollInfo.parent 要求 Scroller），
      // 故此处不通过 bindToNestedScrollable 绑定 Web 嵌套滚动；titleBar 原生 systemMaterialEffect
      // 仍可在内容滚入顶栏背面时提供沉浸光感视觉效果
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.index_page_body_background'));
    } else {
      // ─── API < 26: Stack + 手工顶栏叠层（backgroundBlurStyle 降级）───
      Stack({ alignContent: Alignment.Top }) {
        this.webBody();
        // 顶栏层（上层）：blurStyle + 半透明底色糊住下层 WebView 内容
        this.fallbackTitleBar()
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.index_page_body_background'));
    }
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
