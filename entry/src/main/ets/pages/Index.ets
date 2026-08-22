@Entry
@Component
struct Index {
  @State topSafeAreaArr: Array<SafeAreaEdge> = [SafeAreaEdge.TOP];
  @State bottomSafeAreaArr: Array<SafeAreaEdge> = [SafeAreaEdge.BOTTOM];

  build() {
    Column() {
      Row() {
        Text('顶部内容区域').fontSize(40).textAlign(TextAlign.Center).width('100%');
      }
      .backgroundColor($r('app.color.start_window_background'))
      // 设置顶部绘制延伸到状态栏
      .expandSafeArea([SafeAreaType.SYSTEM], this.topSafeAreaArr)

      Column({ space: 30 }) {
        Row({ space: 30 }) {
          if (this.topSafeAreaArr.length > 0) {
            Text('避让状态栏：否');
          } else {
            Text('避让状态栏：是');
          }
          Toggle({ type: ToggleType.Switch })
            .scale({ x: 2, y: 2 })
            .onChange((isOn: boolean) => {
              if (isOn) {
                this.topSafeAreaArr = [SafeAreaEdge.TOP];
              } else {
                this.topSafeAreaArr = [];
              }
            });
        };

        Row({ space: 30 }) {
          if (this.bottomSafeAreaArr.length > 0) {
            Text('避让导航条：否');
          } else {
            Text('避让导航条：是');
          }
          Toggle({ type: ToggleType.Switch })
            .scale({ x: 2, y: 2 })
            .onChange((isOn: boolean) => {
              if (isOn) {
                this.bottomSafeAreaArr = [SafeAreaEdge.BOTTOM];
              } else {
                this.bottomSafeAreaArr = [];
              }
            });
        };
      };

      Row() {
        Text('底部内容区域').fontSize(40).textAlign(TextAlign.Center).width('100%');
      }
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Center)
    .backgroundColor($r('app.color.start_window_background'))
    .justifyContent(FlexAlign.SpaceBetween)
    // 设置底部绘制延伸到导航区域
    .expandSafeArea([SafeAreaType.SYSTEM], this.bottomSafeAreaArr);
  }
}
