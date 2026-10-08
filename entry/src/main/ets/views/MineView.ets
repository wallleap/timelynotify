import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { notificationManager } from '@kit.NotificationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { PreferencesUtil } from '../utils/PreferencesUtil';
import { ThemeService } from '../services/ThemeService';
import { DOMAIN, KEY_HOME_TAB_INDEX, KEY_INDEX_PAGE_VISIBLE } from '../common/Constant';
import {
  KEY_IMMERSIVE_LIGHT_ENABLED,
  resolveBlurStyle,
  shouldUseSystemMaterialPath,
  supportsImmersiveMaterial
} from '../utils/ImmersiveUtil';
import { hdsMaterial, HdsNavigation, HdsNavigationTitleMode, ScrollEffectType } from '@kit.UIDesignKit';
import { NotifySettingsSection } from '../components/minesections/NotifySettingsSection';
import { AppInfoSection } from '../components/minesections/AppInfoSection';
import { AboutSection } from '../components/minesections/AboutSection';
import { SettingArrow } from '../components/settings/SettingArrow';
import showToast from '../components/showToast';

// 系统通知权限读取状态；本地订阅开关不参与判断。
enum NotificationPermissionStatus {
  LOADING,
  ENABLED,
  DISABLED,
  ERROR
}

// 我的页 - 展示个人设置入口
@Component
export struct MineView {
  @State fallbackTitleBarBottom: number = -1;
  @State scrollTop: number = -1;
  // 顶部卡片展示的系统通知权限状态。
  @State notificationPermissionStatus: NotificationPermissionStatus = NotificationPermissionStatus.LOADING;
  // 页面或 Tab 重新可见时刷新权限，避免从系统设置返回后展示旧状态。
  @StorageProp(KEY_HOME_TAB_INDEX) @Watch('onHomeTabIndexChanged') homeTabIndex: number = 0;
  @StorageProp(KEY_INDEX_PAGE_VISIBLE) @Watch('onIndexPageVisibleChanged') indexPageVisible: boolean = true;
  // 状态栏/导航条高度（vp），EntryAbility 沉浸式布局初始化时写入 AppStorage（键值见 ImmersiveUtil）
  @StorageProp('statusBarHeight') statusBarHeight: number = 36;
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  // 沉浸光感开关值（API 26+ 生效；EntryAbility 启动时从 Preferences 写入 AppStorage）：
  // 入口行状态文本与各页面渲染分支均读此权威值；切换走 Dialog → 重启确认 → 重启应用生效
  @StorageProp(KEY_IMMERSIVE_LIGHT_ENABLED) immersiveLightEnabled: boolean = true;
  // 与“个性化设置”的 Select 共用页面状态；持久化仍由 ThemeService 负责。
  @StorageLink('color_mode') colorModeKey: string = 'system';
  // 主题三选项的 Symbol 图标（顺序与 COLOR_MODE_KEYS 一致）
  private readonly COLOR_MODE_ICONS: Resource[] = [
    $r('sys.symbol.moon_fill'),
    $r('sys.symbol.sun_max_fill'),
    $r('sys.symbol.circle_lefthalf_inset_filled'),
  ];
  // 主题三选项的持久化键值（顺序与 COLOR_MODE_ICONS 一致）
  private readonly COLOR_MODE_KEYS: string[] = ['dark', 'light', 'system'];
  // 官方结构：Scroll 绑定自己的 Scroller 实例，供 HdsNavigation.bindToScrollable 用
  private scroller: Scroller = new Scroller();
  // 多次刷新并发时只采纳最后一次结果，避免旧查询覆盖从设置页返回后的新状态。
  private permissionQueryId: number = 0;
  // 防止重复点击权限卡片同时拉起多个系统设置窗口。
  private notificationSettingsOpening: boolean = false;

  aboutToAppear() {
    this.refreshColorMode();
    this.refreshNotificationPermission();
  }

