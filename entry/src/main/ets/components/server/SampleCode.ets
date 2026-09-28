import { deviceInfo } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CodeBlock } from '../../common/CodeBlock';
import { ServerEntry } from '../../model/ServerEntry';
import { ServerManager } from '../../services/ServerManager';
import { DeviceRegisterService } from '../../services/DeviceRegisterService';
import { NotifyMessageService } from '../../services/NotifyMessageService';
import { ClipboardService } from '../../services/ClipboardService';
import { buildTestGetCode, buildTestPostCode } from '../../utils/TestPushExample';
import { getMenuMaterial } from '../../utils/ImmersiveUtil';
import { DOMAIN } from '../../common/Constant';
import showToast from '../showToast';

const TAG: string = 'SampleCode';

// 推送测试卡片独立选择目标服务器，不改变通知列表的当前服务器。
@Component
export struct SampleCode {
  @State serverList: ServerEntry[] = [];
  @State selectedId: string = '';
  @State requestMethod: string = 'GET';
  @State codeText: string = '# 正在加载服务器…';
  @State testing: boolean = false;
  private onServerChange: ((list: ServerEntry[], currentId: string) => void) | null = null;
  private keyRequests: Map<string, Promise<string>> = new Map();

  aboutToAppear(): void {
    const manager: ServerManager = ServerManager.getInstance();
    this.onServerChange = (_list: ServerEntry[], _currentId: string): void => {
      this.refreshServers();
    };
    manager.addChangeListener(this.onServerChange);
    this.initialize();
  }

  aboutToDisappear(): void {
    if (this.onServerChange) {
      ServerManager.getInstance().removeChangeListener(this.onServerChange);
      this.onServerChange = null;
    }
  }

