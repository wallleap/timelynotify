import {
  AntiPeepService, ANTI_PEEP_MODE_BLUR, ANTI_PEEP_MODE_FULLSCREEN,
  KEY_ANTI_PEEP_ERROR, KEY_ANTI_PEEP_PREVIEW_VISIBLE
} from '../../services/AntiPeepService';
import showToast from '../showToast';
import { SettingCell } from './SettingCell';
import { SettingGroup } from './SettingGroup';

/** 防窥开关和两种可选效果；预览只使用示意内容，不模拟或更改系统防窥状态。 */
@Component
export struct AntiPeepSettingsCard {
  @State antiPeepEnabled: boolean = false;
  @State selectedMode: string = ANTI_PEEP_MODE_BLUR;
  @State loaded: boolean = false;
  @State saving: boolean = false;
  @State previewHidden: boolean = false;
  @StorageProp(KEY_ANTI_PEEP_ERROR) runtimeError: string = '';
  @StorageProp(KEY_ANTI_PEEP_PREVIEW_VISIBLE) @Watch('updatePreview') pageVisible: boolean = false;
  private mounted: boolean = false;
  private inViewport: boolean = false;
  private previewTimer: number = -1;
  private previewGeneration: number = 0;

  /** 使用示意文本的微缩页面，两张预览共享同一轮正常/防窥状态，便于比较。 */
  @Builder
  private miniature(mode: string) {
    Stack({ alignContent: Alignment.Center }) {
      Column({ space: 9 }) {
        Row() {
          Text('通知').fontSize(10).fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.color_text_primary'));
          Blank();
          Image($r('app.media.search')).width(12).height(12)
            .fillColor($r('app.color.color_text_hint')).draggable(false);
        }.width('100%');
        Column({ space: 7 }) {
          ForEach([0, 1, 2], (index: number) => {
            Column({ space: 3 }) {
              // 与真实通知一致：仅标题、正文各自模糊，卡片轮廓保持清晰。
              Text(index === 0 ? '工作提醒' : index === 1 ? '验证码' : '日程通知')
                .fontSize(9).fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.color_text_primary')).maxLines(1)
                .blur(this.antiPeepEnabled && this.previewHidden && mode === ANTI_PEEP_MODE_BLUR ? 5 : 0);
              Text(index === 0 ? '会议将在十分钟后开始' : index === 1 ? '验证码 123456' : '今天有一项待办事项')
                .fontSize(8).fontColor($r('app.color.color_text_tertiary'))
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                .blur(this.antiPeepEnabled && this.previewHidden && mode === ANTI_PEEP_MODE_BLUR ? 5 : 0);
            }
            .width('100%').padding(6).alignItems(HorizontalAlign.Start)
            .backgroundColor($r('app.color.color_bg_surface')).borderRadius(7);
          });
        }
        .width('100%');
        Row().width(44).height(4).borderRadius(2)
          .backgroundColor($r('app.color.color_border_default'));
      }
      .width('100%').padding(10);
      if (this.antiPeepEnabled && this.previewHidden && mode === ANTI_PEEP_MODE_FULLSCREEN) {
        Column({ space: 8 }) {
          Image($r('app.media.shield_keyhole')).width(26).height(26)
            .fillColor($r('app.color.color_brand')).draggable(false);
          Text('隐私防窥').fontSize(11).fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.color_text_primary'));
        }
        .width('100%').height('100%').justifyContent(FlexAlign.Center)
        .backgroundColor($r('app.color.color_bg_surface_muted'))
        .transition(TransitionEffect.OPACITY.animation({ duration: 200 }));
      }
    }
    .width('100%').height(174).borderRadius(10).clip(true)
    .backgroundColor($r('app.color.color_bg_surface_muted'))
    .accessibilityLevel('no-hide-descendants');
  }

  /** 选中态和可操作状态均由开关控制，关闭时不启动动画也不能更改模式。 */
  @Builder
  private modeCard(mode: string, title: string, description: string) {
    Column({ space: 10 }) {
      this.miniature(mode);
      Row({ space: 5 }) {
        Stack() {
          if (this.selectedMode === mode) {
            Row().width(6).height(6).borderRadius(3)
              .backgroundColor(this.antiPeepEnabled ? $r('app.color.color_brand') :
                $r('app.color.color_text_hint'));
          }
        }
        .width(13).height(13).borderRadius(7)
        .border({ width: 1.5, color: this.antiPeepEnabled && this.selectedMode === mode ?
          $r('app.color.color_brand') : $r('app.color.color_text_hint') });
        Text(title).fontSize(13).fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.color_text_primary'));
      }
      .width('100%').alignItems(VerticalAlign.Center);
      Text(description).fontSize(11).fontColor($r('app.color.color_text_tertiary'))
        .width('100%').constraintSize({ minHeight: 32 });
    }
    .layoutWeight(1).padding(9).alignItems(HorizontalAlign.Start)
    .borderRadius(14)
    .border({ width: this.selectedMode === mode ? 1.5 : 1,
      color: this.antiPeepEnabled && this.selectedMode === mode ?
        $r('app.color.color_brand') : $r('app.color.color_border_default') })
    .opacity(this.antiPeepEnabled ? 1 : 0.45)
    .saturate(this.antiPeepEnabled ? 1 : 0)
    .enabled(this.loaded && this.antiPeepEnabled && !this.saving)
    .accessibilityText(title + (this.selectedMode === mode ? '，已选中' : ''))
    .onClick(() => this.changeMode(mode));
  }