  // 系统通知权限卡片：点击整张卡片进入系统设置。
  @Builder
  notificationPermissionCard() {
    Row({ space: 14 }) {
      // 只给铃铛提供状态色底座，整张卡片仍保持与设置项一致的中性玻璃背景。
      Row() {
        Image(this.notificationPermissionStatus === NotificationPermissionStatus.ENABLED
          ? $r('app.media.bell_check') : $r('app.media.bell_off'))
          .width(24)
          .height(24)
          .fillColor(this.notificationPermissionStatus === NotificationPermissionStatus.ENABLED
            ? $r('app.color.color_success') : this.notificationPermissionStatus === NotificationPermissionStatus.DISABLED
              ? $r('app.color.color_error') : $r('app.color.color_warning'));
      }
      .width(44)
      .height(44)
      .justifyContent(FlexAlign.Center)
      .borderRadius(22)
      .backgroundColor(this.notificationPermissionStatus === NotificationPermissionStatus.ENABLED
        ? $r('app.color.color_success_bg') : this.notificationPermissionStatus === NotificationPermissionStatus.DISABLED
          ? $r('app.color.color_notification_permission_error_bg') : Color.Transparent);
      Column({ space: 4 }) {
        Text(this.notificationPermissionStatus === NotificationPermissionStatus.ENABLED
          ? '系统通知权限已开启' : this.notificationPermissionStatus === NotificationPermissionStatus.DISABLED
            ? '系统通知权限未开启' : this.notificationPermissionStatus === NotificationPermissionStatus.ERROR
              ? '通知权限状态获取失败' : '正在获取通知权限状态')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.notificationPermissionStatus === NotificationPermissionStatus.ENABLED
            ? $r('app.color.color_success') : this.notificationPermissionStatus === NotificationPermissionStatus.DISABLED
              ? $r('app.color.color_error') : $r('app.color.color_warning'));
        Text(this.notificationPermissionStatus === NotificationPermissionStatus.ENABLED
          ? '现在可以正常接收推送通知，点击可调整提醒方式'
          : this.notificationPermissionStatus === NotificationPermissionStatus.DISABLED
            ? '现在收到通知不会提醒，点击去开启“允许通知”'
            : this.notificationPermissionStatus === NotificationPermissionStatus.ERROR
              ? '点击卡片查看通知设置'
              : '请稍候…')
          .fontSize(13)
          .fontColor($r('app.color.color_text_secondary'));
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1);
      SettingArrow();
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding(16)
    .backgroundBlurStyle(resolveBlurStyle('bar')!)
    .backgroundColor($r('app.color.color_bg_surface_glass'))
    .borderRadius(12)
    .onClick(() => this.openNotificationSettings());
  }

