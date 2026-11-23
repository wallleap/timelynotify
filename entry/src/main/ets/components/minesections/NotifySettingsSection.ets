import { hilog } from '@kit.PerformanceAnalysisKit';
import { promptAction, UIContext } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { PreferencesUtil } from '../../utils/PreferencesUtil';
import { NotifyExportService } from '../../services/NotifyExportService';
import { ThemeService } from '../../services/ThemeService';
import showToast from '../showToast';
import { getDialogMaterial } from '../../utils/ImmersiveUtil';
import { DOMAIN } from '../../common/Constant';
import { SettingGroup } from '../settings/SettingGroup';
import { SettingCell } from '../settings/SettingCell';
import { SettingArrow } from '../settings/SettingArrow';

const TAG: string = 'NotifySettingsSec';

/**
 * 「通知设置」板块：应用内订阅开关、导出通知与个性化设置。
 * 全自治：自身管理 notifyEnabled/exporting 状态，业务下沉到各 Service。
 */
@Component
export struct NotifySettingsSection {
  // 应用内订阅通知偏好；系统通知权限由 MineView 顶部卡片单独管理。
  @State notifyEnabled: boolean = false;
  // 是否正在执行通知导出（读取本地缓存 + 保存全程置 true，防止重复触发）
  @State exporting: boolean = false;

  aboutToAppear() {
    this.refreshNotifyEnabled();
  }

  build() {
    Column({ space: 12 }) {
      SettingGroup() {
        // 开启应用订阅通知（开关）
        SettingCell({
          title: $r('app.string.mine_notifyset_enable_title'),
          description: this.notifyEnabled ? $r('app.string.mine_notifyset_enabled') : $r('app.string.mine_notifyset_disabled'),
          icon: $r('app.media.bell_dot'),
          descriptionColor: this.notifyEnabled ? $r('app.color.color_brand') : $r('app.color.color_text_hint')
        }) {
          Toggle({ type: ToggleType.Switch, isOn: this.notifyEnabled })
            .selectedColor($r('app.color.color_brand'))
            .onChange((isOn: boolean) => {
              this.onNotifyToggle(isOn);
            });
        }
      }

      // 独立的导出通知卡片（导出所有来源的本地未过期通知为 txt 文件，内容为 JSON 数组）
      SettingGroup() {
        SettingCell({
          title: $r('app.string.mine_notifyset_export_title'),
          icon: $r('app.media.book_up'),
          description: this.exporting ? $r('app.string.mine_notifyset_exporting') : $r('app.string.mine_notifyset_export_desc'),
          clickable: true,
          onActivate: () => this.exportMessages()
        }) {
          // 导出中显示加载指示器，否则显示箭头。
          if (this.exporting) {
            LoadingProgress().width(24).height(24).color($r('app.color.color_brand'));
          } else {
            SettingArrow();
          }
        }
      }

      // 个性化设置入口紧随导出卡片；可用设置项随系统能力变化。
      SettingGroup() {
        SettingCell({
          title: $r('app.string.mine_notifyset_personalization'),
          icon: $r('app.media.paintbrush_vertical'),
          description: $r('app.string.mine_notifyset_personalization_desc'),
          clickable: true,
          onActivate: () => this.openPersonalizationSettings()
        }) {
          SettingArrow();
        }
      }
    }
    .width('100%');
  }

