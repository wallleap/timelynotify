import { HoldingHandService } from '../../services/HoldingHandService';
import showToast from '../showToast';
import { SettingCell } from './SettingCell';
import { SettingGroup } from './SettingGroup';

/** 独立设置页的可见信号，用于在离页或退后台时停止预览动画。 */
export const KEY_HOLDING_HAND_PREVIEW_VISIBLE: string = 'holdingHandPreviewVisible';

/** 智感握姿设置及示意预览；演示只使用本地占位内容，不订阅实际握姿。 */
@Component
export struct HoldingHandSettingsCard {
  @State holdingEnabled: boolean = true;
  @State loaded: boolean = false;
  @State saving: boolean = false;
  @State previewLeft: boolean = false;
  @State previewOpacity: number = 1;
  @StorageProp(KEY_HOLDING_HAND_PREVIEW_VISIBLE) @Watch('onPageVisibilityChanged') pageVisible: boolean = false;
  // 页面可见且卡片进入视口才循环；代次使旧动画回调不能重新启动已停止的预览。
  private mounted: boolean = false;
  private inViewport: boolean = false;
  private previewTimer: number = -1;
  private previewGeneration: number = 0;

  /** 模拟顶栏的按钮组，颜色与真实页面使用同一套亮暗主题资源。 */
  @Builder
  private previewActions() {
    Row({ space: 6 }) {
      ForEach([$r('app.media.select_more'), $r('app.media.trash1'), $r('app.media.search')],
        (icon: Resource) => {
          Image(icon)
            .width(24)
            .height(24)
            .padding(5)
            .objectFit(ImageFit.Contain)
            .fillColor($r('app.color.color_brand'))
            .backgroundColor($r('app.color.color_brand_container'))
            .borderRadius(12)
            .draggable(false);
        });
    }
    .position({ x: this.previewLeft ? 0 : 156, y: 0 })
    .opacity(this.previewOpacity);
  }

  /** 固定尺寸的微缩通知页，使左右演示不受设备宽度或真实通知内容影响。 */
  @Builder
  private preview() {
    Column({ space: 10 }) {
      Stack({ alignContent: Alignment.TopStart }) {
        Row() {
          Text('全部通知')
            .fontSize(13)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.color_text_primary'));
        }
        .position({ x: this.previewLeft ? 156 : 0, y: 3 })
        .opacity(this.previewOpacity);
        this.previewActions();

        Column({ space: 8 }) {
          ForEach([0, 1, 2], (index: number) => {
            Column({ space: 6 }) {
              Row()
                .width(index === 1 ? '42%' : '58%')
                .height(5)
                .borderRadius(3)
                .backgroundColor($r('app.color.color_border_default'));
              Row()
                .width(index === 1 ? '76%' : '90%')
                .height(4)
                .borderRadius(2)
                .backgroundColor($r('app.color.color_border_subtle'));
            }
            .width('100%')
            .padding(10)
            .alignItems(HorizontalAlign.Start)
            .backgroundColor($r('app.color.color_bg_surface'))
            .borderRadius(8);
          });
        }
        .width(240)
        .position({ x: 0, y: 34 });

        Column({ space: 6 }) {
          Image($r('app.media.group_collapse'))
            .width(26)
            .height(26)
            .padding(6)
            .objectFit(ImageFit.Contain)
            .fillColor($r('app.color.color_brand'))
            .backgroundColor($r('app.color.color_brand_container'))
            .borderRadius(13)
            .draggable(false);
          Image($r('app.media.select_more'))
            .width(26)
            .height(26)
            .padding(6)
            .objectFit(ImageFit.Contain)
            .fillColor($r('app.color.color_brand'))
            .backgroundColor($r('app.color.color_brand_container'))
            .borderRadius(13)
            .draggable(false);
        }
        .position({ x: this.previewLeft ? 6 : 208, y: 100 })
        .opacity(this.previewOpacity)
        .translate({ x: (this.previewLeft ? -14 : 14) * (1 - this.previewOpacity) });
      }
      .width(240)
      .height(164)
      .clip(true)
      .accessibilityLevel('no-hide-descendants');

      Text(this.holdingEnabled ? (this.previewLeft ? '左手握持' : '右手握持') : '固定右侧')
        .fontSize(12)
        .fontColor(this.holdingEnabled ? $r('app.color.color_brand') : $r('app.color.color_text_tertiary'));
    }
    .width('100%')
    .padding({ top: 16, bottom: 12 })
    .backgroundColor($r('app.color.color_bg_surface_muted'))
    .borderRadius(12)
    .accessibilityText(this.holdingEnabled ? '智感握姿效果预览，按钮随握姿左右切换' : '智感握姿已关闭，按钮固定右侧')
    .hitTestBehavior(HitTestMode.None);
  }

