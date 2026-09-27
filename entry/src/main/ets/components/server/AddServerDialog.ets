import { hilog } from '@kit.PerformanceAnalysisKit';
import { ServerEntry } from '../../model/ServerEntry';
import { ServerManager } from '../../services/ServerManager';
import showToast from '../showToast';
import { DOMAIN } from '../../common/Constant';

const TAG: string = 'AddServerDlg';

@Builder
function emptyBuilder(): void {
}

// 添加服务器弹窗：URL + 名称 + 客户端 Token，校验后调用 ServerManager.addServer
@CustomDialog
export struct AddServerDialog {
  controller: CustomDialogController = new CustomDialogController({
    builder: emptyBuilder(),
    autoCancel: true,
    alignment: DialogAlignment.Center,
    offset: { dx: 0, dy: 0 },
  });
  @State inputURL: string = '';
  @State inputName: string = '';
  @State inputToken: string = '';
  @State adding: boolean = false;
  // 添加成功回调（可选，用于外层刷新等）
  onAdded: (entry: ServerEntry | null) => void = (_e: ServerEntry | null) => {
  };

  // 带标题标签的输入项
  @Builder
  labeledInput(label: string, placeholder: string, value: string, onChanged: (v: string) => void) {
    Column({ space: 6 }) {
      Text(label)
        .fontSize(13)
        .fontColor($r('app.color.color_text_secondary'))
        .width('100%');

      TextInput({ placeholder: placeholder, text: value })
        .width('100%')
        .height(42)
        .backgroundColor($r('app.color.color_bg_input_glass'))
        .borderRadius(8)
        .padding({ left: 12, right: 12 })
        .enabled(!this.adding)
        .onChange((val: string) => {
          onChanged(val);
        });
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start);
  }

  build() {
    Column({ space: 12 }) {
      Text('添加服务器')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .width('100%')
        .textAlign(TextAlign.Center);

      // 表单内容区：可滚动，底部按钮固定在 Scroll 外
      Scroll() {
        Column({ space: 12 }) {
          this.labeledInput('服务器地址', 'http://host:port 或域名', this.inputURL,
            (v: string) => { this.inputURL = v; });

          this.labeledInput('名称（可选）', '输入服务器名称', this.inputName,
            (v: string) => { this.inputName = v; });

          this.labeledInput('客户端 Token（可选）', '留空使用内置默认 Token', this.inputToken,
            (v: string) => { this.inputToken = v; });
        }
        .width('100%');
      }
      .width('100%')
      .constraintSize({ maxHeight: '60%' })
      .scrollBar(BarState.Auto)
      .edgeEffect(EdgeEffect.Spring);

      Row({ space: 8 }) {
        Button('取消')
          .layoutWeight(1)
          .height(40)
          .fontSize(14)
          .backgroundColor(Color.Transparent)
          .fontColor($r('app.color.color_text_secondary'))
          .borderRadius(8)
          .enabled(!this.adding)
          .onClick(() => {
            this.close();
          });

        Button(this.adding ? '添加中...' : '添加')
          .layoutWeight(1)
          .height(40)
          .fontSize(14)
          .backgroundColor($r('app.color.color_brand'))
          .borderRadius(8)
          .enabled(!this.adding)
          .onClick(() => {
            this.confirm();
          });
      }
      .width('100%');
    }
    .padding(18)
    .backgroundColor(Color.Transparent)
    .borderRadius(14);
  }

  private close(): void {
    try {
      this.controller.close();
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'close add server 失败');
    }
  }

  private async confirm(): Promise<void> {
    const url: string = this.inputURL.trim();
    if (!url) {
      showToast(this.getUIContext(), '请输入服务器地址');
      return;
    }
    this.adding = true;
    const mgr: ServerManager = ServerManager.getInstance();
    const errMsg: string = await mgr.validateAndPing(url);
    if (errMsg.length > 0) {
      showToast(this.getUIContext(), errMsg);
      this.adding = false;
      return;
    }
    const entry: ServerEntry | null = await mgr.addServer(null, url, this.inputName.trim());
    // addServer 成功后当前服务器已切换为新条目，若用户填写了 Token 则写入
    if (entry) {
      const token: string = this.inputToken.trim();
      if (token.length > 0) {
        await mgr.updateServerClientToken(null, entry.id, token);
      }
    }
    this.adding = false;
    if (entry) {
      showToast(this.getUIContext(), '已添加并切换', 1200);
      this.close();
      this.onAdded(entry);
    } else {
      showToast(this.getUIContext(), '添加失败');
    }
  }
}
