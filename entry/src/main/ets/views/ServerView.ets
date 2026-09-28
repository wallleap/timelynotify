import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  getDialogBackgroundOptions,
  KEY_IMMERSIVE_LIGHT_ENABLED,
  resolveBlurStyle,
  SUPPORTS_IMMERSIVE_MATERIAL
} from '../utils/ImmersiveUtil';
import { hdsMaterial, HdsNavigation, HdsNavigationTitleMode, IconStyleMode, ScrollEffectType } from '@kit.UIDesignKit';
import { ServerList } from '../components/server/ServerList';
import { AddServerDialog } from '../components/server/AddServerDialog';
import { DOMAIN } from '../common/Constant';
import { SampleCode } from '../components/server/SampleCode';
import { ExternalLinkService, USE_DOCS_URL } from '../services/ExternalLinkService';

const TAG: string = 'ServerView';
const PUSH_FIELDS_URL: string = `${USE_DOCS_URL}/fields/`;
const FAQ_URL: string = `${USE_DOCS_URL}/faq/`;

// 服务页 - 直接展示服务器列表，右上角 + 走 HdsNavigation 系统 menu 槽位（材质由 HDS 自动渲染），点击弹窗添加服务器
@Component
export struct ServerView {
  @State fallbackTitleBarBottom: number = -1;
  @State scrollTop: number = -1;
  // 状态栏/导航条高度（vp），EntryAbility 沉浸式布局初始化时写入 AppStorage
  @StorageProp('statusBarHeight') statusBarHeight: number = 36;
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  // 沉浸光感开关值（API 26+ 生效）
  @StorageProp(KEY_IMMERSIVE_LIGHT_ENABLED) immersiveLightEnabled: boolean = true;
  // 官方结构：Scroll 绑定自己的 Scroller 实例，供 HdsNavigation.bindToScrollable 用
  private scroller: Scroller = new Scroller();
  // 添加服务器弹窗：点击时构造，保证材质读取最新就绪态
  private addServerController: CustomDialogController | null = null;