  build() {
    Column() {
      Row({ space: 6 }) {
        Row({ space: 6 }) {
          Image($r('app.media.notice_colorful'))
            .width(32)
            .height(32)
            .objectFit(ImageFit.Contain)
            .draggable(false);

          Text('推送测试')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.color_text_primary'));
        }

        Row({ space: 2 }) {
          Text('切换服务')
            .fontSize(14)
            .fontColor($r('app.color.color_text_secondary'));
          Image($r('app.media.select_more'))
            .width(18)
            .height(18)
            .fillColor($r('app.color.color_text_secondary'))
            .draggable(false);
        }
        .bindMenu(this.serverMenu(), this.menuOptions());
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.SpaceBetween);

      // 切换服务或 GET/POST 时，代码块直接使用最新的完整命令。
      Stack({ alignContent: Alignment.TopStart }) {
        CodeBlock({
          code: this.codeText,
          paddingTop: 52,
          paddingBottom: 14
        })
          .width('100%');

        Row() {
          // 每个操作项自行提供四周内边距，整块区域都能响应点击。
          Row() {
            Text('GET')
              .fontFamily('monospace')
              .fontWeight(this.requestMethod === 'GET' ? FontWeight.Bold : FontWeight.Regular)
              .fontColor(this.requestMethod === 'GET' ? $r('app.color.color_text_primary') :
                $r('app.color.color_text_secondary'))
              .fontSize(12)
              .padding({ left: 10, right: 10, top: 14, bottom: 14 })
              .textAlign(TextAlign.Center)
              .onClick(() => {
                this.selectMethod('GET');
              });
            Text('POST')
              .fontFamily('monospace')
              .fontWeight(this.requestMethod === 'POST' ? FontWeight.Bold : FontWeight.Regular)
              .fontColor(this.requestMethod === 'POST' ? $r('app.color.color_text_primary') :
                $r('app.color.color_text_secondary'))
              .fontSize(12)
              .padding({ left: 10, right: 10, top: 14, bottom: 14 })
              .textAlign(TextAlign.Center)
              .onClick(() => {
                this.selectMethod('POST');
              });
          }

          Row() {
            Image($r('app.media.copy'))
              .width(14)
              .height(14)
              .fillColor($r('app.color.color_text_secondary'))
              .draggable(false);
          }
          .padding({ left: 10, right: 10, top: 14, bottom: 14 })
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)
          .onClick(() => {
            this.copyCode();
          });
        }
        .width('100%')
        .borderRadius({ topLeft: 8, topRight: 8 })
        .backgroundColor($r('app.color.color_bg_page'))
        .alignItems(VerticalAlign.Center)
        .justifyContent(FlexAlign.SpaceBetween);
      }.margin({ top: 12 });

      // 两个底部操作均使用卡片选中的服务器，不修改通知列表的目标。
      Row({ space: 8 }) {
        // 复制操作合并为分段按钮：主区域复制 Key，右侧菜单提供地址及完整推送地址。
        Row() {
          Button('复制 Key')
            .layoutWeight(1)
            .height(44)
            .fontSize(14)
            .fontColor($r('app.color.color_text_primary'))
            .backgroundColor(Color.Transparent)
            .borderRadius(0)
            .enabled(this.serverList.length > 0)
            .onClick(() => {
              this.copyKey();
            });
          Divider()
            .vertical(true)
            .height(20)
            .strokeWidth(0.5)
            .color($r('app.color.color_border_subtle'));
          Row() {
            Image($r('app.media.select_more'))
              .width(16)
              .height(16)
              .fillColor($r('app.color.color_text_secondary'))
              .draggable(false);
          }
          .width(34)
          .height(44)
          .justifyContent(FlexAlign.Center)
          .enabled(this.serverList.length > 0)
          .bindMenu(this.copyMenu(), this.menuOptions());
        }
        .layoutWeight(1)
        .height(44)
        .backgroundColor($r('app.color.color_bg_control_glass'))
        .borderRadius(10)
        .clip(true);

        Button() {
          Row({ space: 6 }) {
            Image($r('app.media.send'))
              .width(16)
              .height(16)
              .fillColor(Color.White)
              .objectFit(ImageFit.Contain)
              .draggable(false);
            Text(this.testing ? '发送中…' : '发送通知')
              .fontSize(14)
              .fontColor(Color.White);
          }
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center);
        }
        .layoutWeight(1)
        .height(44)
        .backgroundColor($r('app.color.color_brand'))
        .borderRadius(10)
        .enabled(this.serverList.length > 0 && !this.testing)
        .onClick(() => {
          this.sendTestNotification();
        });
      }
      .width('100%')
      .margin({ top: 16 });
    }
    .padding(16)
    .borderRadius(10)
    .backgroundColor($r('app.color.color_bg_surface'));
  }

  // 服务列表可能晚于 Tab 渲染完成；初始化后回填默认选中项及代码块。
  private async initialize(): Promise<void> {
    await ServerManager.getInstance().ensureLoaded();
    this.refreshServers();
    const server: ServerEntry | null = this.selectedServer();
    if (server) {
      await this.ensureDeviceKey(server);
    }
  }

  // 服务增删或 Key 更新时刷新；手动选中的目标仍存在就不跟随全局当前服务器改变。
  private refreshServers(): void {
    const manager: ServerManager = ServerManager.getInstance();
    const list: ServerEntry[] = manager.getList();
    this.serverList = list;
    if (!list.some((item: ServerEntry) => item.id === this.selectedId)) {
      const current: ServerEntry | null = manager.getCurrentServer();
      this.selectedId = current ? current.id : (list.length > 0 ? list[0].id : '');
    }
    this.updateCode();
  }

  // 从当前卡片选中 id 查找目标，防止全局 server 切换影响复制与测试。
  private selectedServer(): ServerEntry | null {
    for (let i: number = 0; i < this.serverList.length; i++) {
      if (this.serverList[i].id === this.selectedId) {
        return this.serverList[i];
      }
    }
    return null;
  }

  // Menu 只展示域名（含端口）；服务器的自定义名称不参与此处显示。
  private hostOf(baseURL: string): string {
    let host: string = baseURL;
    const schemeEnd: number = host.indexOf('://');
    if (schemeEnd >= 0) {
      host = host.substring(schemeEnd + 3);
    }
    const slash: number = host.indexOf('/');
    return slash >= 0 ? host.substring(0, slash) : host;
  }

  // 首次缺少 per-server Key 时按既有注册流程获取；同一服务并发点击共享一个请求。
  private async ensureDeviceKey(server: ServerEntry): Promise<string> {
    if (server.deviceKey.length > 0) {
      return server.deviceKey;
    }
    const pending: Promise<string> | undefined = this.keyRequests.get(server.id);
    if (pending) {
      return pending;
    }
    const current: ServerEntry | null = ServerManager.getInstance().getCurrentServer();
    // 当前服务复用 ServerList/启动流程的并发注册；其它服务按指定 id 单独获取，绝不切换全局目标。
    const request: Promise<string> = (current && current.id === server.id
      ? DeviceRegisterService.getInstance().ensureRegistered(null)
      : DeviceRegisterService.getInstance().syncKeyForServer(null, server.id, server.baseURL, ''))
      .then((key: string | null): string => key ?? '');
    this.keyRequests.set(server.id, request);
    try {
      return await request;
    } catch (err) {
      hilog.warn(DOMAIN, TAG, '获取设备 Key 失败：serverId=%{public}s reason=%{public}s', server.id,
        err instanceof Error ? err.message : String(err));
      return '';
    } finally {
      this.keyRequests.delete(server.id);
      this.refreshServers();
    }
  }

  // 选中项仅改变卡片的代码、复制和测试目标。
  private selectServer(id: string): void {
    this.selectedId = id;
    this.updateCode();
    const server: ServerEntry | null = this.selectedServer();
    if (server) {
      this.ensureDeviceKey(server);
    }
  }

  // GET/POST 共用选中服务及 Key；无 Key 时不生成误导性的可执行命令。
  private updateCode(): void {
    const server: ServerEntry | null = this.selectedServer();
    if (!server) {
      this.codeText = '# 暂无服务器';
      return;
    }
    if (server.deviceKey.length === 0) {
      this.codeText = '# 此服务尚未取得设备 Key，请稍候或点击下方操作重试';
      return;
    }
    this.codeText = this.requestMethod === 'POST' ?
      buildTestPostCode(server.baseURL, server.deviceKey) : buildTestGetCode(server.baseURL, server.deviceKey);
  }

  private selectMethod(method: string): void {
    this.requestMethod = method;
    this.updateCode();
  }

  // 沉浸光感系统 Menu 与旧设备模糊降级沿用加密设置的菜单样式。
  private menuOptions(): MenuOptions {
    const options: MenuOptions = { placement: Placement.BottomRight };
    if (deviceInfo.apiAvailable('26.0.0')) {
      const material = getMenuMaterial();
      if (material) {
        options.systemMaterial = material;
      }
    }
    return options;
  }

  @Builder
  private serverMenu() {
    Menu() {
      if (this.serverList.length === 0) {
        MenuItem({ content: '暂无服务器' }).enabled(false);
      }
      ForEach(this.serverList, (server: ServerEntry) => {
        MenuItem({ content: this.hostOf(server.baseURL) })
          .contentFontColor(server.id === this.selectedId ? $r('app.color.color_brand') :
            $r('app.color.color_text_primary'))
          .backgroundColor(server.id === this.selectedId ? $r('app.color.color_bg_selected_glass') :
            Color.Transparent)
          .onClick(() => {
            this.selectServer(server.id);
          });
      }, (server: ServerEntry) => server.id);
    }
    .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
    .backgroundColor($r('app.color.color_bg_dialog_glass'));
  }

  // 分段按钮右侧的菜单只操作卡片当前选中的服务器。
  @Builder
  private copyMenu() {
    Menu() {
      MenuItem({ content: '复制地址' }).onClick(() => {
        this.copyAddress();
      });
      MenuItem({ content: '复制地址和 Key' }).onClick(() => {
        this.copyAddressAndKey();
      });
    }
    .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
    .backgroundColor($r('app.color.color_bg_dialog_glass'));
  }

  // 复制当前展示模式的完整、可执行命令。
  private async copyCode(): Promise<void> {
    const server: ServerEntry | null = this.selectedServer();
    if (!server) {
      showToast(this.getUIContext(), '暂无可用服务器');
      return;
    }
    const key: string = await this.ensureDeviceKey(server);
    if (!key) {
      showToast(this.getUIContext(), '未获取到设备 Key');
      return;
    }
    const code: string = this.requestMethod === 'POST' ?
      buildTestPostCode(server.baseURL, key) : buildTestGetCode(server.baseURL, key);
    const ok: boolean = await ClipboardService.copyText(code);
    showToast(this.getUIContext(), ok ? '代码已复制' : '复制失败');
  }

  // 复制卡片选中服务器的推送地址与设备 Key。
  private async copyAddressAndKey(): Promise<void> {
    const server: ServerEntry | null = this.selectedServer();
    if (!server) {
      showToast(this.getUIContext(), '暂无可用服务器');
      return;
    }
    const key: string = await this.ensureDeviceKey(server);
    if (!key) {
      showToast(this.getUIContext(), '未获取到设备 Key');
      return;
    }
    const baseURL: string = server.baseURL.replace(/\/+$/, '');
    const ok: boolean = await ClipboardService.copyText(`${baseURL}/${key}`);
    showToast(this.getUIContext(), ok ? '已复制地址和 Key' : '复制失败');
  }

  // 单独复制服务器地址，不依赖设备 Key 是否已注册。
  private async copyAddress(): Promise<void> {
    const server: ServerEntry | null = this.selectedServer();
    if (!server) {
      showToast(this.getUIContext(), '暂无可用服务器');
      return;
    }
    const ok: boolean = await ClipboardService.copyText(server.baseURL.replace(/\/+$/, ''));
    showToast(this.getUIContext(), ok ? '已复制地址' : '复制失败');
  }

  // 单独复制当前服务器的设备 Key；缺失时先复用原有注册流程获取。
  private async copyKey(): Promise<void> {
    const server: ServerEntry | null = this.selectedServer();
    if (!server) {
      showToast(this.getUIContext(), '暂无可用服务器');
      return;
    }
    const key: string = await this.ensureDeviceKey(server);
    if (!key) {
      showToast(this.getUIContext(), '未获取到设备 Key');
      return;
    }
    const ok: boolean = await ClipboardService.copyText(key);
    showToast(this.getUIContext(), ok ? '已复制 Key' : '复制失败');
  }

  // 向选中的服务器发送与代码块相同参数的 POST 测试推送。
  private async sendTestNotification(): Promise<void> {
    if (this.testing) {
      return;
    }
    const server: ServerEntry | null = this.selectedServer();
    if (!server) {
      showToast(this.getUIContext(), '暂无可用服务器');
      return;
    }
    this.testing = true;
    try {
      const key: string = await this.ensureDeviceKey(server);
      if (!key) {
        showToast(this.getUIContext(), '未获取到设备 Key');
        return;
      }
      const error: string = await NotifyMessageService.getInstance().sendTestPush(server, key);
      showToast(this.getUIContext(), error.length > 0 ? error : '测试通知已发送，请查看通知栏',
        error.length > 0 ? 3000 : 2000);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, '测试通知发送失败：%{public}s', err instanceof Error ? err.message : String(err));
      showToast(this.getUIContext(), '发送失败，请稍后重试');
    } finally {
      this.testing = false;
    }
  }
}
