import { hilog } from '@kit.PerformanceAnalysisKit';
import { DOMAIN } from '../common/Constant';
import { ServerSettingsContent } from './ServerSettingsContent';

const TAG: string = 'ServerDlg';

// 空 builder 占位（用于给 controller 字段做默认值，避免 SDK 注入前的空引用崩溃）
@Builder
function emptyDialogBuilder(): void {
}

// 服务器设置弹窗（NotifyView 使用）
// 不再通过构造参数传 context：持久化所需 context 从 AppContextStore 全局取（EntryAbility.onCreate 已注入）
@CustomDialog
export struct ServerSettingsDialog {
  // controller 由 SDK 自动注入；放一个占位实例作默认值，避免"未初始化/注入未生效"NPE
  controller: CustomDialogController = new CustomDialogController({
    builder: emptyDialogBuilder(),
    autoCancel: true,
    alignment: DialogAlignment.Center,
    offset: { dx: 0, dy: 0 },
  });

  build() {
    Column({ space: 14 }) {
      Text('服务器设置')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .width('100%')
        .textAlign(TextAlign.Center);

      ServerSettingsContent({ maxListHeight: 280 });

      Text('关闭')
        .fontSize(14)
        .fontColor($r('app.color.text_quinary_color'))
        .padding(8)
        .onClick(() => {
          try {
            if (this.controller) {
              this.controller.close();
            }
          } catch (err) {
            hilog.warn(DOMAIN, TAG, 'close dialog 调用失败');
          }
        });
    }
    .padding(18)
    .backgroundColor($r('app.color.dialog_background'))
    .borderRadius(14);
  }
}