  // 降级顶栏（API < 26）右侧 + 图标：纯系统图标，无材质链式调用
  @Builder
  fallbackAddIcon() {
    Row() {
      SymbolGlyph($r('sys.symbol.plus'))
        .fontSize(22)
        .fontColor([$r('app.color.color_text_primary')]);
    }
    .width(38)
    .height(38)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.openAddServerDialog();
    });
  }

  // 降级顶栏：低版本 SDK 手工 Stack 叠层，blurStyle + 半透明底色实现毛玻璃
  @Builder
  fallbackTitleBar() {
    Row() {
      Text('服务')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.color_text_primary'));
      Blank();
      this.fallbackAddIcon();
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({
      left: 16,
      right: 16,
      top: 16 + this.statusBarHeight,
      bottom: 16
    })
    .backgroundBlurStyle(resolveBlurStyle('bar')!)
    .backgroundColor($r('app.color.color_bg_glass'))
    .onAreaChange((_old: Area, area: Area) => {
      const bottom: number = (area.globalPosition.y as number) + (area.height as number);
      if (bottom >= 0 && bottom !== this.fallbackTitleBarBottom) {
        this.fallbackTitleBarBottom = bottom;
      }
    });
  }

  // 文档入口：复用应用内 SharePage，分别打开使用指南和推送参数
  @Builder
  doc() {
    Column() {
      Row({ space: 6 }) {
        Row({ space: 6 }) {
          Image($r('app.media.documentation_colorful'))
            .width(32)
            .height(32)
            .objectFit(ImageFit.Contain)
            .draggable(false);

          Text('文档')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.color_text_primary'));
        }

      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.SpaceBetween)
      .padding({ bottom: 16 })

      Divider()
        .color($r('app.color.color_border_subtle'))
        .strokeWidth(1)

      Row() {
        Text('使用指南')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.color_text_primary'))

        Row() {
          Image($r('app.media.arrow_right'))
            .width(18)
            .height(18)
            .fillColor($r('app.color.color_text_hint'))
            .draggable(false);
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.SpaceBetween)
      // 用行内边距扩展点击区域，替代 Column 的不可点击间距。
      .padding({ top: 16, bottom: 16 })
      .onClick(() => {
        this.openDocument(`${USE_DOCS_URL}/`, '使用指南');
      })

      Divider()
        .color($r('app.color.color_border_subtle'))
        .strokeWidth(1)

      Row() {
        Text('推送参数')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.color_text_primary'))

        Row() {
          Image($r('app.media.arrow_right'))
            .width(18)
            .height(18)
            .fillColor($r('app.color.color_text_hint'))
            .draggable(false);
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.SpaceBetween)
      .padding({ top: 16, bottom: 20 })
      .onClick(() => {
        this.openDocument(PUSH_FIELDS_URL, '推送参数');
      })
    }
    .padding({
      top: 16,
      left: 16,
      right: 16,
      bottom: 0
    })
    .borderRadius(10)
    .backgroundColor($r('app.color.color_bg_surface'))
  }

  // 常见问答入口
  @Builder
  question() {
    Column() {
      Row({ space: 6 }) {
        Row({ space: 6 }) {
          Image($r('app.media.question_colorful'))
            .width(32)
            .height(32)
            .objectFit(ImageFit.Contain)
            .draggable(false);

          Text('常见问答')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.color_text_primary'));
        }

        Row() {
          Image($r('app.media.arrow_right'))
            .width(18)
            .height(18)
            .fillColor($r('app.color.color_text_hint'))
            .draggable(false);
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.SpaceBetween)
    }
    .padding(16)
    .borderRadius(10)
    .backgroundColor($r('app.color.color_bg_surface'))
    .onClick(() => {
      this.openDocument(FAQ_URL, '常见问答');
    })
  }

  // 服务页滚动内容主体：仅服务器列表
  @Builder
  scrollBody() {
    Scroll(this.scroller) {
      Column({ space: 16 }) {
        // 顶栏避让占位
        Row()
          .width('100%')
          .height(SUPPORTS_IMMERSIVE_MATERIAL && this.immersiveLightEnabled ? 0 :
            (this.fallbackTitleBarBottom >= 0 && this.scrollTop >= 0
              ? Math.max(0, this.fallbackTitleBarBottom - this.scrollTop) : 0));

        // 服务器列表（切换/删除/操作菜单，不含添加表单与 viewAll 开关）
        ServerList();

        // 示例
        SampleCode();

        // 文档 + 问答
        this.doc();
        this.question();

        // 底部占位
        Row().width('100%').height(this.navBarHeight + 72);
      }
      .width('100%')
      .padding({ left: 16, right: 16 });
    }
    .align(Alignment.TopStart)
    .height('100%')
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .width('100%')
    .onAreaChange((_old: Area, area: Area) => {
      const top: number = area.globalPosition.y as number;
      if (top !== this.scrollTop) {
        this.scrollTop = top;
      }
    })
    .clip(false);
  }

  build() {
    if (SUPPORTS_IMMERSIVE_MATERIAL && this.immersiveLightEnabled) {
      // ─── API 26+: HdsNavigation 原生沉浸光感 ───
      // 标题与 + 菜单均走系统槽位：图标材质由 HDS 按 systemMaterialEffect(ADAPTIVE) 自动渲染，
      // 不要在 @Builder 里手写 Button.systemMaterial() 链式调用（ArkTSCheck 无法对声明式链做版本守卫，必报警告）。
      HdsNavigation() {
        this.scrollBody();
      }
      .titleBar({
        enableComponentSafeArea: true,
        // MINI 全屏页（Tab 内容）必须显式避让状态栏；MODAL 半模态自带窗口安全区可不开。
        avoidLayoutSafeArea: true,
        content: {
          title: { mainTitle: '服务' },
          menu: {
            value: [
              {
                content: {
                  icon: $r('sys.symbol.plus'),
                  type: IconStyleMode.SMALL,
                  action: (): void => {
                    this.openAddServerDialog();
                  }
                }
              }
            ]
          }
        },
        style: {
          scrollEffectOpts: {
            enableScrollEffect: true,
            scrollEffectType: ScrollEffectType.GRADIENT_BLUR
          },
          systemMaterialEffect: {
            materialType: hdsMaterial.MaterialType.ADAPTIVE,
            materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
          },
        }
      })
      .hideBackButton(true)
      .titleMode(HdsNavigationTitleMode.MINI)
      .bindToScrollable([this.scroller])
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.color_bg_page'));
    } else {
      // ─── API < 26: Stack + 手工顶栏叠层 ───
      Column() {
        Stack({ alignContent: Alignment.Top }) {
          this.scrollBody();
          this.fallbackTitleBar();
        }.width('100%').layoutWeight(1);
      }
      .width('100%').height('100%')
      .backgroundColor($r('app.color.color_bg_page'));
    }
  }

  // 打开添加服务器弹窗
  private openAddServerDialog(): void {
    try {
      const dialogBg = getDialogBackgroundOptions();
      this.addServerController = new CustomDialogController({
        builder: AddServerDialog({
          onAdded: () => {
            // ServerList 监听 ServerManager 变更会自动刷新，无需手动处理
          },
        }),
        alignment: DialogAlignment.Center,
        autoCancel: true,
        offset: { dx: 0, dy: 0 },
        cornerRadius: 14,
        systemMaterial: dialogBg.systemMaterial,
        backgroundColor: dialogBg.backgroundColor,
        backgroundBlurStyle: dialogBg.backgroundBlurStyle,
      });
      this.addServerController.open();
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, TAG, 'add server dialog open 失败：%{public}s', msg);
    }
  }

  // 使用现有的内嵌 WebView 打开文档页，导航失败由 ExternalLinkService 提示
  private async openDocument(url: string, title: string): Promise<void> {
    await ExternalLinkService.openSharePage(this.getUIContext(), url, title);
  }
}
