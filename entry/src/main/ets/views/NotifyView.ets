import { ApiConfig } from '../config/ApiConfig';

// 从完整 URL 中提取 host（去掉 protocol://、路径、查询参数）
// 例如 http://192.168.0.202:18080/path -> 192.168.0.202:18080
function extractHost(url: string): string {
  let s: string = url;
  const protocolEnd: number = s.indexOf('://');
  if (protocolEnd >= 0) {
    s = s.substring(protocolEnd + 3);
  }
  const slashIdx: number = s.indexOf('/');
  if (slashIdx >= 0) {
    s = s.substring(0, slashIdx);
  }
  return s;
}

// 通知页 - 展示接收到的 HTTP 推送消息列表
@Component
export struct NotifyView {
  title: string = extractHost(ApiConfig.baseURL);

  build() {
    Column() {
      // 顶部栏：左侧 server 域名
      Row() {
        Text(this.title)
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .layoutWeight(1)
          .textAlign(TextAlign.Start);
      }
      .width('100%')
      .padding(16)
      .alignItems(VerticalAlign.Center)
      .backgroundColor($r('app.color.index_page_top_background'));

      // 内容区域（待填充消息列表）
      Column() {
        Blank();
      }
      .layoutWeight(1)
      .width('100%');
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.index_page_body_background'));
  }
}
