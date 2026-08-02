/**
 * 视频播放器「更多」面板内容组件
 *
 * 包含进度调整、倍速选择、音量/亮度调节、清晰度切换、时间/电量信息。
 * 通过 @Prop 接收状态，通过回调通知父页面操作。
 */

import { VideoQuality } from '../api/VideoDetailApi';
import { formatTime, getBatteryIcon } from '../utils/VideoPlayerUtils';
import { LengthMetrics } from '@kit.ArkUI';

@Component
export struct VideoPlayerMoreSheetContent {
  @Prop currentProgress: number = 0;
  @Prop totalDuration: number = 0;
  @Prop isSeekLoading: boolean = false;
  @Prop currentSpeed: number = 1.0;
  @Prop currentVolume: number = 0.8;
  @Prop currentBrightness: number = 0.5;
  @Prop availableQualities: VideoQuality[] = [];
  @Prop currentQn: number = 80;
  @Prop currentTimeDisplay: string = '';
  @Prop batteryLevel: number = 100;
  onSeek: (value: number) => void = (_v: number): void => {};
  onSeekStart: () => void = (): void => {};
  onSpeedChange: (speed: number) => void = (_s: number): void => {};
  onVolumeChange: (value: number) => void = (_v: number): void => {};
  onBrightnessChange: (value: number) => void = (_v: number): void => {};
  onQualitySwitch: (qn: number) => void = (_q: number): void => {};

