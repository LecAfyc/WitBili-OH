/**
 * 视频播放页面
 *
 * 支持 DASH（IJKPlayer 视频 + DashAudioRenderer 音频分离渲染）
 * 和 MP4（IJKPlayer 一体渲染）两种模式。
 *
 * 导航参数：{ videoCard, cid, qn }
 */

import {
  IjkMediaPlayer,
  OnPreparedListener,
  OnErrorListener,
  OnCompletionListener,
  OnVideoSizeChangedListener,
  OnBufferingUpdateListener,
  OnSeekCompleteListener,
  OnInfoListener
} from '@ohos/ijkplayer';
import { common } from '@kit.AbilityKit';
import { VideoCard } from '../model/ContentCard';
import { getDashPlayUrl, DashPlayUrlResult } from '../api/VideoStreamApi';
import { reportWatchProgress } from '../api/HistoryApi';
import { DashAudioRenderer, AudioRenderState } from '../api/DashAudioRenderer';
import { getCookieString } from '../api/CookiesApi';
import { HEADERS } from '../api/CommonApi';
import { BarrageView, BarrageController, BarrageItem, BarrageOption } from '@esky/barrage';
import { getDanmakuItems, DanmakuData, createBarrageItem } from '../api/DanmakuApi';
import { VideoQuality } from '../api/VideoDetailApi';
import batteryInfo from '@ohos.batteryInfo';
import vibrator from '@ohos.vibrator';
import { audio as harmoniousAudio } from '@kit.AudioKit';
import { LengthMetrics, window } from '@kit.ArkUI';

@Component
export struct VideoPlayerPage {
  @Consume('pageStack') pageStack: NavPathStack;
  // ===== 导航参数 =====
  @State videoCard: VideoCard | null = null;
  @State cid: number = 0;
  @State qn: number = 80;
  // ===== 播放器状态 =====
  @State videoUrl: string = '';
  @State audioUrl: string = '';
  @State isDashStream: boolean = false;
  @State isLoading: boolean = true;
  @State errorMsg: string = '';
  @State isPlaying: boolean = false;
  // ===== 音频 =====
  @State stateText: string = '';
  // ===== 手势缩放与拖拽 =====
  @State curScale: number = 1.0;
  @State curOffsetX: number = 0;
  @State curOffsetY: number = 0;
  @State containerWidth: number = 0;
  @State containerHeight: number = 0;
  @State private baseWidth: number = 0;
  @State private baseHeight: number = 0;
  // ===== 弹幕 =====
  private barrageController: BarrageController = new BarrageController();
  @State barrageReady: boolean = false;
  // ===== UI 控制 =====
  @State showControls: boolean = false;
  @State showMoreSheet: boolean = false;
  @State currentSpeed: number = 1.0;
  @State currentProgress: number = 0;
  @State isSeeking: boolean = false;
  @State isSeekLoading: boolean = false;
  @State isBuffering: boolean = false;
  @State totalDuration: number = 0;
  @State wasPlayingBeforeSheet: boolean = false;
  @State danmakuEnabled: boolean = false;
  @State currentVolume: number = 0.8;
  @State currentBrightness: number = 0.5;
  @State batteryLevel: number = 100;
  @State currentTimeDisplay: string = '';
  @State availableQualities: VideoQuality[] = [];
  @State currentQnName: string = '';
  // ===== 视频尺寸 =====
  @State private videoWidth: number = 16;
  @State private videoHeight: number = 9;
  private audioRenderer: DashAudioRenderer | null = null;
  private audioInitStarted: boolean = false;
  private syncTimerId: number | undefined = undefined;
  private lastAudioSeekMs: number = 0;
  private readonly MIN_SCALE: number = 0.5;
  private readonly MAX_SCALE: number = 3.0;
  private maxOffsetX: number = 0;
  private minOffsetX: number = 0;
  private maxOffsetY: number = 0;
  private minOffsetY: number = 0;
  private saveScale: number = 1.0;
  private saveOffsetX: number = 0;
  private saveOffsetY: number = 0;
  private speedBeforeLongPress: number = 1.0;
  // ===== IJKPlayer =====
  private mIjkMediaPlayer = IjkMediaPlayer.getInstance();
  private mContext: object | undefined = undefined;
  private readonly XCOMPONENT_ID: string = 'xcomponentId';
  private xcController: XComponentController = new XComponentController();
  private danmakuDataList: Array<DanmakuData> = [];
  private danmakuIndex: number = 0;
  private danmakuTimer: number | undefined = undefined;
  private lastCheckedPosition: number = 0;
  // ===== 历史记录上报 =====
  private reportTimerId: number | undefined = undefined;
  private readonly REPORT_INTERVAL_MS: number = 15000;
  private controlsTimerId: number | undefined = undefined;
  private moreProgressTimerId: number | undefined = undefined;
  private timeTickTimerId: number | undefined = undefined;

