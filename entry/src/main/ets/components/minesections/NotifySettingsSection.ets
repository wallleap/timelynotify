import { hilog } from '@kit.PerformanceAnalysisKit';
import { promptAction, UIContext } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { notificationManager } from '@kit.NotificationKit';
import { common } from '@kit.AbilityKit';
import { PreferencesUtil } from '../../utils/PreferencesUtil';
import { NotifyMessageService } from '../../services/NotifyMessageService';
import { NotifyExportService } from '../../services/NotifyExportService';
import { ThemeService } from '../../services/ThemeService';
import showToast from '../showToast';
import { resolveBlurStyle } from '../../utils/ImmersiveUtil';
import { DOMAIN } from '../../common/Constant';

const TAG: string = 'NotifySettingsSec';

/**
 * 「通知设置」板块：开启订阅通知开关 + 通知权限设置 + 测试通知 + 导出消息。
 * 全自治：自身管理 notifyEnabled/testingPush/exporting 状态，业务下沉到各 Service。
 */
@Component
export struct NotifySettingsSection {
  // 通知授权开关状态（系统级，应用无法直接关闭，只能引导用户去系统设置）
  @State notifyEnabled: boolean = false;
  // 是否正在发送测试通知（请求期间置 true，防止重复触发）
  @State testingPush: boolean = false;
  // 是否正在执行消息导出（拉取 + 保存全程置 true，防止重复触发）
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
      .fillColor($r('app.color.text_quinary_color'));
  }

  build() {
    Column({ space: 0 }) {
      // 开启应用订阅通知（开关）
      Row() {
        Column({ space: 2 }) {
          Text('开启应用订阅通知')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary_color'));
          Text(this.notifyEnabled ? '已开启' : '已关闭')
            .fontSize(12)
            .fontColor(
              this.notifyEnabled ? $r('app.color.text_accent_color') : $r('app.color.text_quinary_color'));
        }.alignItems(HorizontalAlign.Start).layoutWeight(1);

        Toggle({ type: ToggleType.Switch, isOn: this.notifyEnabled })
          .selectedColor($r('app.color.text_accent_color'))
          .onChange((isOn: boolean) => {
            this.onNotifyToggle(isOn);
          });
      }.width('100%').padding(16);

      Divider().color($r('app.color.divider_color')).strokeWidth(1).margin({ left: 16, right: 16 });

      // 通知权限设置（点击拉起系统通知管理）
      Row() {
        Text('通知权限设置')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary_color'))
          .layoutWeight(1);

        this.arrowRightIcon();
      }.width('100%').padding(16).onClick(() => {
        this.openNotifySettings();
      });

      Divider().color($r('app.color.divider_color')).strokeWidth(1).margin({ left: 16, right: 16 });

      // 测试通知行（点击向当前服务器 POST /push 发送一条测试推送，验证通知链路）
      Row() {
        Column({ space: 2 }) {
          Text('测试通知')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary_color'));
          Text(this.testingPush ? '正在发送…' : '发送一条测试推送验证通知链路')
            .fontSize(12)
            .fontColor($r('app.color.text_quinary_color'));
        }.alignItems(HorizontalAlign.Start).layoutWeight(1);

        // 发送中显示加载指示器，否则显示箭头
        if (this.testingPush) {
          LoadingProgress()
            .width(24)
            .height(24)
            .color($r('app.color.text_accent_color'));
        } else {
          this.arrowRightIcon();
        }
      }.width('100%').padding(16).onClick(() => {
        this.sendTestNotification();
      });

      Divider().color($r('app.color.divider_color')).strokeWidth(1).margin({ left: 16, right: 16 });

      // 导出消息行（点击导出当前设备全部消息为 txt 文件，内容为 JSON 数组）
      Row() {
        Column({ space: 2 }) {
          Text('导出消息')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary_color'));
          Text(this.exporting ? '正在导出…' : '导出当前设备全部消息为 txt 文件')
            .fontSize(12)
            .fontColor($r('app.color.text_quinary_color'));
        }.alignItems(HorizontalAlign.Start).layoutWeight(1);

        // 导出中显示加载指示器，否则显示箭头
        if (this.exporting) {
          LoadingProgress()
            .width(24)
            .height(24)
            .color($r('app.color.text_accent_color'));
        } else {
          this.arrowRightIcon();
        }
      }.width('100%').padding(16).onClick(() => {
        this.exportMessages();
      });
    }
    .width('100%')
    .backgroundBlurStyle(resolveBlurStyle('bar')!)
    .backgroundColor($r('app.color.card_glass_background'))
    .borderRadius(12);
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
    const onButtons: promptAction.Button[] = [{ text: '残忍拒绝', color: $r('app.color.text_tertiary_color') },
      { text: '接受推送', color: $r('app.color.text_accent_color') },];
    const offButtons: promptAction.Button[] = [{ text: '保持推送', color: $r('app.color.text_tertiary_color') },
      { text: '取消推送', color: $r('app.color.text_accent_color') },];
    uiCtx.getPromptAction().showDialog({
      title: isOn ? '开启订阅' : '关闭订阅',
      message: isOn ? '是否要接收此订阅的通知栏推送？' : '是否要取消此订阅的通知栏推送？',
      buttons: isOn ? onButtons : offButtons,
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

  // 发送测试通知：调 NotifyMessageService.sendTestPush 向当前服务器 POST /push
  // 成功后提示用户查看通知栏；失败透出服务端/网络错误原因
  private async sendTestNotification(): Promise<void> {
    if (this.testingPush) {
      return; // 防重复触发
    }
    const uiCtx: UIContext = this.getUIContext();
    this.testingPush = true;
    try {
      const failMsg: string = await NotifyMessageService.getInstance().sendTestPush(null);
      if (failMsg.length > 0) {
        showToast(uiCtx, failMsg, 3000);
        return;
      }
      showToast(uiCtx, '测试通知已发送，请查看通知栏', 2000);
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, TAG, '发送测试通知失败：%{public}s', msg);
      showToast(uiCtx, '发送失败，请点击下方[反馈问题]', 5000);
    } finally {
      this.testingPush = false;
    }
  }

  // 导出当前设备全部消息：调 NotifyExportService.exportAll（拉取 + 保存 + 写文件一体化）
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
      // 成功提示；流被截断时额外说明数据可能不完整
      if (result.truncated) {
        showToast(uiCtx, `导出完成（流中断，可能不完整），共 ${result.count} 条`, 3000);
      } else {
        showToast(uiCtx, `已导出 ${result.count} 条消息`, 1500);
      }
    } finally {
      this.exporting = false;
    }
  }
}
