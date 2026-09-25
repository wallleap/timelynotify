import { hilog } from '@kit.PerformanceAnalysisKit';
import { NotifyMessageService } from '../services/NotifyMessageService';
import { DOMAIN } from '../common/Constant';
import showToast from './showToast';

const TAG: string = 'ClientTokenDlg';

// 自建服务部署文档（含 client_token 配置说明）
const DEPLOY_DOCS_URL: string = 'https://docs.timelynotify.oicode.cn/deploy/#client-token';

@Builder
function emptyTokenBuilder(): void {
}

// 客户端 Token 配置弹窗（用于调用 GET /:device_key/message 的 X-Gotify-Key 认证）
@CustomDialog
export struct ClientTokenDialog {
  controller: CustomDialogController = new CustomDialogController({
    builder: emptyTokenBuilder(),
    autoCancel: true,
    alignment: DialogAlignment.Center,
    offset: { dx: 0, dy: 0 },
  });
  @State inputToken: string = '';

  // 拉取当前已保存的 token 预填
  getInitToken: () => string = () => '';
  onSaved: () => void = () => {
  };

  aboutToAppear() {
    this.inputToken = this.getInitToken();
  }

  build() {
    Column({ space: 12 }) {
      Text('客户端 Token')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .width('100%')
        .textAlign(TextAlign.Center);

      Column({ space: 4 }) {
        Text('用于同步历史通知（X-Gotify-Key 认证）')
          .fontSize(12)
          .fontColor($r('app.color.color_text_hint'))
          .width('100%');
        Row() {
          Text('自建服务需要填写，可查看：')
            .fontSize(12)
            .fontColor($r('app.color.color_text_hint'));
          // 点击跳转部署文档（内嵌 WebView，定位到 client_token 说明）
          Text('部署文档')
            .fontSize(12)
            .fontColor($r('app.color.color_brand'))
            .onClick(() => {
              this.openDocs();
            });
        }
        .width('100%');
      }
      .width('100%');

      // 密码样式输入框：全程掩码显示，无查看明文入口（与密码体验一致）
      TextInput({ placeholder: '粘贴 client token', text: this.inputToken })
        .type(InputType.Password)
        .width('100%')
        .height(42)
        .backgroundColor($r('app.color.color_bg_input'))
        .borderRadius(8)
        .padding({ left: 12, right: 12 })
        .onChange((val: string) => {
          this.inputToken = val;
        });

      Row({ space: 8 }) {
        Button('取消')
          .layoutWeight(1)
          .height(40)
          .fontSize(14)
          .backgroundColor($r('app.color.color_border_subtle'))
          .fontColor($r('app.color.color_text_secondary'))
          .borderRadius(8)
          .onClick(() => {
            this.close();
          });

        Button('保存')
          .layoutWeight(1)
          .height(40)
          .fontSize(14)
          .backgroundColor($r('app.color.color_brand'))
          .borderRadius(8)
          .onClick(() => {
            this.save();
          });
      }
      .width('100%');
    }
    .width('100%')
    .padding(18)
    .backgroundColor(Color.Transparent)
    .borderRadius(14);
  }

  private close(): void {
    try {
      this.controller.close();
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'close 失败');
    }
  }

  // 跳转部署文档（内嵌 WebView）：先关弹窗，避免返回时弹窗残留
  private async openDocs(): Promise<void> {
    this.close();
    try {
      await this.getUIContext().getRouter().pushUrl({
        url: 'pages/SharePage', params: { url: DEPLOY_DOCS_URL, title: '部署文档' }
      });
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, TAG, '跳转部署文档失败：%{public}s', msg);
      showToast(this.getUIContext(), '无法打开页面');
    }
  }

  private async save(): Promise<void> {
    const token: string = this.inputToken.trim();
    const ok: boolean = await NotifyMessageService.getInstance().setClientToken(null, token);
    this.close();
    if (ok) {
      showToast(this.getUIContext(), '已保存', 1200);
      this.onSaved();
    } else {
      showToast(this.getUIContext(), '保存失败');
    }
  }
}
