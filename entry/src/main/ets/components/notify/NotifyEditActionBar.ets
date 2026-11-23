import { resolveBlurStyle, shouldUseSystemMaterialPath } from '../../utils/ImmersiveUtil';

/** 通知多选模式底部操作栏；选择状态与实际动作均由 NotifyView 管理。 */
@Component
export struct NotifyEditActionBar {
  @Prop selectedCount: number = 0;
  @Prop messageCount: number = 0;
  @Prop exporting: boolean = false;
  @Prop navBarHeight: number = 0;
  @Prop immersiveLightEnabled: boolean = true;
  onCancel: () => void = () => {};
  onToggleAll: () => void = () => {};
  onExport: () => void = () => {};
  onDelete: () => void = () => {};

  build() {
    Row() {
      Text($r('app.string.common_cancel')).fontSize(15)
        .fontColor($r('app.color.color_text_tertiary')).onClick(() => this.onCancel());
      Blank();
      Text(this.selectedCount === this.messageCount ? $r('app.string.ntf_deselect_all') :
        $r('app.string.ntf_select_all')).fontSize(15)
        .fontColor($r('app.color.color_text_tertiary')).padding({ right: 16 }).onClick(() => this.onToggleAll());
      Text(this.exporting ? $r('app.string.ntf_exporting') :
        $r('app.string.ntf_export_count', this.selectedCount)).fontSize(15)
        .fontColor(this.selectedCount > 0 && !this.exporting ? $r('app.color.color_brand') : $r('app.color.color_text_hint'))
        .padding({ right: 16 }).onClick(() => this.onExport());
      Text($r('app.string.ntf_delete_count', this.selectedCount)).fontSize(15)
        .fontColor(this.selectedCount > 0 ? $r('app.color.color_error') : $r('app.color.color_text_hint'))
        .onClick(() => this.onDelete());
    }
    .width('100%').padding({ left: 16, right: 16, top: 12,
      bottom: shouldUseSystemMaterialPath(this.immersiveLightEnabled) ? this.navBarHeight + 72 : this.navBarHeight + 64 })
    .backgroundBlurStyle(resolveBlurStyle('bar')!).backgroundColor($r('app.color.color_bg_glass'));
  }
}
