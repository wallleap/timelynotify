import { hilog } from '@kit.PerformanceAnalysisKit';
import { promptAction, UIContext } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { notificationManager } from '@kit.NotificationKit';
import { common } from '@kit.AbilityKit';
import { PreferencesUtil } from '../../utils/PreferencesUtil';
import { NotifyExportService } from '../../services/NotifyExportService';
import { ThemeService } from '../../services/ThemeService';
import showToast from '../showToast';
import { resolveBlurStyle, getDialogMaterial } from '../../utils/ImmersiveUtil';
import { DOMAIN } from '../../common/Constant';

const TAG: string = 'NotifySettingsSec';

/**
 * 「通知设置」板块：开启订阅通知开关和通知权限设置共用卡片，导出通知独立成卡片。
 * 全自治：自身管理 notifyEnabled/exporting 状态，业务下沉到各 Service。
 */
@Component
export struct NotifySettingsSection {
  // 通知授权开关状态（系统级，应用无法直接关闭，只能引导用户去系统设置）
  @State notifyEnabled: boolean = false;
  // 是否正在执行通知导出（读取本地缓存 + 保存全程置 true，防止重复触发）
  @State exporting: boolean = false;

  aboutToAppear() {
    this.refreshNotifyEnabled();
  }

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
    Column({ space: 16 }) {
      Column({ space: 0 }) {
        // 开启应用订阅通知（开关）
        Row() {
          Column({ space: 4 }) {
            Text('开启应用订阅通知')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.color_text_primary'));
            Text(this.notifyEnabled ? '已开启' : '已关闭')
              .fontSize(12)
              .fontColor(
                this.notifyEnabled ? $r('app.color.color_brand') : $r('app.color.color_text_hint'));
          }.alignItems(HorizontalAlign.Start).layoutWeight(1);

          Toggle({ type: ToggleType.Switch, isOn: this.notifyEnabled })
            .selectedColor($r('app.color.color_brand'))
            .onChange((isOn: boolean) => {
              this.onNotifyToggle(isOn);
            });
        }.width('100%').padding(16);

        Divider().color($r('app.color.color_border_subtle')).strokeWidth(1).margin({ left: 16, right: 16 });

        // 通知权限设置（点击拉起系统通知管理）
        Row() {
          Text('通知权限设置')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.color_text_primary'))
            .layoutWeight(1);

          this.arrowRightIcon();
        }.width('100%').padding(16).onClick(() => {
          this.openNotifySettings();
        });
      }
      .width('100%')
      .backgroundBlurStyle(resolveBlurStyle('bar')!)
      .backgroundColor($r('app.color.color_bg_surface_glass'))
      .borderRadius(12);

      // 独立的导出通知卡片（导出当前服务器本地保存的全部通知为 txt 文件，内容为 JSON 数组）
      Row() {
        Column({ space: 4 }) {
          Text('导出通知')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.color_text_primary'));
          Text(this.exporting ? '正在导出…' : '导出当前服务器本地保存的全部通知')
            .fontSize(12)
            .fontColor($r('app.color.color_text_hint'));
        }.alignItems(HorizontalAlign.Start).layoutWeight(1);

        // 导出中显示加载指示器，否则显示箭头
        if (this.exporting) {
          LoadingProgress()
            .width(24)
            .height(24)
            .color($r('app.color.color_brand'));
        } else {
          this.arrowRightIcon();
        }
      }
      .width('100%')
      .padding(16)
      .backgroundBlurStyle(resolveBlurStyle('bar')!)
      .backgroundColor($r('app.color.color_bg_surface_glass'))
      .borderRadius(12)
      .onClick(() => {
        this.exportMessages();
      });

      // 个性化设置入口紧随导出卡片，主题、通知重发与沉浸光感偏好集中在独立页面中管理。
      Row() {
        Column({ space: 4 }) {
          Text('个性化设置')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.color_text_primary'));
          Text('主题模式、加密通知重发、沉浸光感')
            .fontSize(12)
            .fontColor($r('app.color.color_text_hint'));
        }.alignItems(HorizontalAlign.Start).layoutWeight(1);

        this.arrowRightIcon();
      }
      .width('100%')
      .padding(16)
      .backgroundBlurStyle(resolveBlurStyle('bar')!)
      .backgroundColor($r('app.color.color_bg_surface_glass'))
      .borderRadius(12)
      .onClick(() => {
        this.openPersonalizationSettings();
      });
    }
    .width('100%');
  }

  // 进入个性化设置页：主题模式、加密通知重发、沉浸光感等偏好集中管理。
  private async openPersonalizationSettings(): Promise<void> {
    const uiCtx: UIContext = this.getUIContext();
    try {
      await uiCtx.getRouter().pushUrl({ url: 'pages/PersonalizationSettings' });
    } catch (err) {
      const message: string = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, TAG, '跳转个性化设置失败：%{public}s', message);
      showToast(uiCtx, '无法打开个性化设置');
    }
  }

  // 读取持久化的订阅通知开关状态（纯本地存储，不调系统 API）
  private async refreshNotifyEnabled(): Promise<void> {
    const v: string = await PreferencesUtil.getString(null, PreferencesUtil.KEY_NOTIFY_ENABLED, '');
    this.notifyEnabled = v === 'true';
  }

  // 开关切换：弹应用内确认对话框（仅为合规提示，不调系统 API）
  // 真正的通知开关由【通知权限设置】入口控制系统层
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
    const onButtons: promptAction.Button[] = [{ text: '残忍拒绝', color: $r('app.color.color_text_tertiary') },
      { text: '接受推送', color: $r('app.color.color_brand') },];
    const offButtons: promptAction.Button[] = [{ text: '保持推送', color: $r('app.color.color_text_tertiary') },
      { text: '取消推送', color: $r('app.color.color_brand') },];
    uiCtx.getPromptAction().showDialog({
      title: isOn ? '开启订阅' : '关闭订阅',
      message: isOn ? '是否要接收此订阅的通知栏推送？' : '是否要取消此订阅的通知栏推送？',
      buttons: isOn ? onButtons : offButtons,
      // API 26+ 材质就绪时系统确认框走 REGULAR 沉浸材质，旧系统缺省纯色
      systemMaterial: getDialogMaterial(),
    }, (err: BusinessError, result: promptAction.ShowDialogSuccessResponse) => {
      if (err) {
        hilog.warn(DOMAIN, TAG, 'showDialog 失败：%{public}s', err.message); // 弹窗异常关闭，Toggle 需回滚到实际状态
        this.notifyEnabled = isOn;
        this.notifyEnabled = !isOn;
        return;
      }
      if (result.index === 1) { // 确认：写盘 + 翻转本地状态（纯 UI 层；系统通知权限由【通知权限设置】入口控制）
        this.notifyEnabled = isOn;
        PreferencesUtil.putString(null, PreferencesUtil.KEY_NOTIFY_ENABLED, isOn ? 'true' : 'false');
        return;
      } // 取消/拒绝：notifyEnabled 未变化，Toggle 不会自动回滚，需强制同步
      // 先设为点击值（匹配 Toggle 当前视觉），再还原实际值触发重渲染
      this.notifyEnabled = isOn;
      this.notifyEnabled = !isOn;
    });
  }

  // 拉起系统应用通知设置页（用户可在其中真正开启/关闭通知）
  private async openNotifySettings(): Promise<void> {
    const ctx: common.UIAbilityContext | null = ThemeService.getAbilityContext(this.getUIContext());
    if (!ctx) {
      showToast(this.getUIContext(), '上下文获取失败');
      return;
    }
    try {
      await notificationManager.openNotificationSettings(ctx);
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'openNotificationSettings 失败：code=%{public}d msg=%{public}s', e.code, e.message);
      showToast(this.getUIContext(), '无法打开通知设置');
    }
  }

  // 导出当前服务器全部本地通知：调 NotifyExportService.exportAll（读取 + 保存 + 写文件）
  // 成功后展示条数；失败透出原因
  private async exportMessages(): Promise<void> {
    if (this.exporting) {
      return; // 防重复触发
    }
    const uiCtx: UIContext = this.getUIContext();
    const ctx: common.UIAbilityContext | null = ThemeService.getAbilityContext(uiCtx);
    if (!ctx) {
      showToast(uiCtx, '上下文获取失败');
      return;
    }
    this.exporting = true;
    try {
      const result = await NotifyExportService.exportAll(ctx);
      if (result.cancelled) {
        return; // 用户取消保存，静默结束
      }
      if (!result.ok) {
        showToast(uiCtx, result.errorMsg.length > 0 ? result.errorMsg : '导出失败');
        return;
      }
      showToast(uiCtx, `已导出 ${result.count} 条通知`, 1500);
    } finally {
      this.exporting = false;
    }
  }
}
