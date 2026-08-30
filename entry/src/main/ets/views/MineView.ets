import { hilog } from '@kit.PerformanceAnalysisKit';
import { promptAction, UIContext } from '@kit.ArkUI';
import { BusinessError, deviceInfo, pasteboard } from '@kit.BasicServicesKit';
import { bundleManager, common } from '@kit.AbilityKit';
import { notificationManager } from '@kit.NotificationKit';
import { fileIo, picker } from '@kit.CoreFileKit';
import { ServerEntry } from '../model/ServerEntry';
import { ServerManager } from '../services/ServerManager';
import { extractHost } from '../components/ServerSettingsContent';
import { ClientTokenDialog } from '../components/ClientTokenDialog';
import { NotifyMessageService } from '../services/NotifyMessageService';
import { DeviceRegisterService } from '../services/DeviceRegisterService';
import { PreferencesUtil } from '../utils/PreferencesUtil';
import showToast from '../components/showToast';
import { DOMAIN } from '../common/Constant';
import { BuildInfo } from '../generated/BuildInfo';
import { resolveBlurStyle, SUPPORTS_IMMERSIVE_MATERIAL } from '../utils/ImmersiveUtil';
import { hdsMaterial, HdsNavigation, HdsNavigationTitleMode, ScrollEffectType } from '@kit.UIDesignKit';

// 版本号兜底常量，与 AppScope/app.json5 保持一致，防止 bundleManager 返回空时显示异常
const FALLBACK_VERSION_NAME: string = '1.0.0';
const FALLBACK_VERSION_CODE: number = 1000000;

const TAG: string = 'MineView';

export const SOURCE_CODE_URL: string = 'https://github.com/wallleap/timelynotify';

export const USE_DOCS_URL: string = 'https://docs.timelynotify.oicode.cn';

export const PRIVACY_URL: string =
  'https://agreement-drcn.hispace.dbankcloud.cn/index.html?lang=zh&agreementId=2026233837759005504';

export const FEEDBACK_EMAIL: string = 'vonnelu@163.com';


