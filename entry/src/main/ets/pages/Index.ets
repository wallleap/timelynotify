import { NotifyView } from '../views/NotifyView';
import { MineView } from '../views/MineView';
import { resolveBlurStyle, SUPPORTS_IMMERSIVE_MATERIAL } from '../utils/ImmersiveUtil';
import { hdsMaterial, HdsTabs, HdsTabsController } from '@kit.UIDesignKit';

// 底部 Tab 项定义
interface TabItem {
  title: string | Resource;
  icon: Resource;
  iconActive: Resource;
}

@Entry
@Component
struct Index {
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  @State currentIndex: number = 0;
  private hdsController: HdsTabsController = new HdsTabsController();
  // Tab 数据
  private tabs: TabItem[] = [
    {
      title: $r('app.string.index_tab_notify'),
      icon: $r('app.media.notify'),
      iconActive: $r('app.media.notify_active')
    },
    {
      title: $r('app.string.index_tab_mine'),
      icon: $r('app.media.mine'),
      iconActive: $r('app.media.mine_active')
    },
  ];

  @Builder
  tabBuilder(item: TabItem, index: number) {
    Column() {
      Image(this.currentIndex === index ? item.iconActive : item.icon)
        .width(24)
        .height(24)
        .fillColor(
          this.currentIndex === index ? $r('app.color.text_accent_color') : $r('app.color.text_quinary_color'));
      Text(item.title)
        .fontSize(12)
        .fontColor(
          this.currentIndex === index ? $r('app.color.text_accent_color') : $r('app.color.text_quinary_color'));
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  tabsContent() {
    TabContent() {
      NotifyView()
    }
    .tabBar(this.tabBuilder(this.tabs[0], 0));

    TabContent() {
      MineView()
    }
    .tabBar(this.tabBuilder(this.tabs[1], 1))
  }

  build() {
    if (SUPPORTS_IMMERSIVE_MATERIAL) {
      // ─── API 26+: HdsTabs 悬浮胶囊 + systemMaterialEffect 沉浸光感 ───
      Column() {
        HdsTabs({ controller: this.hdsController }) {
          this.tabsContent();
        }
        .barOverlap(true)
        .barPosition(BarPosition.End)
        .barFloatingStyle({
          barBottomMargin: this.navBarHeight,
          systemMaterialEffect: {
            materialType: hdsMaterial.MaterialType.ADAPTIVE,
            materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
          }
        })
        .onChange((index: number) => {
          this.currentIndex = index;
        })
      }
      .width('100%')
      .height('100%')
    } else {
      // ─── API < 26: 标准 Tabs + 自定义顶栏（barBackgroundBlurStyle 降级）───
      Column() {
        Tabs({ barPosition: BarPosition.End, index: this.currentIndex }) {
          this.tabsContent();
        }
        .barMode(BarMode.Fixed)
        .barWidth('100%')
        .barHeight(56 + this.navBarHeight)
        .animationDuration(300)
        .barOverlap(true)
        .barBackgroundBlurStyle(resolveBlurStyle('bar')!)
        .barBackgroundColor($r('app.color.index_page_bottom_glass_background'))
        .onChange((index: number) => {
          this.currentIndex = index
        })
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.index_page_top_solid'))
    }
  }
}
