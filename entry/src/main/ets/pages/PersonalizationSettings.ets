import {
  getDialogMaterial,
  IMMERSIVE_SELECT_MENU_MODIFIER,
  KEY_IMMERSIVE_LIGHT_ENABLED,
  resolveBlurStyle,
  shouldUseSystemMaterialPath,
  supportsImmersiveMaterial
} from '../utils/ImmersiveUtil';
import { AppearanceSection } from '../components/minesections/AppearanceSection';
import { SettingGroup } from '../components/settings/SettingGroup';
import { SettingGroupTitle } from '../components/settings/SettingGroupTitle';
import { SettingCell } from '../components/settings/SettingCell';
import {
  HoldingHandSettingsCard,
  KEY_HOLDING_HAND_PREVIEW_VISIBLE
} from '../components/settings/HoldingHandSettingsCard';
import { ThemeService } from '../services/ThemeService';
import { EncryptedNotificationResendService } from '../services/EncryptedNotificationResendService';
import { NotifyClickSettingsService } from '../services/NotifyClickSettingsService';
import { HoldingHandService } from '../services/HoldingHandService';
import { AntiPeepSettingsCard } from '../components/settings/AntiPeepSettingsCard';
import { AntiPeepService, KEY_ANTI_PEEP_PREVIEW_VISIBLE } from '../services/AntiPeepService';
import showToast from '../components/showToast';
import { hdsMaterial, HdsNavigation, HdsNavigationTitleMode, ScrollEffectType } from '@kit.UIDesignKit';

/**
 * 个性化设置页：承载外观、通知点击及重发、智感握姿等偏好，支持系统材质时额外显示沉浸光感。
 * 主题模式与 MineView 共用 color_mode 页面状态；沉浸光感的持久化和重启逻辑仍由 AppearanceSection 处理。
 */
@Entry
@Component
struct PersonalizationSettings {
  @State fallbackTitleBarBottom: number = -1;
  @State scrollTop: number = -1;
  @StorageProp('statusBarHeight') statusBarHeight: number = 36;
  @StorageProp(KEY_IMMERSIVE_LIGHT_ENABLED) immersiveLightEnabled: boolean = true;
  // 与 MineView 的主题图标选择器共用状态；值与 PreferencesUtil.KEY_COLOR_MODE 一致。
  @StorageLink('color_mode') colorModeKey: string = 'system';
  @State encryptedResendEnabled: boolean = false;
  @State encryptedResendLoaded: boolean = false;
  @State encryptedResendSaving: boolean = false;
  // 读完偏好前禁用开关；保存期间阻止连点，失败恢复已持久化的状态。
  @State notifyClickUrlEnabled: boolean = true;
  @State notifyClickUrlLoaded: boolean = false;
  @State notifyClickUrlSaving: boolean = false;
  // 未确认支持前不渲染卡片和空分组，避免不支持设备出现入口闪现。
  @State holdingHandSupported: boolean = false;
  @State antiPeepSupported: boolean = false;
  // 页面销毁或重新挂载后，旧读写回调不能覆盖新页面状态。
  private notifyClickSettingsGeneration: number = 0;
  // 异步能力查询不能在页面离开后补渲染卡片。
  private supportCheckSequence: number = 0;
  private readonly colorModeKeys: string[] = ['system', 'light', 'dark'];
  private readonly colorModeLabels: string[] = ['跟随系统', '浅色模式', '深色模式'];
  private scroller: Scroller = new Scroller();