  build() {
    Column() {
      List({ space: 14 }) {
        ListItem() {
          Column().height('4%')
        }

        ListItem() {
          this.ProgressSection()
        }

        ListItem() {
          this.SpeedSection()
        }

        ListItem() {
          this.VolumeBrightnessSection()
        }

        ListItem() {
          this.QualitySection()
        }

        ListItem() {
          this.InfoSection()
        }

        ListItem() {
          Column().height('8%')
        }
      }
      .width('100%')
      .height(LengthMetrics.px(418))
      .fadingEdge(true, { fadingEdgeLength: LengthMetrics.vp(10) })
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .focusable(true)
      .focusOnTouch(true)
      .defaultFocus(true)
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16, bottom: 24 })
  }

  @Builder
  ProgressSection() {
    Column({ space: 2 }) {
      Row() {
        Text(formatTime(this.currentProgress) + " / " + formatTime(this.totalDuration))
          .fontSize(13).fontColor(Color.White).textAlign(TextAlign.Start)
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)

      Stack() {
        Row() {
          Slider({
            value: this.currentProgress,
            min: 0,
            max: this.totalDuration > 0 ? this.totalDuration : 1,
            step: 100,
            style: SliderStyle.OutSet
          })
            .trackColor('#555555')
            .selectedColor('#FF69B4')
            .blockColor(Color.White)
            .layoutWeight(1)
            .onChange((value: number, mode: SliderChangeMode) => {
              if (mode === SliderChangeMode.Moving) {
                this.onSeekStart();
              } else {
                this.onSeek(value);
              }
            })
        }
        .width('100%')

        if (this.isSeekLoading) {
          Row({ space: 6 }) {
            LoadingProgress().width(14).height(14).color(Color.White)
            Text('跳转中...').fontSize(11).fontColor('#AAAAAA')
          }
          .backgroundColor('rgba(0,0,0,0.6)')
          .borderRadius(8)
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .justifyContent(FlexAlign.Center)
        }
      }
      .width('100%')
      .alignContent(Alignment.Center)
    }
    .width('100%')
    .padding({
      top: 10,
      bottom: 10,
      left: 8,
      right: 8
    })
    .backgroundColor('#bf2c2c2e')
    .borderRadius(12)
  }

  @Builder
  SpeedSection() {
    Column({ space: 8 }) {
      Text('播放倍速').fontSize(15).fontColor('#CCCCCC').width('100%')
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0], (speed: number) => {
          Button(speed + 'x')
            .fontSize(12)
            .fontColor(speed === this.currentSpeed ? Color.White : '#CCCCCC')
            .backgroundColor(
              speed === this.currentSpeed ? '#FF69B4' : '#333333'
            )
            .borderRadius(16)
            .height(32)
            .padding({ left: 14, right: 14 })
            .margin(1)
            .onClick(() => {
              this.onSpeedChange(speed);
            })
        })
      }
      .width('100%')
    }
    .width('100%')
    .padding({
      top: 10,
      bottom: 10,
      left: 8,
      right: 8
    })
    .backgroundColor('#bf2c2c2e')
    .borderRadius(12)
  }

  @Builder
  VolumeBrightnessSection() {
    Column({ space: 12 }) {
      Row({ space: 12 }) {
        SymbolGlyph($r("sys.symbol.speaker_wave_2"))
          .fontSize(18)
          .fontColor(['#AAAAAA'])
        Slider({
          value: this.currentVolume * 100,
          min: 0,
          max: 100,
          step: 1,
          style: SliderStyle.OutSet
        })
          .trackColor('#555555')
          .selectedColor('#FF69B4')
          .blockColor(Color.White)
          .layoutWeight(1)
          .onChange((value: number) => {
            this.onVolumeChange(value / 100);
          })
        Text(Math.round(this.currentVolume * 100) + '%')
          .fontSize(12).fontColor('#AAAAAA').width(36).textAlign(TextAlign.End)
      }
      .width('100%')

      Row({ space: 12 }) {
        SymbolGlyph($r("sys.symbol.sun_max"))
          .fontSize(18)
          .fontColor(['#AAAAAA'])
        Slider({
          value: this.currentBrightness * 100,
          min: 0,
          max: 100,
          step: 1,
          style: SliderStyle.OutSet
        })
          .trackColor('#555555')
          .selectedColor('#FF69B4')
          .blockColor(Color.White)
          .layoutWeight(1)
          .onChange((value: number) => {
            this.onBrightnessChange(value / 100);
          })
        Text(Math.round(this.currentBrightness * 100) + '%')
          .fontSize(12).fontColor('#AAAAAA').width(36).textAlign(TextAlign.End)
      }
      .width('100%')
    }
    .width('100%')
    .padding({
      top: 10,
      bottom: 10,
      left: 8,
      right: 8
    })
    .backgroundColor('#bf2c2c2e')
    .borderRadius(12)
  }

  @Builder
  QualitySection() {
    Column({ space: 8 }) {
      Text('清晰度').fontSize(15).fontColor('#CCCCCC').width('100%')
      if (this.availableQualities.length > 0) {
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.availableQualities, (item: VideoQuality) => {
            Button(item.name)
              .fontSize(12)
              .fontColor(item.qn === this.currentQn ? Color.White : '#CCCCCC')
              .backgroundColor(
                item.qn === this.currentQn ? '#FF69B4' : '#333333'
              )
              .borderRadius(16)
              .height(32)
              .padding({ left: 14, right: 14 })
              .margin(1)
              .onClick(() => {
                this.onQualitySwitch(item.qn);
              })
          }, (item: VideoQuality) => String(item.qn))
        }
        .width('100%')
      } else {
        Text('加载中...').fontSize(12).fontColor('#888888')
      }
    }
    .width('100%')
    .padding({ top: 10, bottom: 10, left: 8, right: 8 })
    .backgroundColor('#bf2c2c2e')
    .borderRadius(12)
  }

  @Builder
  InfoSection() {
    Row() {
      Column({ space: 4 }) {
        Text('当前时间').fontSize(11).fontColor('#888888')
        Text(this.currentTimeDisplay)
          .fontSize(22).fontWeight(FontWeight.Bold).fontColor(Color.White)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Column({ space: 4 }) {
        Text('电池电量').fontSize(11).fontColor('#888888')
        Row({ space: 6 }) {
          Text(this.batteryLevel >= 0 ? this.batteryLevel + '%' : '--')
            .fontSize(22).fontWeight(FontWeight.Bold)
            .fontColor(this.batteryLevel > 20 ? Color.White : '#FF4444')
          if (this.batteryLevel >= 0) {
            SymbolGlyph(getBatteryIcon(this.batteryLevel))
              .fontSize(18)
              .fontColor([this.batteryLevel > 20 ? '#34C759' : '#FF4444'])
          }
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.End)
    }
    .width('100%')
    .padding(16)
    .backgroundColor('#bf2c2c2e')
    .borderRadius(12)
  }
}
