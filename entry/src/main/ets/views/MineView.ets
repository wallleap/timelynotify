import { PreferencesUtil } from '../utils/PreferencesUtil';
import { ThemeService } from '../services/ThemeService';
import {
  KEY_IMMERSIVE_LIGHT_ENABLED,
  resolveBlurStyle,
  SUPPORTS_IMMERSIVE_MATERIAL
} from '../utils/ImmersiveUtil';
import { hdsMaterial, HdsNavigation, HdsNavigationTitleMode, ScrollEffectType } from '@kit.UIDesignKit';
import { NotifySettingsSection } from '../components/minesections/NotifySettingsSection';
import { ServerEntrySection } from '../components/minesections/ServerEntrySection';
import { AppearanceSection } from '../components/minesections/AppearanceSection';
import { AppInfoSection } from '../components/minesections/AppInfoSection';
import { AboutSection } from '../components/minesections/AboutSection';

// 我的页 - 展示个人设置入口
@Component
export struct MineView {
  @State fallbackTitleBarBottom: number = -1;
  @State scrollTop: number = -1;
  // 状态栏/导航条高度（vp），EntryAbility 沉浸式布局初始化时写入 AppStorage（键值见 ImmersiveUtil）
  @StorageProp('statusBarHeight') statusBarHeight: number = 36;
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  // 沉浸光感开关值（API 26+ 生效；EntryAbility 启动时从 Preferences 写入 AppStorage）：
  // 入口行状态文本与各页面渲染分支均读此权威值；切换走 Dialog → 重启确认 → 重启应用生效
  @StorageProp(KEY_IMMERSIVE_LIGHT_ENABLED) immersiveLightEnabled: boolean = true;
  // 主题颜色模式选中索引：0=跟随系统 1=浅色 2=深色（与 COLOR_MODE_KEYS/ICONS 顺序一致）
  @State @Watch('onColorModeIndexChanged') colorModeIndex: number = 0;
  // 冷启动回填是否完成：回填阶段赋值不触发持久化/切换（EntryAbility 启动流程已应用过一次）
  private colorModeInitialized: boolean = false;
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

  aboutToAppear() {
    this.refreshColorMode();
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
            .fontColor([idx === this.colorModeIndex ? $r('app.color.color_brand') :
              $r('app.color.color_text_tertiary')])
        }
        .width(32)
        .height(32)
        .borderRadius(16)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(idx === this.colorModeIndex ? $r('app.color.color_state_brand_selected') :
          Color.Transparent)
        .onClick(() => {
          this.colorModeIndex = idx;
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
          .height(SUPPORTS_IMMERSIVE_MATERIAL && this.immersiveLightEnabled ? 0 :
            (this.fallbackTitleBarBottom >= 0 && this.scrollTop >= 0
              ? Math.max(0, this.fallbackTitleBarBottom - this.scrollTop) : 0));

        // 通知设置板块（开关 / 通知权限设置 / 测试通知 / 导出通知）
        NotifySettingsSection();

        // 配置板块（服务器入口卡片）
        ServerEntrySection();

        // 外观板块（仅 API 26+ 显示）：沉浸光感入口行
        if (SUPPORTS_IMMERSIVE_MATERIAL) {
          AppearanceSection();
        }

        // 信息板块（构建信息 + 推送 Token）
        AppInfoSection();

        // 关于板块（当前版本 / 开源代码 / 使用文档 / 隐私协议 / 反馈问题）
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
    if (SUPPORTS_IMMERSIVE_MATERIAL && this.immersiveLightEnabled) {
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

  // 读取持久化的主题偏好并回填选中索引（EntryAbility 启动时已应用过一次，此处仅同步 UI）
  private async refreshColorMode(): Promise<void> {
    const v: string = await PreferencesUtil.getString(null, PreferencesUtil.KEY_COLOR_MODE, 'system');
    const idx: number = this.COLOR_MODE_KEYS.indexOf(v);
    this.colorModeIndex = idx >= 0 ? idx : 0;
    this.colorModeInitialized = true; // 回填完成后，用户点击才触发持久化/切换
  }

  // 主题切换回调（@Watch）：持久化用户选择并即时应用到全局颜色模式
  private onColorModeIndexChanged(): void {
    if (!this.colorModeInitialized) {
      return; // 冷启动回填阶段，避免重复写盘/切换（启动流程已处理）
    }
    const idx: number = this.colorModeIndex;
    const key: string = (idx >= 0 && idx < this.COLOR_MODE_KEYS.length) ? this.COLOR_MODE_KEYS[idx] : 'system';
    ThemeService.applyColorMode(key, this.getUIContext());
  }
}
