import { CodeBlock } from '../../common/CodeBlock';

@Component
export struct SampleCode {
  bashCode: string = `seg1=$(echo -n "[订阅通知] 及时通知推送" | jq -Rr @uri)
seg2=$(echo -n "这是一条测试通知，收到即表示订阅推送链路 工作正常" | jq -Rr @uri)
url="http://192.168.0.202:18080/\${seg1}/\${seg2}?icon=https%3A%2F%2Fstatic.wallleap.cn%2Ftemp%2Fnwvgnm7l2on5u6c531mo.jpg&group=example&ttl=600"
curl "$url"`;

  build() {
    Column() {
      Row({ space: 6 }) {
        Row({ space: 6 }) {
          Image($r('app.media.notice_colorful'))
            .width(32)
            .height(32)
            .objectFit(ImageFit.Contain)
            .draggable(false);

          Text('通知测试')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.color_text_primary'));
        }

        Row({ space: 2 }) {
          Text('切换服务')
            .fontSize('14')
          Image($r('app.media.select_more'))
            .width('18')
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.SpaceBetween)

      // 代码块
      Stack({ alignContent: Alignment.TopStart }) {
        CodeBlock({
          code: this.bashCode,
          lang: "bash",
          paddingTop: 42,
          paddingBottom: 8
        })
          .width('100%')

        Row() {
          Row({ space: 12 }) {
            Text('GET')
              .fontFamily("monospace")
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.color_text_primary'))
              .fontSize(12)
            Text('POST')
              .fontFamily("monospace")
              .fontWeight(FontWeight.Regular)
              .fontColor($r('app.color.color_text_secondary'))
              .fontSize(12)
          }

          Row() {
            Image($r('app.media.copy'))
              .width(14)
          }
        }
        .width('100%')
        .padding(10)
        .borderRadius({ topLeft: 8, topRight: 8 })
        .backgroundColor($r('app.color.color_bg_page'))
        .alignItems(VerticalAlign.Center)
        .justifyContent(FlexAlign.SpaceBetween)
      }.margin({ top: 12 })
    }
    .padding(16)
    .borderRadius(10)
    .backgroundColor($r('app.color.color_bg_surface'))
  }
}
