import { NotifyView } from '../views/NotifyView';
import { MineView } from '../views/MineView';
import { ServerView } from '../views/ServerView';
import {
  KEY_IMMERSIVE_LIGHT_ENABLED,
  resolveBlurStyle,
  shouldUseSystemMaterialPath
} from '../utils/ImmersiveUtil';
import { hdsMaterial, HdsTabs, HdsTabsController } from '@kit.UIDesignKit';
import {
  KEY_HOME_TAB_INDEX,
  KEY_INDEX_PAGE_VISIBLE,
  KEY_NOTIFY_EDITING,
  KEY_NOTIFY_SEARCH_BACK_ACTIVE,
  KEY_NOTIFY_SEARCH_BACK_SIGNAL,
  KEY_NOTIFY_SYNC_PROGRESS
} from '../common/Constant';
import { NotifySyncService } from '../services/NotifySyncService';
import { AntiPeepService } from '../services/AntiPeepService';

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
  @StorageLink(KEY_HOME_TAB_INDEX) @Watch('onTabRequested') currentIndex: number = 0;
  // 底栏视觉选中态提前跟随 HdsTabs 动画；业务状态仍在切换完成后同步。
  @State barSelectedIndex: number = 0;
  // 通知页多选编辑态（NotifyView 经 @StorageLink 写入）：onBackPress 据此拦截系统返回
  @StorageLink(KEY_NOTIFY_EDITING) notifyIsEditing: boolean = false;
  // 包含搜索入场和退场，防止动画期间再次返回直接退出应用。
  @StorageProp(KEY_NOTIFY_SEARCH_BACK_ACTIVE) notifySearchBackActive: boolean = false;
  @StorageProp(KEY_NOTIFY_SYNC_PROGRESS) syncProgress: string = '';
  private hdsController: HdsTabsController = new HdsTabsController();
  private hdsSelectedIndex: number = 0;
  // 独立路由覆盖主页时不启用防窥；Sheet/弹窗不离开主页，继续跟随当前 Tab。
  private pageVisible: boolean = false;
  // Tab 数据
  private tabs: TabItem[] = [
    {
      title: $r('app.string.index_tab_notify'),
      icon: $r('app.media.notify'),
      iconActive: $r('app.media.notify_active')
    },
    {
      title: $r('app.string.index_tab_server'),
      icon: $r('app.media.server'),
      iconActive: $r('app.media.server_active')
    },
    {
      title: $r('app.string.index_tab_mine'),
      icon: $r('app.media.mine'),
      iconActive: $r('app.media.mine_active')
    },
  ];

  @Builder
  tabBuilder(item: TabItem, index: number) {
    Column({ space: 4 }) {
      Stack({ alignContent: Alignment.TopEnd }) {
        Image(this.barSelectedIndex === index ? item.iconActive : item.icon)
          .width(24)
          .height(24)
          .fillColor(
            this.barSelectedIndex === index ? $r('app.color.color_brand') : $r('app.color.color_text_hint'))
          .draggable(false);
        if (index === 0 && this.syncProgress.length > 0) {
          LoadingProgress()
            .width(9)
            .height(9)
            .color($r('app.color.color_brand'));
        }
      }
      .width(24)
      .height(24);
      Text(item.title)
        .fontSize(12)
        .fontColor(
          this.barSelectedIndex === index ? $r('app.color.color_brand') : $r('app.color.color_text_hint'));
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
      ServerView()
    }
    .tabBar(this.tabBuilder(this.tabs[1], 1));

    TabContent() {
      MineView()
    }
    .tabBar(this.tabBuilder(this.tabs[2], 2))
  }

  aboutToAppear(): void {
    AntiPeepService.start();
    this.barSelectedIndex = this.currentIndex;
    NotifySyncService.getInstance().setTabIndex(this.currentIndex);
  }

  /** 根页面销毁时释放应用生命周期，独立路由显隐通过页面范围暂停防窥。 */
  aboutToDisappear(): void {
    this.pageVisible = false;
    AppStorage.setOrCreate(KEY_NOTIFY_SEARCH_BACK_ACTIVE, false);
    AntiPeepService.stop();
  }

  // 页面显隐：router 跳转其它页面（如服务器设置页）/应用退后台时触发 onPageHide，
  // 返回/回前台时触发 onPageShow。Tab 内子组件感知不到页面级显隐（不会触发 aboutToDisappear），
  // 经 AppStorage 同步给 NotifyView 用于刷新可见数据；同步本身由 Ability 生命周期管理。
  onPageShow(): void {
    this.pageVisible = true;
    this.updateAntiPeepScope(this.currentIndex);
    AppStorage.setOrCreate(KEY_INDEX_PAGE_VISIBLE, true);
  }

  onPageHide(): void {
    this.pageVisible = false;
    this.updateAntiPeepScope(this.currentIndex);
    AppStorage.setOrCreate(KEY_INDEX_PAGE_VISIBLE, false);
  }

  /** AppStorage 外部切换 Tab 时同步 HdsTabs 的控制器，降级 Tabs 则由 index 属性响应。 */
  private onTabRequested(): void {
    this.barSelectedIndex = this.currentIndex;
    this.updateAntiPeepScope(this.currentIndex);
    NotifySyncService.getInstance().setTabIndex(this.currentIndex);
    if (shouldUseSystemMaterialPath(this.immersiveLightEnabled) && this.hdsSelectedIndex !== this.currentIndex) {
      this.hdsSelectedIndex = this.currentIndex;
      this.hdsController.changeIndex(this.currentIndex);
    }
  }

  /** 仅通知和服务 Tab 启用防窥；我的、设置及 SharePage 均排除。 */
  private updateAntiPeepScope(index: number): void {
    AntiPeepService.setPageActive(this.pageVisible && (index === 0 || index === 1));
  }

  // 系统返回拦截：通知页先退出搜索或多选，搜索动画期间继续消费返回；
  // 返回 true 表示事件已消费，false 走默认返回行为（退出应用）
  onBackPress(): boolean {
    if (this.currentIndex === 0 && this.notifySearchBackActive) {
      const signal: number = AppStorage.get<number>(KEY_NOTIFY_SEARCH_BACK_SIGNAL) ?? 0;
      AppStorage.setOrCreate(KEY_NOTIFY_SEARCH_BACK_SIGNAL, signal + 1);
      return true;
    }
    if (this.currentIndex === 0 && this.notifyIsEditing) {
      // 置 false 后经 @StorageLink 同步回 NotifyView，等价于 exitEditMode
      this.notifyIsEditing = false;
      return true;
    }
    return false;
  }

  build() {
    if (shouldUseSystemMaterialPath(this.immersiveLightEnabled)) {
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
        .onSelected((index: number) => {
          // 手势确定目标后即更新底栏；不提前触发通知同步等业务状态切换。
          this.barSelectedIndex = index;
          // 视觉切向“我的”时就暂停，避免等待 Tab 动画期间仍弹出蒙层。
          this.updateAntiPeepScope(index);
        })
        .onChange((index: number) => {
          this.hdsSelectedIndex = index;
          this.barSelectedIndex = index;
          this.updateAntiPeepScope(index);
          this.currentIndex = index;
          NotifySyncService.getInstance().setTabIndex(index);
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
        .barBackgroundColor($r('app.color.color_bg_glass'))
        .onChange((index: number) => {
          this.barSelectedIndex = index;
          this.updateAntiPeepScope(index);
          this.currentIndex = index;
          NotifySyncService.getInstance().setTabIndex(index);
        })
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.color_bg_navigation'))
    }
  }
}
