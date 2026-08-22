// 我的页 - 展示个人设置入口
@Component
export struct MineView {
  build() {
    Column() {
      Text('我的')
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