  pause(): void {
    try {
      this.mIjkMediaPlayer.pause();
    } catch (_e) { /* ignore */
    }
    if (this.isDashStream && this.audioRenderer) {
      this.audioRenderer.pause();
    }
    this.isPlaying = false;
    this.barrageController.pause()
  }

  resume(seekMs?: number): void {
    try {
      if (seekMs !== undefined) {
        this.mIjkMediaPlayer.seekTo(String(Math.round(seekMs)));
      }
      this.mIjkMediaPlayer.start();
    } catch (_e) { /* ignore */
    }
    if (this.isDashStream && this.audioRenderer && !this.isBuffering) {
      if (seekMs !== undefined) {
        this.audioRenderer.seekTo(seekMs);
      }
      this.audioRenderer.play();
    }
    this.isPlaying = true;
    if (seekMs !== undefined) {
      this.danmakuIndex = 0;
    }
    if (this.danmakuEnabled) {
      this.barrageController.start();
    }
    if (this.danmakuTimer === undefined) {
      this.startDanmakuTimer();
    }
  }

  togglePlayPause(): void {
    if (this.isPlaying) {
      this.pause();
    } else {
      this.resume();
    }
  }

  seekTo(positionMs: number): void {
    let pos: number = Math.round(Math.max(0, positionMs));
    this.isSeekLoading = true;
    setTimeout(() => {
      this.isSeekLoading = false;
    }, 3000);
    try {
      this.mIjkMediaPlayer.seekTo(String(pos));
    } catch (_e) {
      this.isSeekLoading = false;
    }
    if (this.isDashStream && this.audioRenderer) {
      this.audioRenderer.seekTo(pos);
    }
    this.danmakuIndex = 0;
    this.lastCheckedPosition = pos / 1000;
  }

  setSpeed(speed: number): void {
    speed = Math.max(0.5, Math.min(3.0, speed));
    try {
      this.mIjkMediaPlayer.setOption('4', 'playback-rate', String(speed));
    } catch (_e) { /* ignore */
    }
    if (this.isDashStream && this.audioRenderer) {
      this.audioRenderer.setSpeed(speed);
    }
  }

  // ===================================================================
  //  生命周期
  // ===================================================================

  aboutToDisappear(): void {
    this.releasePlayer();
    this.releaseAudio();
    this.stopDanmakuTimer();
    this.stopSyncTimer();
    this.clearControlsTimer();
    this.clearMoreProgressTimer();
  }

  build() {
    NavDestination() {
      Stack() {
        // ── 内层：视频内容 + 弹幕 + 原有手势 ──
        Stack() {
          if (this.isLoading) {
            LoadingProgress().width(40).height(40).align(Alignment.Center)
          } else if (this.errorMsg) {
            Text(this.errorMsg).fontSize(16).fontColor(Color.Red).textAlign(TextAlign.Center)
          } else {
            XComponent({
              id: this.XCOMPONENT_ID,
              type: XComponentType.SURFACE,
              controller: this.xcController,
              libraryname: 'ijkplayer_napi'
            })
              .onLoad((context: object) => {
                this.mContext = context;
                this.startPlay();
              })
              .onDestroy(() => {
                this.releasePlayer();
              })
              .width(this.baseWidth * this.curScale)
              .height(this.baseHeight * this.curScale)
              .translate({ x: this.curOffsetX, y: this.curOffsetY })

            if (this.isBuffering) {
              Column() {
                LoadingProgress().width(40).height(40).color(Color.White)
                Text('加载中')
                  .fontSize(12)
                  .fontColor(Color.White)
                  .margin({ top: 8 })
              }
              .justifyContent(FlexAlign.Center)
              .backgroundColor('rgba(0,0,0,0.3)')
              .borderRadius(12)
              .padding(16)
            }

            if (this.stateText) {
              Row() {
                Text(this.stateText)
                  .fontSize(12)
                  .fontColor('#AAAAAA')
                  .padding({
                    left: 8,
                    right: 8,
                    top: 4,
                    bottom: 4
                  })
                  .backgroundColor('rgba(0,0,0,0.5)')
                  .borderRadius(8)
              }
              .position({ x: 0, y: 8 })
              .justifyContent(FlexAlign.Center)
              .width('100%')
            }

            if (this.barrageReady && this.danmakuEnabled) {
              BarrageView({
                barrageController: this.barrageController,
                option: {
                  maxLine: 6,
                  speed: 1.5,
                  textAlpha: 0.7,
                  isShowFPS: false
                } as BarrageOption,
                onCanvasReady: () => {
                  this.barrageController.start();
                },
                onTouchBarrage: (item: BarrageItem) => {
                  console.info('[VideoPlayerPage] 点击弹幕: ' + item.text);
                }
              }).width('100%').height('100%')
            }
          }
        }
        .width('100%').height('100%')
        .clip(true)
        .align(Alignment.Center)
        .onAreaChange((_: Area, newValue: Area) => {
          this.containerWidth = newValue.width as number;
          this.containerHeight = newValue.height as number;
          this.calcBaseSize();
          this.calcBoundary();
        })
        .gesture(
          GestureGroup(GestureMode.Exclusive,
            TapGesture({ count: 2 }).onAction(() => {
              this.onDoubleTap();
            }),
            PinchGesture()
              .onActionStart(() => {
                this.onPinchStart();
              })
              .onActionUpdate((e) => {
                this.onPinchUpdate(e);
              })
              .onActionEnd(() => {
                this.onPinchEnd();
              }),
            PanGesture({ fingers: 1, distance: 3 })
              .onActionStart(() => {
                this.onPanStart();
              })
              .onActionUpdate((e) => {
                this.onPanUpdate(e);
              })
              .onActionEnd(() => {
                this.onPanEnd();
              }),
            LongPressGesture({ duration: 500 })
              .onAction(() => {
                this.onLongPressStart();
              })
              .onActionEnd(() => {
                this.onLongPressEnd();
              })
          )
        )
        .focusable(true)
        .focusOnTouch(true)
        .defaultFocus(!this.showMoreSheet)
        .onDigitalCrown((event: CrownEvent) => {
          event.stopPropagation();
          this.onDigitalCrownAction(event);
        })

        // ── Controls 覆盖层（点击任意位置显示 5 秒后自动隐藏） ──
        Column() {
          // 顶部：返回按钮（左）
          Row() {
            Button() {
              Text('←').fontSize(22).fontColor(Color.White)
            }
            .width(44)
            .height(44)
            .backgroundColor('rgba(0,0,0,0.45)')
            .borderRadius(22)
            .onClick(() => {
              this.clearControlsTimer();
              this.pageStack.pop();
            })

            Blank()
          }
          .width('100%')
          .padding({ left: 16, top: 56 })

          Blank()

          // 中间行：左侧「更多」+ 右侧「弹幕」
          Row() {
            // 更多按钮
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
              this.clearControlsTimer();
              this.openMoreSheet();
            })

            Blank()

            // 弹幕开关
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
              this.toggleDanmaku();
            })
          }
          .width('100%')
          .padding({ left: 24, right: 24 })

