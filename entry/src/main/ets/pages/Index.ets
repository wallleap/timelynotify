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
      .onChange((index: number) => {
        this.currentIndex = index
      })
      .backgroundBlurStyle(resolveBlurStyle('bar'), { scale: 1.0 })
      .backgroundColor($r('app.color.index_page_bottom_background'))
      // 底部 Tab 栏背景延伸到导航条区域
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    }
    .width('100%')
    .height('100%')
    .backgroundBlurStyle(resolveBlurStyle('bar'), { scale: 1.0 })
    .backgroundColor($r('app.color.index_page_top_background'))
    // 顶部背景延伸到状态栏区域（沉浸式），内容布局仍在安全区内自动避让
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
  }
}