  build() {
    Column() {
      SettingGroup() {
        SettingCell({ title: '智感握姿' }) {
          Toggle({ type: ToggleType.Switch, isOn: this.holdingEnabled })
            .id('holding_hand_enabled_toggle')
            .selectedColor($r('app.color.color_brand'))
            .enabled(this.loaded && !this.saving)
            .onChange((enabled: boolean) => this.changeEnabled(enabled));
        }
        Column({ space: 12 }) {
          this.preview();
          Text(this.holdingEnabled ? '按钮随握姿左右切换，单手操作更顺手。' : '按钮固定在右侧，不随握姿切换。')
            .fontSize(12)
            .fontColor($r('app.color.color_text_tertiary'))
            .width('100%');
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 16 });
      }
    }
    .width('100%')
    .onVisibleAreaChange([0, 1], (_visible: boolean, ratio: number) => {
      this.inViewport = ratio > 0;
      this.updatePreview();
    });
  }

  aboutToAppear(): void {
    this.mounted = true;
    this.loadEnabled();
  }

  aboutToDisappear(): void {
    this.mounted = false;
    this.stopPreview();
  }

  /** 读取完成前禁用开关，避免默认开启态覆盖已保存的关闭偏好。 */
  private async loadEnabled(): Promise<void> {
    const enabled: boolean = await HoldingHandService.isEnabled();
    if (!this.mounted) return;
    this.holdingEnabled = enabled;
    this.loaded = true;
    this.updatePreview();
  }

  /** 即时回显目标状态，保存失败恢复原状态；服务只在写盘成功后变更监听。 */
  private async changeEnabled(enabled: boolean): Promise<void> {
    if (!this.loaded || this.saving || enabled === this.holdingEnabled) return;
    const previous: boolean = this.holdingEnabled;
    this.saving = true;
    this.holdingEnabled = enabled;
    this.updatePreview();
    try {
      if (!(await HoldingHandService.setEnabled(enabled)) && this.mounted) {
        this.holdingEnabled = previous;
        showToast(this.getUIContext(), '保存失败，设置未生效');
      }
    } catch (_err) {
      if (this.mounted) {
        this.holdingEnabled = previous;
        showToast(this.getUIContext(), '保存失败，设置未生效');
      }
    } finally {
      if (this.mounted) {
        this.saving = false;
        this.updatePreview();
      }
    }
  }

  /** 页面退后台同样停掉循环；恢复前台后重新从右侧开始演示。 */
  private onPageVisibilityChanged(): void {
    this.updatePreview();
  }

  /** 每次状态变化重建一个循环，关闭、不可见或离页时只保留静态右侧预览。 */
  private updatePreview(): void {
    this.stopPreview();
    if (this.mounted && this.pageVisible && this.inViewport && this.loaded && this.holdingEnabled) {
      this.schedulePreview(this.previewGeneration);
    }
  }

  /** 延时后淡出、换侧、淡入；不在组件声明或销毁阶段直接启动动画。 */
  private schedulePreview(generation: number): void {
    this.previewTimer = setTimeout(() => {
      this.previewTimer = -1;
      if (generation !== this.previewGeneration) return;
      this.getUIContext().animateTo({ duration: 120, curve: Curve.EaseIn, onFinish: () => {
        if (generation !== this.previewGeneration) return;
        this.previewLeft = !this.previewLeft;
        this.previewTimer = setTimeout(() => {
          this.previewTimer = -1;
          if (generation !== this.previewGeneration) return;
          this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseOut, onFinish: () => {
            if (generation === this.previewGeneration) this.schedulePreview(generation);
          } }, () => { this.previewOpacity = 1; });
        }, 16);
      } }, () => { this.previewOpacity = 0; });
    }, 1800);
  }

  /** 代次拦截迟到的 onFinish，确保停止后没有后台定时器重新创建。 */
  private stopPreview(): void {
    this.previewGeneration++;
    if (this.previewTimer >= 0) {
      clearTimeout(this.previewTimer);
      this.previewTimer = -1;
    }
    this.previewLeft = false;
    this.previewOpacity = 1;
  }
}