          Blank()

          // 底部：暂停 / 继续
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
              this.togglePlayPause();
              this.clearControlsTimer();
              this.showControlsWithTimer();
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
          this.hideControls();
        })
        .visibility(this.showControls ? Visibility.Visible : Visibility.Hidden)
        .animation({ duration: 300, curve: Curve.EaseOut })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Color.Black)
      .gesture(
        TapGesture({ count: 1 }).onAction(() => {
          this.onSingleTap();
        })
      )
      .bindSheet($$this.showMoreSheet, this.MoreSheet(), {
        detents: [SheetSize.MEDIUM,SheetSize.LARGE],
        backgroundColor: 'rgba(28,28,30,0.45)',
        blurStyle: BlurStyle.BACKGROUND_THIN,
        onDisappear: () => {
          this.clearMoreProgressTimer();
          this.clearTimeTickTimer();
          if (this.wasPlayingBeforeSheet) {
            this.resume();
          }
        }
      })
    }
    .hideBackButton(true).hideTitleBar(true)
    .onReady((context: NavDestinationContext) => {
      let param = context.pathInfo.param as Record<string, Object>;
      if (param) {
        this.videoCard = param['videoCard'] as VideoCard;
        this.cid = param['cid'] as number;
        if (param['qn'] !== undefined) {
          this.qn = param['qn'] as number;
        }
      }
      if (this.videoCard && this.cid > 0) {
        this.fetchPlayUrl();
      } else {
        this.errorMsg = '参数错误';
        this.isLoading = false;
      }
    })
  }

  // ===================================================================
  //  播放地址获取
  // ===================================================================

  getVideoPosition(): number {
    try {
      return this.mIjkMediaPlayer.getCurrentPosition();
    } catch (_e) {
      return -1;
    }
  }

  // ===================================================================
  //  DASH 音频渲染
  // ===================================================================

  getCurrentPosition(): number {
    if (this.isDashStream && this.audioRenderer) {
      let audioPos = this.audioRenderer.getCurrentPositionMs();
      if (audioPos > 0) {
        return audioPos;
      }
    }
    return this.getVideoPosition();
  }

  getDuration(): number {
    try {
      return this.mIjkMediaPlayer.getDuration();
    } catch (_e) {
      return -1;
    }
  }

  // ===================================================================
  //  音画同步
  // ===================================================================

  toggleDanmaku(): void {
    this.danmakuEnabled = !this.danmakuEnabled;
    if (this.danmakuEnabled) {
      this.danmakuIndex = 0;
      this.lastCheckedPosition = this.getVideoPosition() / 1000;
      if (this.isPlaying) {
        this.startDanmakuTimer();
      }
    } else {
      this.stopDanmakuTimer();
    }
  }

  showControlsWithTimer(): void {
    this.doReportProgress()
    this.showControls = true;
    this.clearControlsTimer();
    this.controlsTimerId = setTimeout(() => {
      this.showControls = false;
    }, 5000);
  }

  clearControlsTimer(): void {
    if (this.controlsTimerId !== undefined) {
      clearTimeout(this.controlsTimerId);
      this.controlsTimerId = undefined;
    }
  }

  hideControls(): void {
    this.showControls = false;
    this.clearControlsTimer();
  }

  // ===================================================================
  //  工具方法
  // ===================================================================

  openMoreSheet(): void {
    this.wasPlayingBeforeSheet = this.isPlaying;
    this.pause();
    this.currentProgress = this.getCurrentPosition();
    this.totalDuration = this.getDuration();
    this.showMoreSheet = true;
    this.clearMoreProgressTimer();
    this.moreProgressTimerId = setInterval(() => {
      if (!this.isSeeking) {
        this.currentProgress = this.getCurrentPosition();
      }
    }, 500);
    this.initMoreSheetState();
    this.updateTimeDisplay();
    this.clearTimeTickTimer();
    this.timeTickTimerId = setInterval(() => {
      this.updateTimeDisplay();
    }, 60000);
  }

  clearMoreProgressTimer(): void {
    if (this.moreProgressTimerId !== undefined) {
      clearInterval(this.moreProgressTimerId);
      this.moreProgressTimerId = undefined;
    }
  }

  clearTimeTickTimer(): void {
    if (this.timeTickTimerId !== undefined) {
      clearInterval(this.timeTickTimerId);
      this.timeTickTimerId = undefined;
    }
  }

  // ===== 历史记录上报 =====

  onSingleTap(): void {
    if (this.showControls) {
      this.hideControls();
    } else {
      this.showControlsWithTimer();
    }
  }

  @Builder
  MoreSheet() {
    Column() {
      List({ space: 14 }) {
        ListItem(){
          Column().height('4%')
        }
        // ── 1. 进度调整 ──
        ListItem() {
          Column({ space: 2 }) {
            Row() {
              Text(this.formatTime(this.currentProgress) + " / " + this.formatTime(this.totalDuration))
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
                    this.currentProgress = value;
                    if (mode === SliderChangeMode.Moving) {
                      this.isSeeking = true;
                    } else {
                      this.isSeeking = false;
                      this.isSeekLoading = true;
                      this.seekTo(value);
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

        // ── 2. 倍速调整 ──
        ListItem() {
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
                    this.currentSpeed = speed;
                    this.setSpeed(speed);
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

        // ── 3. 音量 + 亮度调节 ──
        ListItem() {
          Column({ space: 12 }) {
            // 音量
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
                  this.currentVolume = value / 100;
                  try {
                    let audioManager = harmoniousAudio.getAudioManager();
                    audioManager.setVolume(
                      harmoniousAudio.AudioVolumeType.MEDIA,
                      Math.round(value / 100 * 15),
                      (_err: Error) => {
                      }
                    );
                  } catch (_e) { /* ignore */
                  }
                })
              Text(Math.round(this.currentVolume * 100) + '%')
                .fontSize(12).fontColor('#AAAAAA').width(36).textAlign(TextAlign.End)
            }
            .width('100%')

            // 亮度
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
                  this.currentBrightness = value / 100;
                  try {
                    let uiContext = AppStorage.get<common.UIAbilityContext>('UiAbilityContext');
                    if (uiContext) {
                      window.getLastWindow(uiContext).then((win: window.Window) => {
                        win.setWindowBrightness(this.currentBrightness);
                      });
                    }
                  } catch (_e) { /* ignore */
                  }
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

        // ── 3b. 清晰度选择 ──
        ListItem() {
          Column({ space: 8 }) {
            Text('清晰度').fontSize(15).fontColor('#CCCCCC').width('100%')
            if (this.availableQualities.length > 0) {
              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(this.availableQualities, (item: VideoQuality) => {
                  Button(item.name)
                    .fontSize(12)
                    .fontColor(item.qn === this.qn ? Color.White : '#CCCCCC')
                    .backgroundColor(
                      item.qn === this.qn ? '#FF69B4' : '#333333'
                    )
                    .borderRadius(16)
                    .height(32)
                    .padding({ left: 14, right: 14 })
                    .margin(1)
                    .onClick(() => {
                      this.switchQuality(item.qn);
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

        // ── 4. 信息显示（时间 + 电量） ──
        ListItem() {
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
                  SymbolGlyph(this.getBatteryIcon(this.batteryLevel))
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

        ListItem(){
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
      .defaultFocus(this.showMoreSheet)
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16, bottom: 24 })
  }

  private async fetchPlayUrl(): Promise<void> {
    try {
      let result: DashPlayUrlResult = await getDashPlayUrl(this.videoCard!.bvid, this.cid, this.qn);
      if (!result.videoUrl) {
        throw new Error('videoUrl 为空');
      }
      this.videoUrl = result.videoUrl;
      this.audioUrl = result.audioUrl;
      this.isDashStream = result.isDash;

      let qualities: VideoQuality[] = [];
      for (let i = 0; i < result.acceptDescription.length; i++) {
        qualities.push({
          name: result.acceptDescription[i],
          qn: result.acceptQuality[i] || 0
        });
      }
      this.availableQualities = qualities;
      this.currentQnName = '';
      for (let i = 0; i < qualities.length; i++) {
        if (qualities[i].qn === this.qn) {
          this.currentQnName = qualities[i].name;
          break;
        }
      }

      if (this.isDashStream && this.audioUrl) {
        this.startAudioRendering();
      }
      this.loadDanmaku();
      this.isLoading = false;
    } catch (e) {
      this.errorMsg = '获取播放地址失败: ' + (e instanceof Error ? e.message : String(e));
      this.isLoading = false;
    }
  }

  private async switchQuality(newQn: number): Promise<void> {
    if (newQn === this.qn) {
      return;
    }
    let posMs: number = this.getCurrentPosition();
    this.qn = newQn;
    for (let i = 0; i < this.availableQualities.length; i++) {
      if (this.availableQualities[i].qn === newQn) {
        this.currentQnName = this.availableQualities[i].name;
        break;
      }
    }
    this.resetPlayer();
    this.releaseAudio();
    this.stopDanmakuTimer();
    this.stopSyncTimer();
    this.isLoading = true;
    this.errorMsg = '';
    try {
      let result: DashPlayUrlResult = await getDashPlayUrl(this.videoCard!.bvid, this.cid, this.qn);
      if (!result.videoUrl) {
        throw new Error('videoUrl 为空');
      }
      this.videoUrl = result.videoUrl;
      this.audioUrl = result.audioUrl;
      this.isDashStream = result.isDash;
      this.isLoading = false;
      if (this.isDashStream && this.audioUrl) {
        this.startAudioRendering();
      }
      if (this.mContext) {
        this.startPlay();
      }
      if (posMs > 0) {
        setTimeout(() => {
          this.seekTo(posMs);
        }, 1500);
      }
    } catch (e) {
      this.errorMsg = '切换清晰度失败: ' + (e instanceof Error ? e.message : String(e));
      this.isLoading = false;
    }
  }

  private async startAudioRendering(): Promise<void> {
    if (this.audioInitStarted) {
      return;
    }
    this.audioInitStarted = true;

    try {
      let uiContext = AppStorage.get<common.UIAbilityContext>('UiAbilityContext');
      if (!uiContext) {
        this.setStateText('音频不可用');
        return;
      }

      this.audioRenderer = new DashAudioRenderer();
      this.audioRenderer.onStateChange((state: AudioRenderState) => {
        if (state === AudioRenderState.PLAYING) {
          this.setStateText('音频已同步');
        }
      });

      this.setStateText('音频加载中...');
      await this.audioRenderer.init(this.audioUrl);

      let videoPosMs: number = this.getVideoPosition();
      if (videoPosMs > 500) {
        this.audioRenderer.seekTo(videoPosMs);
      }
      this.audioRenderer.play();

      this.startSyncTimer();
      this.setStateText('音频就绪');
    } catch (e) {
      console.error('[VideoPlayerPage] 音频初始化失败: ' + String(e));
      this.setStateText('音频不可用');
    }
  }

  private setStateText(content: string): void {
    this.stateText = content;
    setTimeout(() => {
      this.stateText = '';
    }, 3000);
  }

  private startSyncTimer(): void {
    this.stopSyncTimer();
    this.syncTimerId = setInterval(() => this.syncAudioWithVideo(), 2000);
  }

  // ===================================================================
  //  IJKPlayer 播放初始化
  // ===================================================================

  private stopSyncTimer(): void {
    if (this.syncTimerId !== undefined) {
      clearInterval(this.syncTimerId);
      this.syncTimerId = undefined;
    }
  }

  // ===================================================================
  //  UI 控制按钮
  // ===================================================================

  private handleBufferingStart(): void {
    this.isBuffering = true;
    this.barrageController.pause();
    if (this.isDashStream && this.audioRenderer) {
      let audioState: AudioRenderState = this.audioRenderer.getState();
      if (audioState === AudioRenderState.PLAYING) {
        this.audioRenderer.pause();
      }
    }
  }

  private handleBufferingEnd(): void {
    this.isBuffering = false;
    if (this.danmakuEnabled && this.isPlaying) {
      this.barrageController.start();
    }
    if (this.isDashStream && this.audioRenderer && this.isPlaying) {
      let audioState: AudioRenderState = this.audioRenderer.getState();
      if (audioState === AudioRenderState.PAUSED) {
        let videoPosMs: number = this.getVideoPosition();
        if (videoPosMs > 0) {
          this.audioRenderer.seekTo(videoPosMs);
          setTimeout(() => {
            if (this.isPlaying && !this.isBuffering && this.audioRenderer) {
              this.audioRenderer.play();
            }
          }, 200);
        } else {
          this.audioRenderer.play();
        }
      }
    }
  }

  private syncAudioWithVideo(): void {
    if (!this.audioRenderer) {
      return;
    }
    let audioState: AudioRenderState = this.audioRenderer.getState();
    if (audioState === AudioRenderState.ERROR || audioState === AudioRenderState.RELEASED) {
      return;
    }
    if (this.isBuffering) {
      return;
    }

    try {
      let videoPosMs: number = this.getVideoPosition();

      if (this.isPlaying && audioState === AudioRenderState.PAUSED) {
        this.audioRenderer.play();
      } else if (!this.isPlaying && audioState === AudioRenderState.PLAYING) {
        this.audioRenderer.pause();
      }

      if (this.isPlaying && videoPosMs >= 0) {
        let elapsedSinceSeek: number = Date.now() - this.lastAudioSeekMs;
        if (elapsedSinceSeek > 3000) {
          this.audioRenderer.syncPosition(videoPosMs);
        }
      }
    } catch (_e) { /* ignore */
    }
  }

  private onAudioSeek(): void {
    this.lastAudioSeekMs = Date.now();
  }

  /** 执行单次进度上报（非异步，HTTP 请求做 fire-and-forget） */
  private doReportProgress(): void {
    if (!this.isPlaying) {
      return;
    }
    let vCard = this.videoCard;
    let cid: number = this.cid;
    if (!vCard || vCard.aid <= 0 || cid <= 0) {
      return;
    }
    let progressMs: number = this.getVideoPosition();
    let progressSec: number = Math.floor(progressMs / 1000);

    // fire-and-forget: 用 .then 避免 async/await 在组件销毁后访问 this 导致 SIGSEGV
    reportWatchProgress(vCard.aid, cid, progressSec).then((result) => {
      if (this.isPlaying) {
        if (result.success) {
          this.setStateText('已上传历史记录');
        } else if (result.code !== -101) {
          this.setStateText('历史记录上报失败: ' + result.message);
        }
      }
    });
  }

  private async loadDanmaku(): Promise<void> {
    try {
      let all: Array<DanmakuData> = await getDanmakuItems(this.cid);
      if (all.length > 1000) {
        let step: number = all.length / 1000;
        let sampled: Array<DanmakuData> = [];
        for (let i: number = 0; i < all.length; i += step) {
          sampled.push(all[Math.floor(i)]);
        }
        this.danmakuDataList = sampled;
      } else {
        this.danmakuDataList = all;
      }
      this.danmakuIndex = 0;
    } catch (_e) {
      this.danmakuDataList = [];
    }
  }

  private startDanmakuTimer(): void {
    this.stopDanmakuTimer();
    this.danmakuIndex = 0;
    this.lastCheckedPosition = 0;
    this.danmakuTimer = setInterval(() => this.syncDanmaku(), 500);
  }

  private stopDanmakuTimer(): void {
    if (this.danmakuTimer !== undefined) {
      clearInterval(this.danmakuTimer);
      this.danmakuTimer = undefined;
    }
  }

  private syncDanmaku(): void {
    if (this.danmakuDataList.length === 0 || this.danmakuIndex >= this.danmakuDataList.length) {
      return;
    }
    try {
      let posMs: number = this.getVideoPosition();
      let curSec: number = posMs / 1000;
      if (curSec < this.lastCheckedPosition) {
        this.danmakuIndex = 0;
      }
      this.lastCheckedPosition = curSec;
      let added: number = 0;
      let maxPerSync: number = 3;
      while (this.danmakuIndex < this.danmakuDataList.length && added < maxPerSync) {
        let data = this.danmakuDataList[this.danmakuIndex];
        if (data.time <= curSec + 0.5) {
          this.barrageController.addBarrage(createBarrageItem(data));
          this.danmakuIndex++;
          added++;
        } else {
          break;
        }
      }
    } catch (_e) { /* ignore */
    }
  }

  private startPlay(): void {
    if (!this.videoUrl || !this.mContext) {
      this.errorMsg = '播放器初始化失败';
      return;
    }

    try {
      this.mIjkMediaPlayer.setDebug(true);
      this.mIjkMediaPlayer.setContext(this.mContext, this.XCOMPONENT_ID);
      this.mIjkMediaPlayer.native_setup();

      this.mIjkMediaPlayer.setOption('4', 'start-on-prepared', '0');
      this.mIjkMediaPlayer.setOption('4', 'mediacodec-all-videos', '1');
      this.mIjkMediaPlayer.setOption('4', 'mediacodec-auto-rotate', '1');
      this.mIjkMediaPlayer.setOption('4', 'mediacodec-handle-resolution-change', '1');
      this.mIjkMediaPlayer.setOption('4', 'enable-accurate-seek', '0');
      this.mIjkMediaPlayer.setOption('4', 'packet-buffering', '1');
      this.mIjkMediaPlayer.setOption('4', 'max-buffer-size', '15728640');
      this.mIjkMediaPlayer.setOption('4', 'min-frames', '25');
      this.mIjkMediaPlayer.setOption('4', 'framedrop', '1');
      this.mIjkMediaPlayer.setOption('4', 'max-fps', '30');
      this.mIjkMediaPlayer.setOption('4', 'sync-av-start', '1');
      this.mIjkMediaPlayer.setOption('4', 'infbuf', '0');
      this.mIjkMediaPlayer.setOption('1', 'timeout', '15000000');
      this.mIjkMediaPlayer.setOption('1', 'connect_timeout', '15000000');
      this.mIjkMediaPlayer.setOption('1', 'addrinfo_timeout', '15000000');
      this.mIjkMediaPlayer.setOption('1', 'dns_cache_timeout', '15000000');

      this.mIjkMediaPlayer.setOnPreparedListener({
        onPrepared: () => {
          this.totalDuration = this.getDuration();
          this.resume();
          this.barrageReady = true;
          this.startDanmakuTimer();
        }
      } as OnPreparedListener);

      this.mIjkMediaPlayer.setOnErrorListener({
        onError: (what: number, extra: number) => {
          this.errorMsg = '播放失败 (' + what + ',' + extra + ')';
          this.isPlaying = false;
          this.stopDanmakuTimer();
          this.releaseAudio();
        }
      } as OnErrorListener);

      this.mIjkMediaPlayer.setOnCompletionListener({
        onCompletion: () => {
          this.isPlaying = false;
          this.stopDanmakuTimer();
          this.pause();
        }
      } as OnCompletionListener);

      this.mIjkMediaPlayer.setOnVideoSizeChangedListener({
        onVideoSizeChanged: (width: number, height: number) => {
          if (width > 0 && height > 0) {
            this.videoWidth = width;
            this.videoHeight = height;
            this.calcBaseSize();
            this.calcBoundary();
          }
        }
      } as OnVideoSizeChangedListener);

      this.mIjkMediaPlayer.setOnSeekCompleteListener({
        onSeekComplete: () => {
          this.isSeekLoading = false;
          this.onAudioSeek();
          let pos = this.getVideoPosition();
          if (pos > 0 && this.isDashStream && this.audioRenderer) {
            this.audioRenderer.syncPosition(pos);
          }
        }
      } as OnSeekCompleteListener);

      this.mIjkMediaPlayer.setOnBufferingUpdateListener({
        onBufferingUpdate: (_percent: number) => {
        }
      } as OnBufferingUpdateListener);

      this.mIjkMediaPlayer.setOnInfoListener({
        onInfo: (what: number, _extra: number) => {
          if (what === 701) {
            this.handleBufferingStart();
          } else if (what === 702) {
            this.handleBufferingEnd();
          }
        }
      } as OnInfoListener);

      this.mIjkMediaPlayer.setMessageListener(); //不加这行就会SIGSEGV！！！！别问我怎么知道的，Debug了一整天😇

      let cookieStr: string = getCookieString();
      let headers: Map<string, string> = new Map([
        ['user_agent', HEADERS['User-Agent']],
        ['origin', HEADERS['Origin']],
        ['referer', HEADERS['Referer']],
        ['cookies', cookieStr]
      ]);
      this.mIjkMediaPlayer.setDataSourceHeader(headers);
      this.mIjkMediaPlayer.setOption('1', 'user-agent', HEADERS['User-Agent']);
      this.mIjkMediaPlayer.setOption('1', 'referer', HEADERS['Referer']);
      this.mIjkMediaPlayer.setOption('1', 'cookies', cookieStr);
      this.mIjkMediaPlayer.setDataSource(this.videoUrl);

      this.mIjkMediaPlayer.prepareAsync();
    } catch (e) {
      this.errorMsg = '播放器初始化失败';
    }
  }

  // ===================================================================
  //  清理
  // ===================================================================

  private updateTimeDisplay(): void {
    let now: Date = new Date();
    let h: string = now.getHours().toString().padStart(2, '0');
    let m: string = now.getMinutes().toString().padStart(2, '0');
    this.currentTimeDisplay = h + ':' + m;
  }

  private initMoreSheetState(): void {
    // 电池
    try {
      this.batteryLevel = batteryInfo.batterySOC;
    } catch (_e) {
      this.batteryLevel = -1;
    }
    // 亮度
    try {
      let uiContext = AppStorage.get<common.UIAbilityContext>('UiAbilityContext');
      if (uiContext) {
        window.getLastWindow(uiContext).then((win: window.Window) => {
          let val: number = win.getWindowProperties().brightness;
          if (val >= 0) {
            this.currentBrightness = val;
          }
        });
      }
    } catch (_e) {
      this.currentBrightness = 0.5;
    }
    // 音量
    try {
      let audioManager = harmoniousAudio.getAudioManager();
      audioManager.getVolume(harmoniousAudio.AudioVolumeType.MEDIA, (_err: Error, vol: number) => {
        this.currentVolume = vol / 15;
      });
    } catch (_e) {
      this.currentVolume = 0.8;
    }
  }

  // ===================================================================
  //  手势
  // ===================================================================

  private releaseAudio(): void {
    this.stopSyncTimer();
    this.audioRenderer?.release();
    this.audioRenderer = null;
    this.audioInitStarted = false;
  }

  private releasePlayer(): void {
    try {
      this.mIjkMediaPlayer?.stop();
      this.mIjkMediaPlayer?.release();
    } catch (_e) { /* ignore */
    }
  }

  private resetPlayer(): void {
    this.releasePlayer();
    this.mIjkMediaPlayer = IjkMediaPlayer.getInstance();
  }

  private calcBaseSize(): void {
    if (this.containerWidth <= 0 || this.containerHeight <= 0) {
      return;
    }
    let videoRatio: number = this.videoWidth / this.videoHeight;
    let containerRatio: number = this.containerWidth / this.containerHeight;
    if (videoRatio > containerRatio) {
      this.baseWidth = this.containerWidth;
      this.baseHeight = this.containerWidth / videoRatio;
    } else {
      this.baseHeight = this.containerHeight;
      this.baseWidth = this.containerHeight * videoRatio;
    }
  }

  private calcBoundary(): void {
    let scaledW: number = this.baseWidth * this.curScale;
    let scaledH: number = this.baseHeight * this.curScale;
    this.maxOffsetX = scaledW > this.containerWidth ? (scaledW - this.containerWidth) / 2 : 0;
    this.minOffsetX = -this.maxOffsetX;
    this.maxOffsetY = scaledH > this.containerHeight ? (scaledH - this.containerHeight) / 2 : 0;
    this.minOffsetY = -this.maxOffsetY;
  }

  private restrictBoundary(): void {
    this.calcBoundary();
    this.curOffsetX = Math.max(this.minOffsetX, Math.min(this.maxOffsetX, this.curOffsetX));
    this.curOffsetY = Math.max(this.minOffsetY, Math.min(this.maxOffsetY, this.curOffsetY));
  }

  private onPinchStart(): void {
    this.saveScale = this.curScale;
  }

  private onPinchUpdate(event: GestureEvent): void {
    this.curScale = Math.max(this.MIN_SCALE, Math.min(this.MAX_SCALE, this.saveScale * event.scale));
  }

  private onPinchEnd(): void {
  }

  private onDigitalCrownAction(event: CrownEvent): void {
    let delta: number = event.degree * 0.005;
    let newScale: number = Math.max(this.MIN_SCALE, Math.min(this.MAX_SCALE, this.curScale + delta));
    if (newScale === this.curScale) {
      return;
    }
    this.curScale = newScale;
    this.restrictBoundary();
    try {
      vibrator.startVibration({
        type: 'time',
        duration: 15
      }, {
        id: 0,
        usage: 'touch'
      });
    } catch (_e) { /* ignore */
    }
  }

  private onPanStart(): void {
    this.saveOffsetX = this.curOffsetX;
    this.saveOffsetY = this.curOffsetY;
  }

  private onPanUpdate(event: GestureEvent): void {
    this.curOffsetX = this.saveOffsetX + event.offsetX;
    this.curOffsetY = this.saveOffsetY + event.offsetY;
  }

  private onPanEnd(): void {
    this.restrictBoundary();
  }

  private onDoubleTap(): void {
    if (this.curScale > 1.1) {
      // 缩放状态 → 回到原大小
      this.curScale = 1.0;
      this.curOffsetX = 0;
      this.curOffsetY = 0;
    } else {
      // 未缩放状态 → 暂停/继续
      this.togglePlayPause();
    }
  }

  // ===================================================================
  //  更多面板（半模态）
  // ===================================================================

  private onLongPressStart(): void {
    this.setStateText("3.0x");
    this.speedBeforeLongPress = this.currentSpeed;
    this.setSpeed(3.0);
  }

  private onLongPressEnd(): void {
    this.setSpeed(this.speedBeforeLongPress);
  }

  private getBatteryIcon(level: number): Resource {
    if (level <= 5) {
      return $r('sys.symbol.battery_5percent');
    }
    if (level <= 10) {
      return $r('sys.symbol.battery_10percent');
    }
    if (level <= 15) {
      return $r('sys.symbol.battery_15percent');
    }
    if (level <= 20) {
      return $r('sys.symbol.battery_20percent');
    }
    if (level <= 30) {
      return $r('sys.symbol.battery_30percent');
    }
    if (level <= 40) {
      return $r('sys.symbol.battery_40percent');
    }
    if (level <= 50) {
      return $r('sys.symbol.battery_50percent');
    }
    if (level <= 60) {
      return $r('sys.symbol.battery_60percent');
    }
    if (level <= 70) {
      return $r('sys.symbol.battery_70percent');
    }
    if (level <= 80) {
      return $r('sys.symbol.battery_80percent');
    }
    if (level <= 90) {
      return $r('sys.symbol.battery_90percent');
    }
    return $r('sys.symbol.battery_100percent');
  }

  private formatTime(ms: number): string {
    if (ms < 0) {
      ms = 0;
    }
    let totalSec: number = Math.floor(ms / 1000);
    let min: number = Math.floor(totalSec / 60);
    let sec: number = totalSec % 60;
    return min.toString().padStart(2, '0') + ':' + sec.toString().padStart(2, '0');
  }
}
