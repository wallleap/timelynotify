import { promptAction, UIContext } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { ThemeService } from '../../services/ThemeService';
import showToast from '../showToast';
import { resolveBlurStyle, KEY_IMMERSIVE_LIGHT_ENABLED, getDialogMaterial } from '../../utils/ImmersiveUtil';

/**
 * 「外观」板块（仅 API 26+ 显示）：沉浸光感入口行。
 * 点击弹居中确认对话框（效果说明 + 重启确认合并为一级）。
 * 不原地写 AppStorage：Index.build 依赖该值选择 HdsTabs/Tabs 分支，原地切换会导致
 * Tabs 整体重建、Tab 落回通知页（bug）；重启后由 EntryAbility.onCreate 读盘写入，天然规避。
 */
@Component
export struct AppearanceSection {
  // 沉浸光感开关值（API 26+ 生效；EntryAbility 启动时从 Preferences 写入 AppStorage）：
  // 入口行状态文本与各页面渲染分支均读此权威值；切换走 Dialog → 重启确认 → 重启应用生效
  @StorageProp(KEY_IMMERSIVE_LIGHT_ENABLED) immersiveLightEnabled: boolean = true;

  @Builder
  arrowRightIcon() {
    Image($r('app.media.arrow_right'))
      .width(20)
      .height(20)
      .objectFit(ImageFit.Contain)
      .fillColor($r('app.color.color_text_hint'))
      .draggable(false);
  }

  build() {
    Column({ space: 8 }) {
      Text('外观')
        .fontSize(12)
        .fontColor($r('app.color.color_text_hint'))
        .width('100%')
        .padding({ left: 12 });

      // 沉浸光感入口卡片：与「服务器」等入口行风格一致，右侧展示当前状态 + 箭头；
      // 说明文字放在点击后的 Dialog 标题中，卡片本身仅保留标题与状态
      Row({ space: 14 }) {
        Text('沉浸光感')
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.color_text_primary'))
          .layoutWeight(1);

        Row() {
          Text(this.immersiveLightEnabled ? '已开启' : '已关闭')
            .fontSize(12)
            .fontColor(this.immersiveLightEnabled ? $r('app.color.color_brand') :
              $r('app.color.color_text_hint'));
          this.arrowRightIcon();
        }
      }
      .width('100%')
      .padding(16)
      .backgroundBlurStyle(resolveBlurStyle('bar')!)
      .backgroundColor($r('app.color.color_bg_surface_glass'))
      .borderRadius(12)
      .onClick(() => {
        this.onImmersiveRowClick();
      });
    }.width('100%');
  }

  // 沉浸光感入口行点击：直接弹居中确认对话框（效果说明 + 重启确认合并为一级）。
  private onImmersiveRowClick(): void {
    const uiCtx: UIContext = this.getUIContext();
    // 目标状态（当前状态的反向）与对应文案
    const enable: boolean = !this.immersiveLightEnabled;
    const title: string = enable ? '开启沉浸光感' : '关闭沉浸光感';
    const message: string = enable
      ? '开启后界面将呈现沉浸光感材质。设置需重启应用后生效，是否立即重启？'
      : '关闭后界面将回退为毛玻璃效果。设置需重启应用后生效，是否立即重启？';
    const buttons: promptAction.Button[] = [{ text: '取消', color: $r('app.color.color_text_tertiary') },
      { text: '立即重启', color: $r('app.color.color_brand') },];
    uiCtx.getPromptAction().showDialog({
      title: title,
      message: message,
      buttons: buttons,
      // 读取当前生效态（重启前不变）：启用沉浸光感时确认框同样为材质背板
      systemMaterial: getDialogMaterial(),
    }, (err: BusinessError, result: promptAction.ShowDialogSuccessResponse) => {
      if (err || result.index !== 1) {
        // 取消/关闭：无操作（入口行状态始终反映权威值，无需还原）
        return;
      }
      // 确认：持久化偏好 → 重启应用（新实例 EntryAbility.onCreate 读盘写入 AppStorage，全页面按新偏好渲染）
      ThemeService.setImmersiveLightEnabled(enable).then((ok: boolean) => {
        if (ok) {
          ThemeService.restartApp(uiCtx);
        } else {
          showToast(this.getUIContext(), '保存失败，设置未生效', 2000);
        }
      });
    });
  }
}