  @Builder
  fallbackTitleBar() {
    Row({ space: 8 }) {
      Image($r('app.media.arrow_left'))
        .width(32)
        .height(32)
        .objectFit(ImageFit.Contain)
        .fillColor($r('app.color.color_text_primary'))
        .padding(4)
        .draggable(false)
        .onClick(() => {
          this.goBack();
        });

      Text('个性化设置')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.color_text_primary'))
        .layoutWeight(1);
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({
      left: 12,
      right: 16,
      top: 12 + this.statusBarHeight,
      bottom: 12
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

  @Builder
  settingsContent() {
    Column({ space: 16 }) {
      if (!shouldUseSystemMaterialPath(this.immersiveLightEnabled)) {
        // 降级标题栏覆盖在 Scroll 上方；按实测重叠高度占位，避免首个设置项被遮挡。
        Row()
          .width('100%')
          .height(this.fallbackTitleBarBottom >= 0 && this.scrollTop >= 0
            ? Math.max(0, this.fallbackTitleBarBottom - this.scrollTop) : 0);
      }

      Column({ space: 12 }) {
        SettingGroupTitle({ title: '外观' });

        SettingGroup() {
          SettingCell({ title: '主题模式' }) {
            Select([
              { value: '跟随系统' },
              { value: '浅色模式' },
              { value: '深色模式' }
            ])
              .selected(this.selectedColorModeIndex())
              .value(this.colorModeLabels[this.selectedColorModeIndex()])
              // 仅缩小选择器外层选中值文字（12sp，与同行右侧状态小字一致）；下拉菜单项由 optionFont 独立控制不受影响
              .font({ size: 12 })
              .fontColor($r('app.color.color_text_primary'))
              .selectedOptionBgColor($r('app.color.color_bg_selected_glass'))
              .selectedOptionFontColor($r('app.color.color_brand'))
              .attributeModifier(IMMERSIVE_SELECT_MENU_MODIFIER)
              .onSelect((index: number) => {
                if (index < 0 || index >= this.colorModeKeys.length) {
                  return;
                }
                const key: string = this.colorModeKeys[index];
                this.colorModeKey = key;
                ThemeService.applyColorMode(key, this.getUIContext());
              });
          }
        }

        if (supportsImmersiveMaterial()) {
          AppearanceSection();
        }
      }
      .width('100%');

      Column({ space: 12 }) {
        SettingGroupTitle({ title: '通知行为' });

        SettingGroup() {
          SettingCell({ title: '通知点击跳转链接', description: '关闭后点击通知卡片仅打开通知详情' }) {
            Toggle({ type: ToggleType.Switch, isOn: this.notifyClickUrlEnabled })
              .selectedColor($r('app.color.color_brand'))
              .enabled(this.notifyClickUrlLoaded && !this.notifyClickUrlSaving)
              .onChange((isOn: boolean) => {
                this.changeNotifyClickUrl(isOn);
              });
          }
        }

        // 只影响后续新同步的加密通知是否补发，不修改消息的 isArchive 留存策略。
        SettingGroup() {
          SettingCell({ title: '加密通知重发' }) {
            Toggle({ type: ToggleType.Switch, isOn: this.encryptedResendEnabled })
              .selectedColor($r('app.color.color_brand'))
              .enabled(this.encryptedResendLoaded && !this.encryptedResendSaving)
              .onChange((isOn: boolean) => {
                this.changeEncryptedResend(isOn);
              });
          }
        }
      }
      .width('100%')
      .margin({ top: 8 });

      // 两项能力独立检测，任一可用时保留分组，避免防窥依赖握姿设备能力。
      if (this.holdingHandSupported || this.antiPeepSupported) {
        Column({ space: 12 }) {
          SettingGroupTitle({ title: '鸿蒙特性' });
          if (this.holdingHandSupported) {
            HoldingHandSettingsCard();
          }
          if (this.antiPeepSupported) {
            AntiPeepSettingsCard();
          }
        }
        .width('100%')
        .margin({ top: 8 });
      }
    }
    .width('100%')
    .padding({
      left: 16,
      right: 16,
      top: shouldUseSystemMaterialPath(this.immersiveLightEnabled) ? 16 : 0,
      bottom: 16
    });
  }

  @Builder
  settingsBody() {
    Scroll(this.scroller) {
      this.settingsContent();
    }
    .align(Alignment.TopStart)
    .width('100%')
    .height('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .onAreaChange((_old: Area, area: Area) => {
      const top: number = area.globalPosition.y as number;
      if (top !== this.scrollTop) {
        this.scrollTop = top;
      }
    })
    .clip(false);
  }

  aboutToAppear(): void {
    this.loadEncryptedResend();
    this.loadNotifyClickUrl(++this.notifyClickSettingsGeneration);
  }

  aboutToDisappear(): void {
    this.notifyClickSettingsGeneration++;
  }

  /** 预览只在当前页面前台可见时播放，不改变首页的握姿订阅门禁。 */
  onPageShow(): void {
    // 支持结果与持久化开关独立；权限或临时服务错误可在再次进入时重新检测。
    this.holdingHandSupported = HoldingHandService.checkSupport();
    this.checkAntiPeepSupport();
    AppStorage.setOrCreate(KEY_HOLDING_HAND_PREVIEW_VISIBLE, true);
    AppStorage.setOrCreate(KEY_ANTI_PEEP_PREVIEW_VISIBLE, true);
  }

  onPageHide(): void {
    this.supportCheckSequence++;
    AppStorage.setOrCreate(KEY_HOLDING_HAND_PREVIEW_VISIBLE, false);
    AppStorage.setOrCreate(KEY_ANTI_PEEP_PREVIEW_VISIBLE, false);
  }

  build() {
    if (shouldUseSystemMaterialPath(this.immersiveLightEnabled)) {
      HdsNavigation() {
        this.settingsBody();
      }
      .titleBar({
        enableComponentSafeArea: true,
        avoidLayoutSafeArea: true,
        content: {
          title: { mainTitle: '个性化设置' },
          backIcon: {
            icon: $r('app.media.arrow_left'),
            action: (): void => {
              this.goBack();
            }
          }
        },
        style: {
          scrollEffectOpts: {
            enableScrollEffect: true,
            scrollEffectType: ScrollEffectType.GRADIENT_BLUR
          },
          // 独立设置页沿用应用的自适应沉浸材质，和主页面保持一致。
          systemMaterialEffect: {
            materialType: hdsMaterial.MaterialType.ADAPTIVE,
            materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
          }
        }
      })
      .hideBackButton(false)
      .titleMode(HdsNavigationTitleMode.MINI)
      .bindToScrollable([this.scroller])
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.color_bg_page'));
    } else {
      Column() {
        Stack({ alignContent: Alignment.Top }) {
          this.settingsBody();
          this.fallbackTitleBar();
        }
        .width('100%')
        .layoutWeight(1);
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.color_bg_page'));
    }
  }

  onBackPress(): boolean {
    this.goBack();
    return true;
  }

  private selectedColorModeIndex(): number {
    const index: number = this.colorModeKeys.indexOf(this.colorModeKey);
    return index >= 0 ? index : 0;
  }

  /** 恢复已保存的点击行为，避免默认开启回显覆盖用户的关闭设置。 */
  private async loadNotifyClickUrl(generation: number): Promise<void> {
    const enabled: boolean = await NotifyClickSettingsService.isUrlEnabled();
    if (generation !== this.notifyClickSettingsGeneration) {
      return;
    }
    this.notifyClickUrlEnabled = enabled;
    this.notifyClickUrlLoaded = true;
  }

  /** 本项无需重启；仅写盘成功才改变两个系统通知点击入口的实际行为。 */
  private async changeNotifyClickUrl(enabled: boolean): Promise<void> {
    if (!this.notifyClickUrlLoaded || this.notifyClickUrlSaving || enabled === this.notifyClickUrlEnabled) {
      return;
    }
    const previous: boolean = this.notifyClickUrlEnabled;
    const generation: number = this.notifyClickSettingsGeneration;
    this.notifyClickUrlSaving = true;
    this.notifyClickUrlEnabled = enabled;
    try {
      const saved: boolean = await NotifyClickSettingsService.setUrlEnabled(enabled);
      if (generation !== this.notifyClickSettingsGeneration) {
        return;
      }
      if (!saved) {
        this.notifyClickUrlEnabled = previous;
        showToast(this.getUIContext(), '保存失败，设置未生效');
      }
    } catch (_err) {
      if (generation !== this.notifyClickSettingsGeneration) {
        return;
      }
      this.notifyClickUrlEnabled = previous;
      showToast(this.getUIContext(), '保存失败，设置未生效');
    } finally {
      if (generation === this.notifyClickSettingsGeneration) {
        this.notifyClickUrlSaving = false;
      }
    }
  }

  /** 查询不改变系统防窥开关；ACL 或暂时错误可以在再次进入页面时重试。 */
  private async checkAntiPeepSupport(): Promise<void> {
    const sequence: number = ++this.supportCheckSequence;
    const supported: boolean = await AntiPeepService.checkSupport();
    if (sequence === this.supportCheckSequence) {
      this.antiPeepSupported = supported;
    }
  }

  /** 进入页面时恢复持久化开关；读完前禁用 Toggle，避免默认关闭态覆盖已保存的开启态。 */
  private async loadEncryptedResend(): Promise<void> {
    this.encryptedResendEnabled = await EncryptedNotificationResendService.isEnabled();
    this.encryptedResendLoaded = true;
  }

  /** 切换前说明对应行为；仅确认且写盘成功后保留新状态，取消或失败时回滚。 */
  private async changeEncryptedResend(enabled: boolean): Promise<void> {
    if (!this.encryptedResendLoaded || this.encryptedResendSaving || enabled === this.encryptedResendEnabled) {
      return;
    }
    const previous: boolean = this.encryptedResendEnabled;
    this.encryptedResendSaving = true;
    // Toggle 点击后先回显目标状态；取消或保存失败时恢复已持久化状态。
    this.encryptedResendEnabled = enabled;
    try {
      const result = await this.getUIContext().getPromptAction().showDialog({
        title: enabled ? '开启加密通知重发' : '关闭加密通知重发',
        message: enabled
          ? '开启后收到加密通知 打开 APP 将解密并重新发送一条解密后的通知'
          : '关闭后收到加密通知仅解密保存 不再重新发送解密通知（isArchive为0 的加密通知为避免信息丢失仍会重新通知）',
        buttons: [
          { text: '取消', color: $r('app.color.color_text_tertiary') },
          { text: '确定', color: $r('app.color.color_brand') }
        ],
        systemMaterial: getDialogMaterial(),
      });
      if (result.index !== 1) {
        this.encryptedResendEnabled = previous;
        return;
      }
      if (!(await EncryptedNotificationResendService.setEnabled(enabled))) {
        this.encryptedResendEnabled = previous;
        showToast(this.getUIContext(), '保存失败，设置未生效');
      }
    } catch (_err) {
      this.encryptedResendEnabled = previous;
      showToast(this.getUIContext(), '保存失败，设置未生效');
    } finally {
      this.encryptedResendSaving = false;
    }
  }

  // 从独立设置页返回“我的”页，系统返回手势也复用同一行为。
  private goBack(): void {
    this.getUIContext().getRouter().back();
  }
}
