import { hilog } from '@kit.PerformanceAnalysisKit';
import { promptAction } from '@kit.ArkUI';
import { NotifyMessageService } from '../services/NotifyMessageService';

const DOMAIN: number = 0x0000;
const TAG: string = 'ClientTokenDlg';

function showToast(message: string, durationMs: number = 1500): void {
  try {
    promptAction.showToast({ message: message, duration: durationMs });
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    hilog.warn(DOMAIN, TAG, 'Toast 调用失败：%{public}s', msg);
  }
}

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

  // 拉取当前已保存的 token 预填
  getInitToken: () => string = () => '';
  onSaved: () => void = () => {};

  @State inputToken: string = '';

  aboutToAppear() {
    this.inputToken = this.getInitToken();
  }

  private close(): void {
    try {
      this.controller.close();
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'close 失败');
    }
  }

  private async save(): Promise<void> {
    const token: string = this.inputToken.trim();
    const ok: boolean = await NotifyMessageService.getInstance().setClientToken(null, token);
    this.close();
    if (ok) {
      showToast('已保存', 1200);
      this.onSaved();
    } else {
      showToast('保存失败');
    }
  }

  build() {
    Column({ space: 12 }) {
      Text('客户端 Token')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .width('100%')
        .textAlign(TextAlign.Center);

      Column({ space: 4 }) {
        Text('用于查询历史消息（X-Gotify-Key 认证）')
          .fontSize(12)
          .fontColor('#999999')
          .width('100%');
        Text('在服务端为该设备创建 Client 后获取')
          .fontSize(12)
          .fontColor('#999999')
          .width('100%');
      }
      .width('100%');

      TextInput({ placeholder: '粘贴 client token', text: this.inputToken })
        .width('100%')
        .height(42)
        .backgroundColor('#F5F5F5')
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
          .backgroundColor('#EEEEEE')
          .fontColor('#333333')
          .borderRadius(8)
          .onClick(() => {
            this.close();
          });

        Button('保存')
          .layoutWeight(1)
          .height(40)
          .fontSize(14)
          .backgroundColor('#FF6F22')
          .borderRadius(8)
          .onClick(() => {
            this.save();
          });
      }
      .width('100%');
    }
    .width('80%')
    .padding(18)
    .backgroundColor('#FFFFFF')
    .borderRadius(14);
  }
}
