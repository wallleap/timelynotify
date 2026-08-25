import { hilog } from '@kit.PerformanceAnalysisKit';
import { promptAction, UIContext } from '@kit.ArkUI';
import { BusinessError, pasteboard } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { notificationManager } from '@kit.NotificationKit';
import { ServerEntry } from '../model/ServerEntry';
import { ServerManager } from '../services/ServerManager';
import { extractHost } from '../components/ServerSettingsContent';
import { ClientTokenDialog } from '../components/ClientTokenDialog';
import { NotifyMessageService } from '../services/NotifyMessageService';
import { DeviceRegisterService } from '../services/DeviceRegisterService';
import { PreferencesUtil } from '../utils/PreferencesUtil';

const DOMAIN: number = 0x0000;
const TAG: string = 'MineView';

function showToast(ctx: UIContext, message: string, durationMs: number = 1500): void {
  try {
    ctx.getPromptAction().showToast({ message: message, duration: durationMs });
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    hilog.warn(DOMAIN, TAG, 'Toast 调用失败：%{public}s', msg);
  }
}

// 我的页 - 展示个人设置入口
@Component
export struct MineView {
  @State hostDisplay: string = '';
  @State serverName: string = '';
  @State serverCount: number = 0;
  // 用户自定义的 token 原文（持久化层内容）；内置默认时空串
  @State customClientToken: string = '';
  // 是否正在使用内置默认 token
  @State isDefaultClientToken: boolean = true;
  // 推送 Token（Push 下发的 device_token；卡片展示用，点击复制完整明文）
  @State deviceTokenDisplay: string = '';
  // 通知授权开关状态（系统级，应用无法直接关闭，只能引导用户去系统设置）
  @State notifyEnabled: boolean = false;
  private onChange: ((list: ServerEntry[], curId: string) => void) | null = null;
  // client token 弹窗（打开时回填用户自定义内容；内置默认时显示空 placeholder，用户填即覆盖）
  private tokenDialogController: CustomDialogController = new CustomDialogController({
    builder: ClientTokenDialog({
      getInitToken: (): string => this.customClientToken,
      onSaved: (): void => {
        this.refreshClientToken();
      },
    }),
    alignment: DialogAlignment.Center,
    autoCancel: true,
    offset: { dx: 0, dy: 0 },
  });

  aboutToAppear() {
    this.refreshSummary();
    this.refreshClientToken();
    this.refreshDeviceToken();
    this.refreshNotifyEnabled();
    this.onChange = (_list: ServerEntry[], _curId: string): void => {
      this.refreshSummary();
    };
    ServerManager.getInstance().addChangeListener(this.onChange);
  }

  aboutToDisappear() {
    if (this.onChange) {
      ServerManager.getInstance().removeChangeListener(this.onChange);
    }
  }

  build() {
    Column() {
      // 顶部标题栏
      Row() {
        Text('我的')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .width('100%')
          .textAlign(TextAlign.Center);
      }
      .width('100%')
      .padding(16)
      .backgroundColor($r('app.color.index_page_top_background'));

      Column({ space: 12 }) {
        // 通知设置卡片
        Column({ space: 0 }) {
          // 开启应用订阅通知（开关）
          Row() {
            Column({ space: 2 }) {
              Text('开启应用订阅通知')
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor('#111111');
              Text(this.notifyEnabled ? '已开启' : '已关闭')
                .fontSize(12)
                .fontColor(this.notifyEnabled ? '#FF6F22' : '#999999');
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1);

            Toggle({ type: ToggleType.Switch, isOn: this.notifyEnabled })
              .selectedColor('#FF6F22')
              .onChange((isOn: boolean) => {
                this.onNotifyToggle(isOn);
              });
          }
          .width('100%')
          .padding(16);

          Divider().color('#F0F0F0').strokeWidth(1).margin({ left: 16, right: 16 });

          // 通知权限设置（点击拉起系统通知管理）
          Row() {
            Text('通知权限设置')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor('#111111')
              .layoutWeight(1);

            Image($r('app.media.arrow_right'))
              .width(24)
              .height(24)
              .objectFit(ImageFit.Contain)
              .fillColor('#999999');
          }
          .width('100%')
          .padding(16)
          .onClick(() => {
            this.openNotifySettings();
          });
        }
        .width('100%')
        .backgroundColor('#FFFFFF')
        .borderRadius(12);

        // 服务器入口卡片
        Row({ space: 14 }) {
          Column({ space: 4 }) {
            Row() {
              Text('服务器')
                .fontSize(17)
                .fontWeight(FontWeight.Medium)
                .fontColor('#111111');
              Blank();
              Text(`共 ${this.serverCount} 个`)
                .fontSize(12)
                .fontColor('#999999');
            }
            .width('100%');

            Text(this.serverName)
              .fontSize(14)
              .fontColor('#666666')
              .width('100%')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis });

            Text(this.hostDisplay)
              .fontSize(12)
              .fontColor('#FF6F22')
              .width('100%')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis });
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1);

