import { NotifyView } from '../views/NotifyView';
import { MineView } from '../views/MineView';
import {
  KEY_IMMERSIVE_LIGHT_ENABLED,
  resolveBlurStyle,
  SUPPORTS_IMMERSIVE_MATERIAL
} from '../utils/ImmersiveUtil';
import { hdsMaterial, HdsTabs, HdsTabsController } from '@kit.UIDesignKit';
import { KEY_HOME_TAB_INDEX, KEY_INDEX_PAGE_VISIBLE, KEY_NOTIFY_EDITING } from '../common/Constant';

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
  // 沉浸光感用户开关（API 26+ 生效；MineView Toggle 切换后经 AppStorage 同步，此处自动重渲染切换分支）
  @StorageProp(KEY_IMMERSIVE_LIGHT_ENABLED) immersiveLightEnabled: boolean = true;
  // 当前选中 Tab：经 @StorageLink 双向同步到 AppStorage，NotifyView 通过 @Watch 监听以在切走时退出多选模式
  @StorageLink(KEY_HOME_TAB_INDEX) currentIndex: number = 0;
  // 通知页多选编辑态（NotifyView 经 @StorageLink 写入）：onBackPress 据此拦截系统返回
  @StorageLink(KEY_NOTIFY_EDITING) notifyIsEditing: boolean = false;
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

  // 页面显隐：router 跳转其它页面（如服务器设置页）/应用退后台时触发 onPageHide，
  // 返回/回前台时触发 onPageShow。Tab 内子组件感知不到页面级显隐（不会触发 aboutToDisappear），
  // 经 AppStorage 同步给 NotifyView 用于停止/恢复前台轮询
  onPageShow(): void {
    AppStorage.setOrCreate(KEY_INDEX_PAGE_VISIBLE, true);
  }

  onPageHide(): void {
    AppStorage.setOrCreate(KEY_INDEX_PAGE_VISIBLE, false);
  }

  // 系统返回拦截：通知页多选编辑态时，返回键/侧滑先退出多选而不是离开页面；
  // 返回 true 表示事件已消费，false 走默认返回行为（退出应用）
  onBackPress(): boolean {
    if (this.currentIndex === 0 && this.notifyIsEditing) {
      // 置 false 后经 @StorageLink 同步回 NotifyView，等价于 exitEditMode
      this.notifyIsEditing = false;
      return true;
    }
    return false;
  }

  build() {
    if (SUPPORTS_IMMERSIVE_MATERIAL && this.immersiveLightEnabled) {
      // ─── API 26+: HdsTabs 悬浮胶囊 + systemMaterialEffect 沉浸光感 ───
      Column() {
        HdsTabs({ controller: this.hdsController }) {
          this.tabsContent();
        }
        .barOverlap(true)
        .barPosition(BarPosition.End)
        .barFloatingStyle({
          // 官方最佳实践：无手势条设备（navBarHeight=0）兜底 padding_level8，避免悬浮胶囊贴底
          barBottomMargin: this.navBarHeight > 0 ? this.navBarHeight : $r('sys.float.padding_level8'),
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
