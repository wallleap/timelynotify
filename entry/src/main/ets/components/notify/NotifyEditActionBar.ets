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
      Text('取消').fontSize(15).fontColor($r('app.color.color_text_tertiary')).onClick(() => this.onCancel());
      Blank();
      Text(this.selectedCount === this.messageCount ? '取消全选' : '全选').fontSize(15)
        .fontColor($r('app.color.color_text_tertiary')).padding({ right: 16 }).onClick(() => this.onToggleAll());
      Text(this.exporting ? '导出中…' : `导出(${this.selectedCount})`).fontSize(15)
        .fontColor(this.selectedCount > 0 && !this.exporting ? $r('app.color.color_brand') : $r('app.color.color_text_hint'))
        .padding({ right: 16 }).onClick(() => this.onExport());
      Text(`删除(${this.selectedCount})`).fontSize(15)
        .fontColor(this.selectedCount > 0 ? $r('app.color.color_error') : $r('app.color.color_text_hint'))
        .onClick(() => this.onDelete());
    }
    .width('100%').padding({ left: 16, right: 16, top: 12,
      bottom: shouldUseSystemMaterialPath(this.immersiveLightEnabled) ? this.navBarHeight + 72 : this.navBarHeight + 64 })
    .backgroundBlurStyle(resolveBlurStyle('bar')!).backgroundColor($r('app.color.color_bg_glass'));
  }
}
