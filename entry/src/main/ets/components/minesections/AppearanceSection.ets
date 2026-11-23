import { promptAction, UIContext } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { ThemeService } from '../../services/ThemeService';
import showToast from '../showToast';
import { KEY_IMMERSIVE_LIGHT_ENABLED, getDialogMaterial } from '../../utils/ImmersiveUtil';
import { SettingGroup } from '../settings/SettingGroup';
import { SettingCell } from '../settings/SettingCell';
import { SettingArrow } from '../settings/SettingArrow';

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

  build() {
    // 由“个性化设置”页面承载；卡片本身仅保留标题与当前状态。
    SettingGroup() {
      SettingCell({ title: $r('app.string.mine_appear_immersive'), clickable: true, onActivate: () => this.onImmersiveRowClick() }) {
        Row() {
          Text(this.immersiveLightEnabled ? $r('app.string.mine_appear_enabled') : $r('app.string.mine_appear_disabled'))
            .fontSize(12)
            .fontColor(this.immersiveLightEnabled ? $r('app.color.color_brand') :
              $r('app.color.color_text_hint'));
          SettingArrow();
        }
      }
    }
  }

  // 沉浸光感入口行点击：直接弹居中确认对话框（效果说明 + 重启确认合并为一级）。
  private onImmersiveRowClick(): void {
    const uiCtx: UIContext = this.getUIContext();
    // 目标状态（当前状态的反向）与对应文案
    const enable: boolean = !this.immersiveLightEnabled;
    const title: ResourceStr = enable ? $r('app.string.mine_appear_enable_title') : $r('app.string.mine_appear_disable_title');
    const message: ResourceStr = enable
      ? $r('app.string.mine_appear_enable_msg')
      : $r('app.string.mine_appear_disable_msg');
    const buttons: promptAction.Button[] = [{ text: $r('app.string.common_cancel'), color: $r('app.color.color_text_tertiary') },
      { text: $r('app.string.mine_appear_restart_now'), color: $r('app.color.color_brand') },];
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
          showToast(this.getUIContext(), $r('app.string.mine_appear_save_failed'), 2000);
        }
      });
    });
  }
}
