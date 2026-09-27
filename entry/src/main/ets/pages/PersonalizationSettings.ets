import {
  KEY_IMMERSIVE_LIGHT_ENABLED,
  resolveBlurStyle,
  SUPPORTS_IMMERSIVE_MATERIAL
} from '../utils/ImmersiveUtil';
import { AppearanceSection } from '../components/minesections/AppearanceSection';
import { hdsMaterial, HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit';

/**
 * 个性化设置页：集中承载会影响全局视觉呈现的偏好项。
 * 沉浸光感的持久化和重启逻辑仍由 AppearanceSection 统一处理，避免改变原有行为。
 */
@Entry
@Component
struct PersonalizationSettings {
  @StorageProp('statusBarHeight') statusBarHeight: number = 36;
  @StorageProp(KEY_IMMERSIVE_LIGHT_ENABLED) immersiveLightEnabled: boolean = true;

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
    .backgroundColor($r('app.color.color_bg_glass'));
  }

  @Builder
  settingsBody() {
    Column() {
      AppearanceSection();
      Blank();
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16, top: 16, bottom: 16 });
  }

  build() {
    if (SUPPORTS_IMMERSIVE_MATERIAL && this.immersiveLightEnabled) {
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
          // 独立设置页沿用应用的自适应沉浸材质，和主页面保持一致。
          systemMaterialEffect: {
            materialType: hdsMaterial.MaterialType.ADAPTIVE,
            materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
          }
        }
      })
      .hideBackButton(false)
      .titleMode(HdsNavigationTitleMode.MINI)
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.color_bg_page'));
    } else {
      Column() {
        this.fallbackTitleBar();
        this.settingsBody();
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.color_bg_page'));
    }
  }

  // 从独立设置页返回“我的”页，系统返回手势也复用同一行为。
  private goBack(): void {
    this.getUIContext().getRouter().back();
  }

  onBackPress(): boolean {
    this.goBack();
    return true;
  }
}
