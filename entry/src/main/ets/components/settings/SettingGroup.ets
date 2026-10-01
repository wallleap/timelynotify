import { resolveBlurStyle } from '../../utils/ImmersiveUtil';

/** 设置卡片容器：只提供现有毛玻璃背景与圆角，内部结构由调用方决定。 */
@Component
export struct SettingGroup {
  // 调用方通过尾随闭包自行排列 Cell 与 Divider。
  @BuilderParam content: () => void;

  build() {
    Column({ space: 0 }) {
      this.content();
    }
    .width('100%')
    .backgroundBlurStyle(resolveBlurStyle('bar')!)
    .backgroundColor($r('app.color.color_bg_surface_glass'))
    .borderRadius(12);
  }
}
