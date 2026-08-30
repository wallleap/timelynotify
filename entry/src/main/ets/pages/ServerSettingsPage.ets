import { hilog } from '@kit.PerformanceAnalysisKit';
import { ServerSettingsContent } from '../components/ServerSettingsContent';
import { resolveBlurStyle, SUPPORTS_IMMERSIVE_MATERIAL } from '../utils/ImmersiveUtil';
import { hdsMaterial, HdsNavigation, HdsNavigationTitleMode, ScrollEffectType } from '@kit.UIDesignKit';
import { DOMAIN } from '../common/Constant';

const TAG: string = 'ServerSettingsPage';

// 服务器设置页（MineView 点击服务器卡片进入）
@Entry
@Component
struct ServerSettingsPage {
  // 状态栏/导航条高度（vp），EntryAbility 沉浸式布局初始化时写入 AppStorage（键值见 ImmersiveUtil）
  @StorageProp('statusBarHeight') statusBarHeight: number = 36;
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  // 官方结构：Scroll 绑定自己的 Scroller 实例，供 HdsNavigation.bindToScrollable 用
  private scroller: Scroller = new Scroller();

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
    if (SUPPORTS_IMMERSIVE_MATERIAL) {
      // ─── API 26+: HdsNavigation 沉浸光感 ───
      HdsNavigation() {
        Scroll(this.scroller) {
          Column() {
            Row()
              .width('100%')
              .height(8);
            // 首占位：HDS 保留 4 作为列表顶部余量（enableComponentSafeArea 已让内容起始于 titleBar 下方）
            // 降级：Stack 叠层内容从窗口顶开始，需手工 statusBarHeight + MINI(56) + 16 余量 占位
            ServerSettingsContent();
          }
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 16 + this.navBarHeight });
        }
        .width('100%')
        .height('100%')
        .edgeEffect(EdgeEffect.Spring)
        .align(Alignment.Top)
        // ⚠️ 官方 HDS 动态模糊必配：Scroll 不裁剪溢出，列表才能向上穿出至 titleBar 背面被材质采样
        .clip(false);
      }
      .titleBar({
        enableComponentSafeArea: true,
        // 与其他页面统一：显式声明标题栏内容避让安全区（mainTitle 槽位虽自带避让，
        // 显式开启可保证配置一致，将来切 stackBuilder 时不踩坑）
        avoidLayoutSafeArea: true,
        content: { title: { mainTitle: '服务器设置' } },
        style: {
          // 服务器列表滚入顶栏下方时触发 GradientBlur 渐变模糊：采样下层内容做动态光感模糊
          scrollEffectOpts: {
            enableScrollEffect: true,
            scrollEffectType: ScrollEffectType.GRADIENT_BLUR
          },
          systemMaterialEffect: {
            materialType: hdsMaterial.MaterialType.ADAPTIVE,
            // 官方推荐 ADAPTIVE：系统按设备算力自适应档位，避免低端机卡顿/发热
            //（EXQUISITE 需 getSystemMaterialTypes() 检测支持后才可硬编码）
            materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
          },
        }
      })
      .hideBackButton(false)
      .titleMode(HdsNavigationTitleMode.MINI)
      // 官方：绑定 Scroll 滚动 → scrollEffectOpts 才会根据滚动偏移激活 GradientBlur 渐变模糊
      .bindToScrollable([this.scroller])
      .width('100%')
      .height('100%')
    } else {
      // ─── API < 26: Stack + 自定义顶栏（barBackgroundBlurStyle 降级）───
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
