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
  // 底部导航条高度（vp），EntryAbility 沉浸式布局初始化时写入 AppStorage（键值见 ImmersiveUtil）
  @StorageProp('navBarHeight') navBarHeight: number = 0;
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
    // 底部补导航条高度：沉浸式布局下 TabBar 覆盖导航条区域，图标文字需避让到手势条上方
    .padding({ bottom: this.navBarHeight })
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
      // TabBar 高度 = 视觉高度 56 + 导航条高度（沉浸式布局下 TabBar 背景覆盖导航条区域）
      .barHeight(56 + this.navBarHeight)
      .animationDuration(300)
      // 内容延伸到 TabBar 下方，TabBar 毛玻璃才能糊到滚动内容
      .barOverlap(true)
      // TabBar 毛玻璃材质（API 11+）+ 半透明底色，与顶栏玻璃色保持一致
      .barBackgroundBlurStyle(resolveBlurStyle('bar'))
      .barBackgroundColor($r('app.color.index_page_bottom_background'))
      .onChange((index: number) => {
        this.currentIndex = index
      })
    }
    .width('100%')
    .height('100%')
    // 沉浸式布局下窗口铺满全屏（含状态栏/导航条区域），根容器底色兜底延伸区域
    .backgroundColor($r('app.color.index_page_top_solid'))
  }
}
