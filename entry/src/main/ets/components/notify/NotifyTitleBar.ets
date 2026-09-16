import { resolveBlurStyle } from '../../utils/ImmersiveUtil';

/** 通知页标题栏；页面通过回调接管服务器设置、多选和删除操作。 */
@Component
export struct NotifyTitleBar {
  @Prop title: string = '';
  @Prop isEditing: boolean = false;
  @Prop statusBarHeight: number = 0;
  @Prop useHdsLayout: boolean = false;
  onOpenSettings: () => void = () => {};
  onToggleSelection: () => void = () => {};
  onDelete: () => void = () => {};

  @Builder
  private selectionPill() {
    Row() {
      Text(this.isEditing ? '取消' : '多选').fontSize(16).fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.color_text_primary'));
    }
    .height(38).padding({ left: 14, right: 14 }).borderRadius(38).alignItems(VerticalAlign.Center)
    .border({ width: 1, color: $r('app.color.color_border_glass') }).backgroundBlurStyle(resolveBlurStyle('card')!)
    .backgroundColor($r('app.color.color_bg_glass_control')).onClick(() => this.onToggleSelection());
  }

  @Builder
  private deletePill() {
    Row() {
      Image($r('app.media.delete')).width(24).height(24).objectFit(ImageFit.Contain).draggable(false)
        .fillColor($r('app.color.color_text_primary'));
    }
    .height(38).width(38).borderRadius(38).justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center)
    .border({ width: 1, color: $r('app.color.color_border_glass') }).backgroundBlurStyle(resolveBlurStyle('card')!)
    .backgroundColor($r('app.color.color_bg_glass_control')).onClick(() => this.onDelete());
  }

  @Builder
  private titleContent(reserveMenuSpace: boolean) {
    Row({ space: 8 }) {
      Row({ space: 2 }) {
        Text(this.title).fontSize(24).fontColor($r('app.color.color_text_primary')).fontWeight(FontWeight.Bold)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).flexShrink(1)
          .onClick(() => this.onOpenSettings());
        Image($r('app.media.select_more')).width(24).height(24).objectFit(ImageFit.Contain).draggable(false)
          .fillColor($r('app.color.color_text_primary')).flexShrink(0).onClick(() => this.onOpenSettings());
      }
      .layoutWeight(1).width(0).alignItems(VerticalAlign.Center).onClick(() => this.onOpenSettings())
      .hitTestBehavior(reserveMenuSpace ? HitTestMode.None : HitTestMode.Default);
      if (reserveMenuSpace) {
        Row().width(116).height(1).hitTestBehavior(HitTestMode.None);
      }
    }
    .width('100%').alignItems(VerticalAlign.Center);
  }

  build() {
    if (this.useHdsLayout) {
      Row() { this.titleContent(true); }
        .width('100%').padding({ left: 16, right: 16, top: 16, bottom: 16 });
    } else {
      Row({ space: 8 }) {
        Row() { this.titleContent(false); }
          .layoutWeight(1).width(0).padding({ right: 48 }).alignItems(VerticalAlign.Center);
        this.selectionPill();
        this.deletePill();
      }
      .width('100%').padding({ left: 16, right: 16, top: 16 + this.statusBarHeight, bottom: 16 })
      .alignItems(VerticalAlign.Center).backgroundBlurStyle(resolveBlurStyle('bar')!)
      .backgroundColor($r('app.color.color_bg_glass'));
    }
  }
}