          Image($r('app.media.arrow_right'))
            .width(32)
            .height(32)
            .objectFit(ImageFit.Contain)
            .fillColor($r('app.color.text_primary_color'))
            .padding(4)
        }
        .width('100%')
        .padding(16)
        .backgroundColor('#FFFFFF')
        .borderRadius(12)
        .onClick(() => {
          this.handleCardClicked();
        });

        // 客户端 Token 卡片
        Row({ space: 14 }) {
          Column({ space: 4 }) {
            Text('客户端 Token')
              .fontSize(17)
              .fontWeight(FontWeight.Medium)
              .fontColor('#111111')
              .width('100%');

            Text(this.buildClientTokenDisplay())
              .fontSize(14)
              .fontColor(this.isDefaultClientToken ? '#FF6F22' : '#666666')
              .width('100%')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis });
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1);

          Image($r('app.media.arrow_right'))
            .width(32)
            .height(32)
            .objectFit(ImageFit.Contain)
            .fillColor($r('app.color.text_primary_color'))
            .padding(4)
        }
        .width('100%')
        .padding(16)
        .backgroundColor('#FFFFFF')
        .borderRadius(12)
        .onClick(() => {
          this.openTokenDialog();
        });

        // 推送 Token 卡片（Device Token）；点击整行复制完整明文到剪贴板
        Row({ space: 14 }) {
          Column({ space: 4 }) {
            Row() {
              Text('推送 Token')
                .fontSize(17)
                .fontWeight(FontWeight.Medium)
                .fontColor('#111111');
              Blank();
              Text('点击复制')
                .fontSize(12)
                .fontColor('#FF6F22');
            }
            .width('100%');

            Text(this.buildDeviceTokenDisplay())
              .fontSize(14)
              .fontColor(this.deviceTokenDisplay.length > 0 ? '#666666' : '#999999')
              .width('100%')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis });
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1);
        }
        .width('100%')
        .padding(16)
        .backgroundColor('#FFFFFF')
        .borderRadius(12)
        .onClick(() => {
          this.copyDeviceToken();
        });
      }
      .layoutWeight(1)
      .width('100%')
      .padding(16);
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.index_page_body_background'));
  }

  private refreshSummary(): void {
    const mgr: ServerManager = ServerManager.getInstance();
    const cur: ServerEntry | null = mgr.getCurrentServer();
    if (cur) {
      this.hostDisplay = extractHost(cur.baseURL);
      this.serverName = cur.name && cur.name.length > 0 ? cur.name : cur.baseURL;
    } else {
      this.hostDisplay = '';
      this.serverName = '';
    }
    this.serverCount = mgr.getList().length;
  }

  private async refreshClientToken(): Promise<void> {
    const svc = NotifyMessageService.getInstance();
    this.customClientToken = await svc.getClientToken();
    this.isDefaultClientToken = await svc.isClientTokenDefault();
  }

  /** 卡片展示用：区分内置默认 / 用户自定义两态；token 全程不显示明文 */
  private buildClientTokenDisplay(): string {
    if (this.isDefaultClientToken) {
      return '•••••••• (内置默认 · 可修改)';
    }
    const t: string = this.customClientToken;
    // 用户自定义：只显示占位 + 长度，不暴露原文任何片段
    const masked: string = '••••••••';
    return `${masked} (已配置 · ${t.length} 位)`;
  }

  // 刷新 Device Token（Push 下发）。先等当前注册任务完成（如 PushKit 还在 getToken），
  // 再读盘；保证启动早期进入 MineView 时也能拿到 Push 写入后的值。
  private async refreshDeviceToken(): Promise<void> {
    await DeviceRegisterService.getInstance().whenRegistrationSettled();
    this.deviceTokenDisplay = await DeviceRegisterService.getInstance().getDeviceToken();
  }

  // 掩码展示：只保留最后 4 位可辨识，其余为圆点，避免卡片上泄露长 token
  private buildDeviceTokenDisplay(): string {
    const t: string = this.deviceTokenDisplay;
    if (!t || t.length === 0) {
      return '未获取';
    }
    if (t.length <= 8) {
      const dots: string = '••'.padEnd(t.length, '•');
      return `${dots} (${t.length} 位)`;
    }
    const tail: string = t.substring(t.length - 4);
    const prefixMasked: string = '••••••••';
    return `${prefixMasked}...${tail} (${t.length} 位)`;
  }

  // 点击卡片：把 Device Token 完整明文复制到剪贴板
  private async copyDeviceToken(): Promise<void> {
    const t: string = this.deviceTokenDisplay;
    if (!t || t.length === 0) {
      showToast(this.getUIContext(), '推送 Token 尚未获取');
      return;
    }
    try {
      const data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, t);
      const sys: pasteboard.SystemPasteboard = pasteboard.getSystemPasteboard();
      await sys.setData(data);
      showToast(this.getUIContext(), '已复制推送 Token', 1200);
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, TAG, 'Device Token 复制失败：%{public}s', msg);
      showToast(this.getUIContext(), '复制失败');
    }
  }

  private handleCardClicked(): void {
    try {
      this.getUIContext().getRouter().pushUrl({ url: 'pages/ServerSettingsPage' });
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, TAG, 'router push 失败：%{public}s', msg);
      showToast(this.getUIContext(), '页面无法打开');
    }
  }

  private openTokenDialog(): void {
    try {
      this.tokenDialogController.open();
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, TAG, 'token dialog open 失败：%{public}s', msg);
      showToast(this.getUIContext(), '弹窗无法打开');
    }
  }

  // 读取持久化的订阅通知开关状态（纯本地存储，不调系统 API）
  private async refreshNotifyEnabled(): Promise<void> {
    const v: string = await PreferencesUtil.getString(null, PreferencesUtil.KEY_NOTIFY_ENABLED, '');
    this.notifyEnabled = v === 'true';
  }

  // 获取 UIAbilityContext（notificationManager 需要）
  private getAbilityContext(): common.UIAbilityContext | null {
    try {
      const ctx = this.getUIContext().getHostContext();
      return ctx as common.UIAbilityContext;
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, TAG, 'getHostContext 失败：%{public}s', msg);
      return null;
    }
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
    const onButtons: promptAction.Button[] = [
      { text: '残忍拒绝', color: '#666666' },
      { text: '接受推送', color: '#FF6F22' },
    ];
    const offButtons: promptAction.Button[] = [
      { text: '保持推送', color: '#666666' },
      { text: '取消推送', color: '#FF6F22' },
    ];
    uiCtx.getPromptAction().showDialog({
      title: isOn ? '开启订阅' : '关闭订阅',
      message: isOn ? '是否要接收此订阅的通知栏推送？' : '是否要取消此订阅的通知栏推送？',
      buttons: isOn ? onButtons : offButtons,
    }, (err: BusinessError, result: promptAction.ShowDialogSuccessResponse) => {
      if (err) {
        hilog.warn(DOMAIN, TAG, 'showDialog 失败：%{public}s', err.message);
        // 弹窗异常关闭，Toggle 需回滚到实际状态
        this.notifyEnabled = isOn;
        this.notifyEnabled = !isOn;
        return;
      }
      if (result.index === 1) {
        // 确认：写盘 + 翻转本地状态（纯 UI 层；系统通知权限由【通知权限设置】入口控制）
        this.notifyEnabled = isOn;
        PreferencesUtil.putString(null, PreferencesUtil.KEY_NOTIFY_ENABLED, isOn ? 'true' : 'false');
        return;
      }
      // 取消/拒绝：notifyEnabled 未变化，Toggle 不会自动回滚，需强制同步
      // 先设为点击值（匹配 Toggle 当前视觉），再还原实际值触发重渲染
      this.notifyEnabled = isOn;
      this.notifyEnabled = !isOn;
    });
  }

  // 拉起系统应用通知设置页（用户可在其中真正开启/关闭通知）
  private async openNotifySettings(): Promise<void> {
    const ctx: common.UIAbilityContext | null = this.getAbilityContext();
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
}