  build() {
    Column() {
      SettingGroup() {
        SettingCell({ title: '隐私防窥' }) {
          Toggle({ type: ToggleType.Switch, isOn: this.antiPeepEnabled })
            .id('anti_peep_enabled_toggle')
            .selectedColor($r('app.color.color_brand'))
            .enabled(this.loaded && !this.saving)
            .onChange((enabled: boolean) => this.changeEnabled(enabled));
        }
        Row({ space: 12 }) {
          this.modeCard(ANTI_PEEP_MODE_BLUR, '模糊通知', '有人窥视时，模糊通知文字。');
          this.modeCard(ANTI_PEEP_MODE_FULLSCREEN, '全屏防窥', '有人窥视时，遮住整个应用。');
        }
        .width('100%').alignItems(VerticalAlign.Top)
        .padding({ left: 16, right: 16, bottom: 16 });
        if (this.antiPeepEnabled && this.runtimeError.length > 0) {
          Text(this.runtimeError).fontSize(12).fontColor($r('app.color.color_warning'))
            .width('100%').padding({ left: 16, right: 16, bottom: 16 });
        }
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
    this.loadSettings();
  }

  aboutToDisappear(): void {
    this.mounted = false;
    this.stopPreview();
  }

  /** 加载前禁用操作；关闭状态的预览始终静止且置灰。 */
  private async loadSettings(): Promise<void> {
    const settings = await AntiPeepService.getSettings();
    if (!this.mounted) return;
    this.antiPeepEnabled = settings.enabled;
    this.selectedMode = settings.mode;
    this.loaded = true;
    this.updatePreview();
  }

  /** 系统开启引导取消、权限失败或保存失败时恢复原开关。 */
  private async changeEnabled(enabled: boolean): Promise<void> {
    if (!this.loaded || this.saving || enabled === this.antiPeepEnabled) return;
    const previous: boolean = this.antiPeepEnabled;
    this.saving = true;
    this.antiPeepEnabled = enabled;
    this.updatePreview();
    try {
      if (!(await AntiPeepService.setEnabled(enabled)) && this.mounted) {
        this.antiPeepEnabled = previous;
        showToast(this.getUIContext(), AntiPeepService.getError() || '设置未生效');
      }
    } catch (_err) {
      if (this.mounted) {
        this.antiPeepEnabled = previous;
        showToast(this.getUIContext(), '设置未生效');
      }
    } finally {
      if (this.mounted) {
        this.saving = false;
        this.updatePreview();
      }
    }
  }

  /** 模式选择与开关使用同一保存锁，只有写盘成功才保留选中态。 */
  private async changeMode(mode: string): Promise<void> {
    if (!this.loaded || this.saving || !this.antiPeepEnabled || mode === this.selectedMode) return;
    const previous: string = this.selectedMode;
    this.saving = true;
    this.selectedMode = mode;
    try {
      if (!(await AntiPeepService.setMode(mode)) && this.mounted) {
        this.selectedMode = previous;
        showToast(this.getUIContext(), AntiPeepService.getError() || '保存失败');
      }
    } catch (_err) {
      if (this.mounted) {
        this.selectedMode = previous;
        showToast(this.getUIContext(), '保存失败');
      }
    } finally {
      if (this.mounted) this.saving = false;
    }
  }

  /** 页面和视口可见、开关开启才演示，关闭或离页立即废弃旧回调。 */
  private updatePreview(): void {
    this.stopPreview();
    if (this.mounted && this.pageVisible && this.inViewport && this.loaded && this.antiPeepEnabled) {
      this.schedulePreview(this.previewGeneration);
    }
  }

  private schedulePreview(generation: number): void {
    this.previewTimer = setTimeout(() => {
      this.previewTimer = -1;
      if (generation !== this.previewGeneration) return;
      this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseInOut }, () => {
        this.previewHidden = !this.previewHidden;
      });
      this.schedulePreview(generation);
    }, 1800);
  }

  private stopPreview(): void {
    this.previewGeneration++;
    if (this.previewTimer >= 0) {
      clearTimeout(this.previewTimer);
      this.previewTimer = -1;
    }
    this.previewHidden = false;
  }
}
