// 通知页 - 展示接收到的 HTTP 推送消息列表
@Component
export struct NotifyView {
  build() {
    Column() {
      Text('通知')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .width('100%')
        .textAlign(TextAlign.Center)
        .padding(16)
        .backgroundColor($r('app.color.index_page_top_background'))
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.index_page_body_background'))
  }
}
