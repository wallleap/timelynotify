/** 通知列表的引导、加载、错误与空状态视图。 */
@Component
export struct NotifyContentState {
  @Prop mode: string = 'empty';
  @Prop errorMsg: string = '';
  onRetry: () => void = () => {};

  build() {
    Column({ space: 12 }) {
      if (this.mode === 'guide') {
        Text('未配置客户端 Token').fontSize(16).fontColor($r('app.color.text_tertiary_color'));
        Text('查询历史消息需要客户端 Token 认证，请到「我的」页面配置').fontSize(13)
          .fontColor($r('app.color.text_quinary_color')).textAlign(TextAlign.Center).width('70%');
      } else if (this.mode === 'loading') {
        LoadingProgress().width(40).height(40).color($r('app.color.text_accent_color'));
        Text('加载中…').fontSize(13).fontColor($r('app.color.text_quinary_color'));
      } else if (this.mode === 'error') {
        Text(this.errorMsg).fontSize(14).fontColor($r('app.color.text_error_color')).textAlign(TextAlign.Center).width('80%');
        Text('下拉重试').fontSize(13).fontColor($r('app.color.text_accent_color')).padding(8).onClick(() => this.onRetry());
      } else {
        Text('暂无消息').fontSize(15).fontColor($r('app.color.text_quinary_color'));
      }
    }
    .width('100%').height('100%').justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center);
  }
}
