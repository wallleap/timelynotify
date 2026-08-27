import { NotifyView } from '../views/NotifyView';
import { MineView } from '../views/MineView';
import { resolveBlurStyle } from '../utils/ImmersiveUtil';

// 底部 Tab 项定义
interface TabItem {
  title: string | Resource;
  icon: Resource;
  iconActive: Resource;
}

@Entry
@Component
struct Index {
  @State currentIndex: number = 0;
  private tabs: TabItem[] = [
    {
      title: $r('app.string.index_tab_notify'),
      icon: $r('app.media.notify'),
      iconActive: $r('app.media.notify_active'),
    },
    {
      title: $r('app.string.index_tab_mine'),
      icon: $r('app.media.mine'),
      iconActive: $r('app.media.mine_active'),
    },
  ];

  @Builder
  tabBuilder(item: TabItem, index: number) {
    Column({ space: 4 }) {
      Image(this.currentIndex === index ? item.iconActive : item.icon)
        .width(24)
        .height(24)
        .fillColor(this.currentIndex === index ? $r('app.color.text_accent_color') : $r('app.color.text_quinary_color'));
      Text(item.title)
        .fontSize(12)
        .fontColor(this.currentIndex === index ? $r('app.color.text_accent_color') : $r('app.color.text_quinary_color'));
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }

  build() {
    Column() {
      Tabs({ barPosition: BarPosition.End, index: this.currentIndex }) {
        TabContent() {
          NotifyView()
        }
        .tabBar(this.tabBuilder(this.tabs[0], 0));

        TabContent() {
          MineView()
        }
        .tabBar(this.tabBuilder(this.tabs[1], 1))
      }
      .barMode(BarMode.Fixed)
      .barWidth('100%')
      .barHeight(56)
      .animationDuration(300)
      // 内容延伸到 TabBar 下方，TabBar 毛玻璃才能糊到滚动内容
      .barOverlap(true)
      // TabBar 毛玻璃材质（API 11+）+ 半透明底色，与顶栏玻璃色保持一致
      .barBackgroundBlurStyle(resolveBlurStyle('bar'))
      .barBackgroundColor($r('app.color.index_page_bottom_background'))
      .onChange((index: number) => {
        this.currentIndex = index
      })
      // 底部 Tab 栏背景延伸到导航条区域
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    }
    .width('100%')
    .height('100%')
    // 顶/底安全区外（状态栏+导航条）用实色兜底：TabContent 裁剪顶栏玻璃延伸、
    // barBackgroundColor 与 barBackgroundBlurStyle 组合时 bar 延伸行为不可控，这里保证导航条区域始终有背景（沉浸）
    .backgroundColor($r('app.color.index_page_top_solid'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