  // 降级顶栏：低版本 SDK 手工 Stack 叠层，blurStyle + 半透明底色实现毛玻璃
  @Builder
  fallbackTitleBar() {
    Row() {
      // 标题居左
      Text('我的').fontSize(24).fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.color_text_primary'));
      Blank();
      // 右侧主题切换器（跟随系统/浅色/深色）
      this.colorModeSelector();
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({
      left: 16,
      right: 16,
      top: 16 + this.statusBarHeight,
      bottom: 16
    })
    // blurStyle 只做模糊不调色 → 必须叠加半透明底色才看得到毛玻璃
    .backgroundBlurStyle(resolveBlurStyle('bar')!)
    .backgroundColor($r('app.color.color_bg_glass'))
    .onAreaChange((_old: Area, area: Area) => {
      const bottom: number = (area.globalPosition.y as number) + (area.height as number);
      if (bottom >= 0 && bottom !== this.fallbackTitleBarBottom) {
        this.fallbackTitleBarBottom = bottom;
      }
    });
  }

  // 顶栏右侧主题切换器：三段纯图标（跟随系统/浅色/深色），选中项圆形高亮底
  @Builder
  colorModeSelector() {
    Row({ space: 4 }) {
      ForEach(this.COLOR_MODE_ICONS, (icon: Resource, idx: number) => {
        Row() {
          SymbolGlyph(icon)
            .fontSize(18)
            .fontColor([this.COLOR_MODE_KEYS[idx] === this.colorModeKey ? $r('app.color.color_brand') :
              $r('app.color.color_text_tertiary')])
        }
        .width(32)
        .height(32)
        .borderRadius(16)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(this.COLOR_MODE_KEYS[idx] === this.colorModeKey ? $r('app.color.color_state_brand_selected') :
          Color.Transparent)
        .onClick(() => {
          const key: string = this.COLOR_MODE_KEYS[idx];
          this.colorModeKey = key;
          ThemeService.applyColorMode(key, this.getUIContext());
        })
      }, (_icon: Resource, idx: number) => `color_mode_${idx}`)
    }
    .alignItems(VerticalAlign.Center)
  }

  // HDS 顶栏自定义内容（塞入 HdsNavigation.titleBar.content.stackBuilder）。
  // 状态栏避让由 titleBar 级 avoidLayoutSafeArea: true 负责（系统将内容整体下移 statusBarHeight）；
  // 此处 padding 只留纯视觉余量，不得再叠加 statusBarHeight（titleBar 高度固定，会溢出裁剪 → 文字消失）。
  @Builder
  customTitleContent() {
    Row() {
      // 标题居左
      Text('我的')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.color_text_primary'));
      Blank();
      // 右侧主题切换器（跟随系统/浅色/深色）
      this.colorModeSelector();
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({
      left: 16,
      right: 16,
      top: 16,
      bottom: 16
    });
  }

  // MineView 滚动内容主体（卡片列表），两条渲染路径共用
  @Builder
  scrollBody() {
    Scroll(this.scroller) {
      Column({ space: 16 }) {
        // HDS 自动避让标题栏；自绘叠层按实测重叠距离占位，Column 的 space 提供视觉间距。
        Row()
          .width('100%')
          .height(shouldUseSystemMaterialPath(this.immersiveLightEnabled) ? 0 :
            (this.fallbackTitleBarBottom >= 0 && this.scrollTop >= 0
              ? Math.max(0, this.fallbackTitleBarBottom - this.scrollTop) : 0));

        // 顶部直接展示系统通知权限状态，不混入应用内订阅偏好。
        this.notificationPermissionCard();

        // 通知设置板块：应用内订阅开关独立于顶部系统权限卡片，导出通知单独成卡片
        NotifySettingsSection();

        // 信息板块（构建信息 + 推送 Token）
        AppInfoSection();

        // 关于板块（检测更新 / 开源代码 / 隐私协议 / 反馈问题）及底部版本、备案信息
        AboutSection();

        // 底部占位：随内容一起滚动，末尾卡片才能滑入 TabBar 毛玻璃下方（padding 是硬边界做不到）
        // TabBar 总高 = 56 + 导航条高度，占位 72 保持视觉余量不变
        Row().width('100%').height(this.navBarHeight + 72);
      }.width('100%') // 左右避让边距（顶/底避让由首尾占位实现）
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
    // ⚠️ 官方 HDS 动态模糊必配：Scroll 不裁剪溢出，卡片才能向上穿出至 titleBar 背面被材质采样
    .clip(false);
  }

  build() {
    if (shouldUseSystemMaterialPath(this.immersiveLightEnabled)) {
      // ─── API 26+: HdsNavigation 原生沉浸光感（titleBar 内置 systemMaterialEffect）───
      HdsNavigation() {
        this.scrollBody();
      }
      .titleBar({
        enableComponentSafeArea: true,
        // ⚠️ stackBuilder 全自定义区域系统不做状态栏避让（系统 mainTitle 槽位才自带避让），
        // 必须显式开启 avoidLayoutSafeArea，titleBar 内容整体下移 statusBarHeight，总高自动变为 statusBarHeight+56；
        // stackBuilder 内部不要再手工加 statusBarHeight（titleBar 高度固定会溢出裁剪）
        avoidLayoutSafeArea: true,
        content: {
          // 自定义整段标题区：居左 24vp「我的」大字 + 右侧主题切换器
          stackBuilder: (): void => {
            this.customTitleContent();
          },
        },
        style: {
          // 滚动到顶栏下方时触发 GradientBlur 渐变模糊：采样下层内容做动态光感模糊
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
      .hideBackButton(true)
      .titleMode(HdsNavigationTitleMode.MINI)
      // 官方：绑定 Scroll 滚动 → scrollEffectOpts 才会根据滚动偏移激活 GradientBlur 渐变模糊
      .bindToScrollable([this.scroller])
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.color_bg_page'));
    } else {
      // ─── API < 26: Stack + 手工顶栏叠层（backgroundBlurStyle 降级）───
      Column() {
        Stack({ alignContent: Alignment.Top }) {
          this.scrollBody();
          // 顶栏层（上层）：blurStyle + 半透明底色糊住下层滚动内容
          this.fallbackTitleBar();
        }.width('100%').layoutWeight(1);
      }
      .width('100%').height('100%')
      .backgroundColor($r('app.color.color_bg_page'));
    }
  }

  // 读取持久化的主题偏好并回填共享状态（EntryAbility 启动时已应用过一次，此处仅同步 UI）。
  private async refreshColorMode(): Promise<void> {
    const v: string = await PreferencesUtil.getString(null, PreferencesUtil.KEY_COLOR_MODE, 'system');
    this.colorModeKey = this.COLOR_MODE_KEYS.includes(v) ? v : 'system';
  }

  // 切回“我的”Tab 时重新查询系统权限。
  private onHomeTabIndexChanged(): void {
    if (this.homeTabIndex === 2 && this.indexPageVisible) {
      this.refreshNotificationPermission();
    }
  }

  // 从系统设置或其他页面回到应用时重新查询系统权限。
  private onIndexPageVisibleChanged(): void {
    if (this.indexPageVisible && this.homeTabIndex === 2) {
      this.refreshNotificationPermission();
    }
  }

  // 系统状态未知时不误显示为“未开启”；异常仅影响提示卡片。
  private async refreshNotificationPermission(): Promise<void> {
    const queryId: number = ++this.permissionQueryId;
    try {
      const enabled: boolean = await notificationManager.isNotificationEnabled();
      if (queryId === this.permissionQueryId) {
        this.notificationPermissionStatus = enabled
          ? NotificationPermissionStatus.ENABLED : NotificationPermissionStatus.DISABLED;
      }
    } catch (err) {
      const message: string = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, 'MineView', '读取通知权限失败：%{public}s', message);
      if (queryId === this.permissionQueryId) {
        this.notificationPermissionStatus = NotificationPermissionStatus.ERROR;
      }
    }
  }

  // 通过顶部卡片打开系统通知设置；API 26+ 窗口关闭后立即刷新权限状态。
  private async openNotificationSettings(): Promise<void> {
    if (this.notificationSettingsOpening) {
      return;
    }
    const ctx: common.UIAbilityContext | null = ThemeService.getAbilityContext(this.getUIContext());
    if (!ctx) {
      showToast(this.getUIContext(), '上下文获取失败');
      return;
    }
    this.notificationSettingsOpening = true;
    try {
      // supportsImmersiveMaterial 仅判断 API 26+，不受用户光感开关或材质加载状态影响。
      if (supportsImmersiveMaterial()) {
        await notificationManager.openNotificationSettingsWithResult(ctx);
      } else {
        // 旧系统保留原有设置入口；页面恢复可见时仍会再次刷新状态。
        await notificationManager.openNotificationSettings(ctx);
      }
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      hilog.warn(DOMAIN, 'MineView', 'openNotificationSettings 失败：code=%{public}d msg=%{public}s',
        e.code, e.message);
      showToast(this.getUIContext(), '无法打开通知设置');
    } finally {
      this.notificationSettingsOpening = false;
      this.refreshNotificationPermission();
    }
  }
}
