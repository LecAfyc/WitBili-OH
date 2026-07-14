/**
 * 视频播放器控制层覆盖组件
 *
 * 半透明覆盖层，包含返回、更多、弹幕开关、播放/暂停按钮。
 * 通过回调与父页面通信，不持有播放状态。
 */

@Component
export struct VideoPlayerControls {
  @Prop isPlaying: boolean = false;
  @Prop danmakuEnabled: boolean = false;
  onBack: () => void = (): void => {};
  onMore: () => void = (): void => {};
  onToggleDanmaku: () => void = (): void => {};
  onTogglePlayPause: () => void = (): void => {};
  onHideControls: () => void = (): void => {};

  build() {
    Column() {
      Row() {
        Button() {
          Text('←').fontSize(22).fontColor(Color.White)
        }
        .width(44)
        .height(44)
        .backgroundColor('rgba(0,0,0,0.45)')
        .borderRadius(22)
        .onClick(() => {
          this.onBack();
        })

        Blank()
      }
      .width('100%')
      .padding({ left: 16, top: 56 })

      Blank()

      Row() {
        Button() {
          Column() {
            Text("∷")
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(Color.White)
            Text("更多")
              .fontSize(7)
              .fontColor(Color.White)
              .margin({ top: 8 })
          }
        }
        .width(56)
        .height(56)
        .backgroundColor('rgba(0,0,0,0.45)')
        .borderRadius(28)
        .onClick(() => {
          this.onMore();
        })

        Blank()

        Button() {
          Column() {
            SymbolGlyph($r("sys.symbol.sort"))
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor([this.danmakuEnabled ? '#FF69B4' : Color.White])
            Text(this.danmakuEnabled ? '弹幕开' : '弹幕关')
              .fontSize(7)
              .fontColor(this.danmakuEnabled ? '#FF69B4' : Color.White)
              .margin({ top: 8 })
          }
        }
        .width(56)
        .height(56)
        .backgroundColor(
          this.danmakuEnabled ? 'rgba(255,105,180,0.30)' : 'rgba(0,0,0,0.45)'
        )
        .borderRadius(28)
        .onClick(() => {
          this.onToggleDanmaku();
        })
      }
      .width('100%')
      .padding({ left: 24, right: 24 })

      Blank()

      Row() {
        Blank()
        Button() {
          SymbolGlyph(
            this.isPlaying ? $r("sys.symbol.pause_round_triangle_fill") : $r("sys.symbol.play_circle_fill"))
            .fontSize(20).fontColor([Color.White])
        }
        .width(64)
        .height(64)
        .backgroundColor('rgba(0,0,0,0.45)')
        .borderRadius(32)
        .onClick(() => {
          this.onTogglePlayPause();
        })

        Blank()
      }
      .width('100%')
      .padding({ bottom: 56 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('rgba(0,0,0,0.30)')
    .onClick(() => {
      this.onHideControls();
    })
  }
}