  // 进入个性化设置页；沉浸光感入口由页面按系统能力决定是否显示。
  private async openPersonalizationSettings(): Promise<void> {
    const uiCtx: UIContext = this.getUIContext();
    try {
      await uiCtx.getRouter().pushUrl({ url: 'pages/PersonalizationSettings' });
    } catch (err) {
      const message: string = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, TAG, '跳转个性化设置失败：%{public}s', message);
      showToast(uiCtx, $r('app.string.mine_notifyset_open_personal_failed'));
    }
  }

  // 读取持久化的订阅通知开关状态（纯本地存储，不调系统 API）
  private async refreshNotifyEnabled(): Promise<void> {
    const v: string = await PreferencesUtil.getString(null, PreferencesUtil.KEY_NOTIFY_ENABLED, '');
    this.notifyEnabled = v === 'true';
  }

  // 开关切换：弹应用内确认对话框（仅为合规提示，不调系统 API）
  // 真正的通知开关由 MineView 顶部权限卡片控制系统层
  //
  // 判断逻辑：Toggle.onChange 可能在两种场景被触发——
  //   1. 用户点击：传入的 isOn 与当前 this.notifyEnabled 相反（Toggle 翻转）
  //   2. 程序化赋值：传入的 isOn 与当前 this.notifyEnabled 相同（Toggle 同步到已有值）
  // 只有场景 1 才需要弹窗，场景 2 直接跳过
  private onNotifyToggle(isOn: boolean): void {
    if (isOn === this.notifyEnabled) {
      return;
    }
    const uiCtx: UIContext = this.getUIContext();
    const onButtons: promptAction.Button[] = [{ text: $r('app.string.mine_notifyset_reject'), color: $r('app.color.color_text_tertiary') },
      { text: $r('app.string.mine_notifyset_accept'), color: $r('app.color.color_brand') },];
    const offButtons: promptAction.Button[] = [{ text: $r('app.string.mine_notifyset_keep'), color: $r('app.color.color_text_tertiary') },
      { text: $r('app.string.mine_notifyset_stop'), color: $r('app.color.color_brand') },];
    uiCtx.getPromptAction().showDialog({
      title: isOn ? $r('app.string.mine_notifyset_sub_on') : $r('app.string.mine_notifyset_sub_off'),
      message: isOn ? $r('app.string.mine_notifyset_sub_on_msg') : $r('app.string.mine_notifyset_sub_off_msg'),
      buttons: isOn ? onButtons : offButtons,
      // API 26+ 且开关开启时系统确认框走统一的 THICK 沉浸材质，旧系统缺省纯色
      systemMaterial: getDialogMaterial(),
    }, (err: BusinessError, result: promptAction.ShowDialogSuccessResponse) => {
      if (err) {
        hilog.warn(DOMAIN, TAG, 'showDialog 失败：%{public}s', err.message); // 弹窗异常关闭，Toggle 需回滚到实际状态
        this.notifyEnabled = isOn;
        this.notifyEnabled = !isOn;
        return;
      }
      if (result.index === 1) { // 确认：写盘 + 翻转本地状态（纯 UI 层；系统通知权限由 MineView 顶部卡片控制）
        this.notifyEnabled = isOn;
        PreferencesUtil.putString(null, PreferencesUtil.KEY_NOTIFY_ENABLED, isOn ? 'true' : 'false');
        return;
      } // 取消/拒绝：notifyEnabled 未变化，Toggle 不会自动回滚，需强制同步
      // 先设为点击值（匹配 Toggle 当前视觉），再还原实际值触发重渲染
      this.notifyEnabled = isOn;
      this.notifyEnabled = !isOn;
    });
  }

  // 导出所有来源的本地通知：调 NotifyExportService.exportAll（读取 + 保存 + 写文件）
  // 成功后展示条数；失败透出原因
  private async exportMessages(): Promise<void> {
    if (this.exporting) {
      return; // 防重复触发
    }
    const uiCtx: UIContext = this.getUIContext();
    const ctx: common.UIAbilityContext | null = ThemeService.getAbilityContext(uiCtx);
    if (!ctx) {
      showToast(uiCtx, $r('app.string.mine_notifyset_ctx_failed'));
      return;
    }
    this.exporting = true;
    try {
      const result = await NotifyExportService.exportAll(ctx);
      if (result.cancelled) {
        return; // 用户取消保存，静默结束
      }
      if (!result.ok) {
        showToast(uiCtx, result.errorMsg.length > 0 ? result.errorMsg : $r('app.string.mine_notifyset_export_failed'));
        return;
      }
      showToast(uiCtx, $r('app.string.mine_notifyset_exported', result.count), 1500);
    } finally {
      this.exporting = false;
    }
  }
}