// 我的页 - 展示个人设置入口
@Component
export struct MineView {
  // 状态栏/导航条高度（vp），EntryAbility 沉浸式布局初始化时写入 AppStorage（键值见 ImmersiveUtil）
  @StorageProp('statusBarHeight') statusBarHeight: number = 36;
  @StorageProp('navBarHeight') navBarHeight: number = 0;
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
  // 是否正在执行消息导出（拉取 + 保存全程置 true，防止重复触发）
  @State exporting: boolean = false;
  // 是否正在发送测试通知（请求期间置 true，防止重复触发）
  @State testingPush: boolean = false;
  // 版本号展示（读取自 BundleInfo；异常时使用兜底常量）
  @State versionNameDisplay: string = FALLBACK_VERSION_NAME;
  @State versionCodeDisplay: number = FALLBACK_VERSION_CODE;
  // 签名证书指纹尾 8 位（运行时读取；完整指纹发布在 README / GitHub Release 供比对）
  @State certFingerprintTail: string = '';
  private onChange: ((list: ServerEntry[], curId: string) => void) | null = null;
  // 官方结构：Scroll 绑定自己的 Scroller 实例，供 HdsNavigation.bindToScrollable 用
  private scroller: Scroller = new Scroller();
  // client token 弹窗（打开时回填用户自定义内容；内置默认时显示空 placeholder，用户填即覆盖）
  private tokenDialogController: CustomDialogController = new CustomDialogController({
    builder: ClientTokenDialog({
      getInitToken: (): string => this.customClientToken, onSaved: (): void => {
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
    this.refreshAppVersion();
    this.refreshCertFingerprint();
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

  // 降级顶栏：低版本 SDK 手工 Stack 叠层，blurStyle + 半透明底色实现毛玻璃
  @Builder
  fallbackTitleBar() {
    Row() {
      Text('我的').fontSize(24).fontWeight(FontWeight.Bold).width('100%').textAlign(TextAlign.Center);
    }.width('100%').padding({
      left: 16,
      right: 16,
      top: 16 + this.statusBarHeight,
      bottom: 16
    })
    // blurStyle 只做模糊不调色 → 必须叠加半透明底色才看得到毛玻璃
    .backgroundBlurStyle(resolveBlurStyle('bar')!)
    .backgroundColor($r('app.color.index_page_top_glass_background'));
  }

  // HDS 顶栏自定义内容（塞入 HdsNavigation.titleBar.content.stackBuilder）。
  // 状态栏避让由 titleBar 级 avoidLayoutSafeArea: true 负责（系统将内容整体下移 statusBarHeight）；
  // 此处 padding 只留纯视觉余量，不得再叠加 statusBarHeight（titleBar 高度固定，会溢出裁剪 → 文字消失）。
  @Builder
  customTitleContent() {
    Row() {
      Text('我的')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .width('100%')
        .textAlign(TextAlign.Center)
        .fontColor($r('app.color.text_primary_color'));
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({
      left: 16,
      right: 16,
      top: 16,
      bottom: 16
    });
  }

  // MineView 滚动内容主体（卡片列表），两条渲染路径共用
  @Builder
  scrollBody() {
    Scroll(this.scroller) {
      Column({ space: 16 }) {
        // 首项占位：组件级安全区（enableComponentSafeArea）已自动让内容起始于 titleBar 下方 → HDS 删除
        // 降级（Stack 叠层）仍需手工 statusBarHeight + titleBar(56) + 8 余量
        if (!SUPPORTS_IMMERSIVE_MATERIAL) {
          Row().width('100%').height(this.statusBarHeight + 56 + 4);
        }

        // 通知设置卡片
        Column({ space: 0 }) { // 开启应用订阅通知（开关）
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

        Column({ space: 8 }) {
          Text('配置')
            .fontSize(12)
            .fontColor($r('app.color.text_quinary_color'))
            .width('100%')
            .padding({ left: 12 });

          Column({ space: 12 }) { // 服务器入口卡片
            Row({ space: 14 }) {
              Column({ space: 4 }) {
                Row() {
                  Text('服务器')
                    .fontSize(17)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.text_primary_color'));
                }.width('100%');

                Row() {
                  Text(this.serverName)
                    .fontSize(14)
                    .fontColor($r('app.color.text_tertiary_color'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis });
                  Text(' (').fontSize(14).fontColor($r('app.color.text_tertiary_color')).maxLines(1)
                  Text(this.hostDisplay)
                    .fontSize(12)
                    .fontColor($r('app.color.text_accent_color'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis });
                  Text(')').fontSize(14).fontColor($r('app.color.text_tertiary_color')).maxLines(1)
                }.width('100%')
              }.alignItems(HorizontalAlign.Start).layoutWeight(1);

              Row() {
                Text(`共 ${this.serverCount} 个`).fontSize(12).fontColor($r('app.color.text_quinary_color'));
                this.arrowRightIcon()
              }
            }
            .width('100%')
            .padding(16)
            .backgroundBlurStyle(resolveBlurStyle('bar')!)
            .backgroundColor($r('app.color.card_glass_background'))
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
                  .fontColor($r('app.color.text_primary_color'))
                  .width('100%');

                Text(this.buildClientTokenDisplay())
                  .fontSize(14)
                  .fontColor(this.isDefaultClientToken ? $r('app.color.text_accent_color') :
                    $r('app.color.text_tertiary_color'))
                  .width('100%')
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis });
              }.alignItems(HorizontalAlign.Start).layoutWeight(1);

              this.arrowRightIcon()
            }
            .width('100%')
            .padding(16)
            .backgroundBlurStyle(resolveBlurStyle('bar')!)
            .backgroundColor($r('app.color.card_glass_background'))
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
                    .fontColor($r('app.color.text_primary_color'));
                  Text(' (自动生成)')
                    .fontSize(14)
                    .fontColor($r('app.color.text_tertiary_color'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis });
                  Blank();
                  Text('点击复制').fontSize(12).fontColor($r('app.color.text_accent_color'));
                }.width('100%');

                Text(this.buildDeviceTokenDisplay())
                  .fontSize(14)
                  .fontColor(this.deviceTokenDisplay.length > 0 ? $r('app.color.text_tertiary_color') :
                    $r('app.color.text_quinary_color'))
                  .width('100%')
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis });
              }.alignItems(HorizontalAlign.Start).layoutWeight(1);
            }
            .width('100%')
            .padding(16)
            .backgroundBlurStyle(resolveBlurStyle('bar')!)
            .backgroundColor($r('app.color.card_glass_background'))
            .borderRadius(12)
            .onClick(() => {
              this.copyDeviceToken();
            });
          }.width('100%')
        }.width('100%');

        // 关于板块（卡片内承载后续扩展项）
        Column({ space: 8 }) {
          Text('关于')
            .fontSize(12)
            .fontColor($r('app.color.text_quinary_color'))
            .width('100%')
            .padding({ left: 12 });

          Column({ space: 0 }) { // 版本号行（整行点击复制版本信息）
            Row() {
              Text('当前版本')
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary_color'))
                .layoutWeight(1);
              Text(`${this.versionNameDisplay} (${this.versionCodeDisplay})`)
                .fontSize(14)
                .fontColor($r('app.color.text_tertiary_color'));
            }.width('100%').padding(16).onClick(() => {
              this.copyVersionInfo();
            });

            Divider().color($r('app.color.divider_color')).strokeWidth(1).margin({ left: 16, right: 16 });

            // 构建信息行（展示云端构建编号 / commit / 签名指纹尾串；点击打开构建记录页供用户比对防伪）
            Row() {
              Column({ space: 2 }) {
                Text('构建信息')
                  .fontSize(16)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_primary_color'));
                Text(this.buildBuildInfoDisplay())
                  .fontSize(12)
                  .fontColor($r('app.color.text_quinary_color'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis });
              }.alignItems(HorizontalAlign.Start).layoutWeight(1);

              // 云端构建才有对应记录页，本地构建不显示箭头
              if (this.hasCloudBuild()) {
                this.arrowRightIcon();
              }
            }.width('100%').padding(16).onClick(() => {
              this.openBuildInfo();
            });

            Divider().color($r('app.color.divider_color')).strokeWidth(1).margin({ left: 16, right: 16 });

            // 开源代码行（点击跳转 GitHub）
            Row() {
              Text('开源代码')
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary_color'))
                .layoutWeight(1);
              this.arrowRightIcon();
            }.width('100%').padding(16).onClick(() => {
              this.openSourceLink();
            });

            Divider().color($r('app.color.divider_color')).strokeWidth(1).margin({ left: 16, right: 16 });

            // 使用文档行（进入内嵌 WebView）
            Row() {
              Text('使用文档')
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary_color'))
                .layoutWeight(1);
              this.arrowRightIcon();
            }.width('100%').padding(16).onClick(() => {
              this.openDocs();
            });

            Divider().color($r('app.color.divider_color')).strokeWidth(1).margin({ left: 16, right: 16 });

            // 隐私协议行
            Row() {
              Text('隐私协议')
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary_color'))
                .layoutWeight(1);
              this.arrowRightIcon();
            }.width('100%').padding(16).onClick(() => {
              this.openPrivacy();
            });

            Divider().color($r('app.color.divider_color')).strokeWidth(1).margin({ left: 16, right: 16 });

            // 反馈问题行（发送邮件）
            Row() {
              Text('反馈问题')
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary_color'))
                .layoutWeight(1);
              this.arrowRightIcon();
            }.width('100%').padding(16).onClick(() => {
              this.sendFeedback();
            });
          }
          .width('100%')
          .backgroundBlurStyle(resolveBlurStyle('bar')!)
          .backgroundColor($r('app.color.card_glass_background'))
          .borderRadius(12);
        }.width('100%');

        // 底部占位：随内容一起滚动，末尾卡片才能滑入 TabBar 毛玻璃下方（padding 是硬边界做不到）
        // TabBar 总高 = 56 + 导航条高度，占位 72 保持视觉余量不变
        Row().width('100%').height(this.navBarHeight + 72);
      }.width('100%') // 左右避让边距（顶/底避让由首尾占位实现）
      .padding({ left: 16, right: 16 });
    }
    .align(Alignment.TopStart)
    .height('100%')
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .width('100%')
    // ⚠️ 官方 HDS 动态模糊必配：Scroll 不裁剪溢出，卡片才能向上穿出至 titleBar 背面被材质采样
    .clip(false);
  }

  build() {
    if (SUPPORTS_IMMERSIVE_MATERIAL) {
      // ─── API 26+: HdsNavigation 原生沉浸光感（titleBar 内置 systemMaterialEffect）───
      HdsNavigation() {
        this.scrollBody();
      }
      .titleBar({
        enableComponentSafeArea: true,
        // ⚠️ stackBuilder 全自定义区域系统不做状态栏避让（系统 mainTitle 槽位才自带避让），
        // 必须显式开启 avoidLayoutSafeArea，titleBar 内容整体下移 statusBarHeight，总高自动变为 statusBarHeight+56；
        // stackBuilder 内部不要再手工加 statusBarHeight（titleBar 高度固定会溢出裁剪）
        avoidLayoutSafeArea: true,
        content: {
          // 自定义整段标题区：仅展示居中 24vp「我的」大字
          stackBuilder: (): void => {
            this.customTitleContent();
          },
        },
        style: {
          // 滚动到顶栏下方时触发 GradientBlur 渐变模糊：采样下层内容做动态光感模糊
          scrollEffectOpts: {
            enableScrollEffect: true,
            scrollEffectType: ScrollEffectType.GRADIENT_BLUR
          },
          systemMaterialEffect: {
            materialType: hdsMaterial.MaterialType.ADAPTIVE,
            // 官方推荐 ADAPTIVE：系统按设备算力自适应档位，避免低端机卡顿/发热
            //（EXQUISITE 需 getSystemMaterialTypes() 检测支持后才可硬编码）
            materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
          },
        }
      })
      .hideBackButton(true)
      .titleMode(HdsNavigationTitleMode.MINI)
      // 官方：绑定 Scroll 滚动 → scrollEffectOpts 才会根据滚动偏移激活 GradientBlur 渐变模糊
      .bindToScrollable([this.scroller])
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.index_page_body_background'));
    } else {
      // ─── API < 26: Stack + 手工顶栏叠层（backgroundBlurStyle 降级）───
      Column() {
        Stack({ alignContent: Alignment.Top }) {
          this.scrollBody();
          // 顶栏层（上层）：blurStyle + 半透明底色糊住下层滚动内容
          this.fallbackTitleBar();
        }.width('100%').layoutWeight(1);
      }
      .width('100%').height('100%')
      .backgroundColor($r('app.color.index_page_body_background'));
    }
  }

  // 统一的右箭头图标：列表行/卡片通用，尺寸与颜色只需在此处调整
  @Builder
  arrowRightIcon() {
    Image($r('app.media.arrow_right'))
      .width(20)
      .height(20)
      .objectFit(ImageFit.Contain)
      .fillColor($r('app.color.text_quinary_color'))
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
    const t: string = this.customClientToken; // 用户自定义：只显示占位 + 长度，不暴露原文任何片段
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
      showToast(this.getUIContext(), '推送 Token 尚未获取', 3000);
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

  private async handleCardClicked(): Promise<void> {
    try {
      await this.getUIContext().getRouter().pushUrl({ url: 'pages/ServerSettingsPage' });
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

  // 生成导出文件名时间后缀：yyyyMMdd_HHmmss
  private formatExportTime(d: Date): string {
    const p = (n: number): string => (n < 10 ? '0' + n : String(n));
    return `${d.getFullYear()}${p(d.getMonth() + 1)}${p(d.getDate())}_${p(d.getHours())}${p(d.getMinutes())}${p(
      d.getSeconds())}`;
  }

  // 导出当前设备全部消息：
  // 1. GET /{device_key}/message?limit=-1 全量拉取（服务端流式返回）
  // 2. 序列化为 JSON 数组文本（2 空格缩进）
  // 3. DocumentViewPicker 拉起系统保存对话框（无需权限），用户选择位置后写入 txt
  private async exportMessages(): Promise<void> {
    if (this.exporting) {
      return; // 防重复触发
    }
    const uiCtx: UIContext = this.getUIContext();
    this.exporting = true;
    try {
      const result = await NotifyMessageService.getInstance().exportAllMessages(null);
      if (!result.ok) {
        showToast(uiCtx, result.errorMsg.length > 0 ? result.errorMsg : '导出失败');
        return;
      }
      // 纯 JSON 数组文本（2 空格缩进便于阅读，整体仍是合法 JSON）
      const text: string = JSON.stringify(result.rawMessages, null, 2);

      // 系统保存对话框：预设文件名 + txt 过滤；Picker 保存无需申请权限
      const saveOptions = new picker.DocumentSaveOptions();
      saveOptions.newFileNames = [`timelynotify_export_${this.formatExportTime(new Date())}.txt`];
      saveOptions.fileSuffixChoices = ['文档|.txt'];
      const abilityCtx = this.getAbilityContext();
      if (!abilityCtx) {
        showToast(uiCtx, '上下文获取失败');
        return;
      }
      const docPicker = new picker.DocumentViewPicker(abilityCtx);
      const uris: string[] = await docPicker.save(saveOptions);
      if (uris.length === 0) {
        return; // 用户取消保存，静默结束
      }

      // Picker 返回的 URI 需以 READ_WRITE 模式打开后写入
      const file = fileIo.openSync(uris[0], fileIo.OpenMode.READ_WRITE);
      try {
        fileIo.writeSync(file.fd, text);
      } finally {
        fileIo.closeSync(file);
      }

      // 成功提示；流被截断时额外说明数据可能不完整
      const count: number = result.rawMessages.length;
      if (result.truncated) {
        showToast(uiCtx, `导出完成（流中断，可能不完整），共 ${count} 条`, 3000);
      } else {
        showToast(uiCtx, `已导出 ${count} 条消息`, 1500);
      }
      hilog.info(DOMAIN, TAG, '消息导出完成：count=%{public}d truncated=%{public}s', count, String(result.truncated));
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, TAG, '导出消息失败：%{public}s', msg);
      showToast(uiCtx, '导出失败');
    } finally {
      this.exporting = false;
    }
  }

  // 读取自身应用版本号（Stage 模式官方接口，无需权限）
  private async refreshAppVersion(): Promise<void> {
    try {
      const flags: number = bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION;
      const info: bundleManager.BundleInfo =
        await bundleManager.getBundleInfoForSelf(flags); // versionName 可能因 module.json5 未声明 version.name 而空串，非空才覆盖兜底
      if (info.versionName && info.versionName.length > 0) {
        this.versionNameDisplay = info.versionName;
      }
      if (info.versionCode > 0) {
        this.versionCodeDisplay = info.versionCode;
      }
      hilog.info(DOMAIN, TAG, '版本号读取：name=%{public}s code=%{public}d', this.versionNameDisplay,
        this.versionCodeDisplay);
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, TAG, 'getBundleInfoForSelf 失败：%{public}s，使用兜底版本', msg); // 失败时保留构造时设置的兜底常量，不做 UI 提示
    }
  }

  // 点击关于板块：复制完整版本信息到剪贴板
  private async copyVersionInfo(): Promise<void> {
    // 组装版本 + 构建溯源信息（便于反馈问题时一次性提供完整证据链）
    const lines: string[] = [`TimelyNotify ${this.versionNameDisplay} (${this.versionCodeDisplay})`];
    if (this.hasCloudBuild()) {
      lines.push(`构建：GitHub Actions Run #${BuildInfo.RUN_NUMBER} (${BuildInfo.RUN_ID})`);
    } else {
      lines.push('构建：本地构建');
    }
    if (BuildInfo.COMMIT_SHA.length > 0) {
      lines.push(`commit：${BuildInfo.COMMIT_SHA}`);
    }
    if (this.certFingerprintTail.length > 0) {
      lines.push(`签名指纹尾 8 位：${this.certFingerprintTail}`);
    }
    const text: string = lines.join('\n');
    try {
      const data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      const sys: pasteboard.SystemPasteboard = pasteboard.getSystemPasteboard();
      await sys.setData(data);
      showToast(this.getUIContext(), `已复制版本：${this.versionNameDisplay}`, 1200);
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, TAG, '版本信息复制失败：%{public}s', msg);
      showToast(this.getUIContext(), text, 1500);
    }
  }

  // 是否为云端构建（GitHub Actions 产物才有可跳转的构建记录页）
  private hasCloudBuild(): boolean {
    return BuildInfo.RUN_ID.length > 0;
  }

  // 构建信息副标题：云端构建显示 Build 编号 · commit 前 7 位 · 指纹尾 8 位；本地构建显示"本地构建"前缀
  private buildBuildInfoDisplay(): string {
    const parts: string[] = [];
    if (BuildInfo.COMMIT_SHA.length >= 7) {
      parts.push(BuildInfo.COMMIT_SHA.substring(0, 7));
    }
    if (this.certFingerprintTail.length > 0) {
      parts.push(`指纹…${this.certFingerprintTail}`);
    }
    if (this.hasCloudBuild()) {
      return `Build #${BuildInfo.RUN_NUMBER} · ${parts.join(' · ')}`;
    }
    // 本地构建：指纹仍有效（对应调试证书），但与 README 公布的发布指纹不同属正常
    return `本地构建${parts.length > 0 ? ' · ' + parts.join(' · ') : ''}`;
  }

  // 点击构建信息行：打开云端构建记录页（伪造包无法在官方仓库创建对应 run 记录，以此验证包来源）
  private async openBuildInfo(): Promise<void> {
    if (!this.hasCloudBuild()) {
      showToast(this.getUIContext(), '本地构建，无云端构建记录', 2000);
      return;
    }
    const runUrl: string = `${SOURCE_CODE_URL}/actions/runs/${BuildInfo.RUN_ID}`;
    try {
      await this.getUIContext().getRouter().pushUrl({
        url: 'pages/SharePage', params: { url: runUrl, title: '构建信息' }
      });
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, TAG, '跳转构建记录页失败：%{public}s', msg);
      showToast(this.getUIContext(), '无法打开页面');
    }
  }

  // 运行时读取签名证书指纹（SHA-256，官方接口无需权限）：
  // 伪造包必然更换签名证书 → 指纹必变；与 README/Release 公布的指纹比对即可识别
  private async refreshCertFingerprint(): Promise<void> {
    try {
      const flags: number = bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_SIGNATURE_INFO;
      const info: bundleManager.BundleInfo = await bundleManager.getBundleInfoForSelf(flags);
      const sig: bundleManager.SignatureInfo | undefined = info.signatureInfo;
      const fp: string = sig ? sig.fingerprint : '';
      if (fp.length >= 8) {
        this.certFingerprintTail = fp.substring(fp.length - 8);
      }
      hilog.info(DOMAIN, TAG, '签名指纹读取成功，尾 8 位：%{public}s', this.certFingerprintTail);
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, TAG, '签名指纹读取失败：%{public}s', msg); // 失败时留空，构建信息行降级为只显示 commit
    }
  }

  // 点击开源代码行：进入内嵌 WebView 页面
  private async openSourceLink(): Promise<void> {
    try {
      await this.getUIContext().getRouter().pushUrl({
        url: 'pages/SharePage', params: { url: SOURCE_CODE_URL, title: '开源代码' }
      });
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, TAG, '跳转 SharePage 失败：%{public}s', msg);
      showToast(this.getUIContext(), '无法打开页面');
    }
  }

  // 点击使用文档行：进入内嵌 WebView 页面
  private async openDocs(): Promise<void> {
    try {
      await this.getUIContext().getRouter().pushUrl({
        url: 'pages/SharePage', params: { url: USE_DOCS_URL, title: '使用文档' }
      });
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, TAG, '跳转 SharePage 失败：%{public}s', msg);
      showToast(this.getUIContext(), '无法打开页面');
    }
  }

  // 点击隐私协议行：进入内嵌 WebView 页面
  private async openPrivacy(): Promise<void> {
    try {
      await this.getUIContext().getRouter().pushUrl({
        url: 'pages/SharePage', params: { url: PRIVACY_URL, title: '隐私协议' }
      });
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, TAG, '跳转 SharePage 失败：%{public}s', msg);
      showToast(this.getUIContext(), '无法打开页面');
    }
  }

  // 点击反馈问题行：通过 startAbilityByType 拉起系统邮件应用，自动附带设备信息
  private sendFeedback(): void {
    try {
      const appVersion: string = `TimelyNotify ${this.versionNameDisplay} (${this.versionCodeDisplay})`;
      let model: string = '';
      let osVer: string = '';
      try {
        model = deviceInfo.productModel;
        osVer = deviceInfo.osFullName;
      } catch (_e) { // 设备信息读取失败时留空，不阻断发邮件
      }
      const body: string = '请在此描述你遇到的问题或建议：\n\n' + '---------------- 设备信息 ----------------\n' +
        `应用版本：${appVersion}\n` + `设备型号：${model}\n` + `系统版本：${osVer}\n` +
        `反馈时间：${new Date().toLocaleString()}\n`;
      const subject: string = `TimelyNotify 反馈 - ${model}`;
      const ctx: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const wantParam: Record<string, Object> = {
        'sceneType': 1,
        'email': [encodeURI(FEEDBACK_EMAIL)],
        'subject': encodeURI(subject),
        'body': encodeURI(body)
      };
      const abilityStartCallback: common.AbilityStartCallback = {
        onError: (code: number, name: string, message: string) => {
          hilog.warn(DOMAIN, TAG, '邮件应用拉起失败：code=%{public}d name=%{public}s msg=%{public}s，回退为复制邮箱',
            code, name, message);
          this.copyFeedbackEmail();
        }, onResult: (_result) => {
          hilog.info(DOMAIN, TAG, '邮件应用返回');
        }
      };
      ctx.startAbilityByType('mail', wantParam, abilityStartCallback, (err) => {
        if (err) {
          hilog.warn(DOMAIN, TAG, 'startAbilityByType 异常：%{public}s，回退为复制邮箱', err.message);
          this.copyFeedbackEmail();
        } else {
          hilog.info(DOMAIN, TAG, '邮件应用拉起成功');
        }
      });
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, TAG, 'sendFeedback 异常：%{public}s，回退为复制邮箱', msg);
      this.copyFeedbackEmail();
    }
  }

  // 无可用邮件应用时，复制邮箱地址到剪贴板作为兜底
  private async copyFeedbackEmail(): Promise<void> {
    try {
      const data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, FEEDBACK_EMAIL);
      const sys: pasteboard.SystemPasteboard = pasteboard.getSystemPasteboard();
      await sys.setData(data);
      showToast(this.getUIContext(), `已复制邮箱：${FEEDBACK_EMAIL}`);
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, TAG, '邮箱复制失败：%{public}s', msg);
      showToast(this.getUIContext(), `请发送邮件至：${FEEDBACK_EMAIL}`);
    }
  }
}
