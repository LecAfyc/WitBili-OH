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
import { DashAudioRenderer, AudioRenderState } from '../utils/DashAudioRenderer';
import { BarrageView, BarrageController, BarrageItem, BarrageOption } from '@esky/barrage';
import { getDanmakuItems, DanmakuData, createBarrageItem } from '../api/DanmakuApi';
import { VideoQuality } from '../api/VideoDetailApi';
import batteryInfo from '@ohos.batteryInfo';
import vibrator from '@ohos.vibrator';
import { audio as harmoniousAudio } from '@kit.AudioKit';
import { LengthMetrics, window } from '@kit.ArkUI';
import { applyDefaultPlayerOptions, setupPlayerHeaders, formatTime } from '../utils/VideoPlayerUtils';
import { VideoPlayerMoreSheetContent } from '../components/VideoPlayerMoreSheetContent';

// ===== 播放器释放守卫 =====
// ijkplayer 的 release() 会删除消息回调的 napi_ref，但已投递到主线程的 async work
// 仍可能执行 after_message 并访问该引用，导致 SIGSEGV。这里延迟 release，等主线程
// 上已排队的回调先执行完；同时跨页面实例共享状态，避免延迟释放误伤新会话。
let playerReleaseInProgress: boolean = false;
let pendingPlayerReleaseTimer: number | undefined = undefined;

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
  @State playSpeed: number = 1.0;
  // ===== 音频 =====
  @State stateText: string = '';
  // ===== 长按倍速提示（按住期间常显，松手隐藏） =====
  @State longPressSpeedText: string = '';
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
  @State isReconnecting: boolean = false;
  @State retryCount: number = 0;
  @State hasPlaybackStarted: boolean = false;
  private savedPositionOnError: number = 0;
  private readonly MAX_RETRY: number = 3;
  @State totalDuration: number = 0;
  @State wasPlayingBeforeSheet: boolean = false;
  @State danmakuEnabled: boolean = false;
  @State currentVolume: number = 0.8;
  @State currentBrightness: number = 0.5;
  @State batteryLevel: number = 100;
  @State availableQualities: VideoQuality[] = [];
  @State currentQnName: string = '';
  // ===== 离线缓存播放 =====
  @State private isOfflinePlayback: boolean = false;
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
  private crownLogCount: number = 0;
  // ===== 滑动调进度 =====
  @State isSeekingByGesture: boolean = false;
  @State seekPreviewMs: number = 0;
  private panMode: number = 0; // 0 未判定 / 1 移动画面 / 2 调进度 / 3 忽略
  private seekBaseMs: number = 0;
  private seekHapticBucket: number = 0;
  private wasPlayingBeforeGestureSeek: boolean = false;
  private readonly PAN_ZOOM_SCALE: number = 1.001;
  private readonly SEEK_PAN_TRIGGER: number = 8;
  private readonly SEEK_RANGE_MS: number = 120000;
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
  private controlsTimerId: number | undefined = undefined;
  private moreProgressTimerId: number | undefined = undefined;
  // ===== 生命周期与释放 =====
  private isExiting: boolean = false;
  private isPlayerReleased: boolean = false;
  private retryTimerId: number | undefined = undefined;
  private restartTimerId: number | undefined = undefined;
  private qualitySeekTimerId: number | undefined = undefined;
  private seekLoadingTimerId: number | undefined = undefined;
  // ===== 焦点控制 =====
  private readonly VIDEO_FOCUS_ID: string = 'video_player_focus_area';
  private readonly VIDEO_SURFACE_FOCUS_ID: string = 'video_player_surface_focus';
  private readonly SHEET_LIST_FOCUS_ID: string = 'video_more_sheet_list';


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
    if (this.isExiting) {
      return;
    }
    let pos: number = Math.round(Math.max(0, positionMs));
    this.isSeekLoading = true;
    if (this.seekLoadingTimerId !== undefined) {
      clearTimeout(this.seekLoadingTimerId);
    }
    this.seekLoadingTimerId = setTimeout(() => {
      this.seekLoadingTimerId = undefined;
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
    try {
      console.info("[IjkPlayer] Try change speed to " + speed)
      this.mIjkMediaPlayer.setSpeed(String(speed) + 'f');
    } catch (e) {
      console.error("[IjkPlayer] 变速失败，原因：" + JSON.stringify(e))
    }
    if (this.isDashStream && this.audioRenderer) {
      this.audioRenderer.setSpeed(speed);
    }
  }

  // ===================================================================
  //  生命周期
  // ===================================================================

  aboutToDisappear(): void {
    this.isExiting = true;
    this.stopDanmakuTimer();
    this.stopSyncTimer();
    this.clearControlsTimer();
    this.clearMoreProgressTimer();
    this.clearPendingTimers();
    this.mContext = undefined;
    this.releaseAudioSafely();
    this.releasePlayerSafely();
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
                // XComponent 挂载后会成为实际的输入/焦点目标，这里主动把焦点和表冠交给它
                this.ensureVideoFocus();
              })
              .onDestroy(() => {
                this.mContext = undefined;
                this.releasePlayerSafely();
              })
              .id(this.VIDEO_SURFACE_FOCUS_ID)
              .focusable(true)
              .focusOnTouch(true)
              .onFocus(() => {
                console.info('[VideoPlayerPage] 视频Surface获焦，表冠可缩放');
              })
              .onBlur(() => {
                console.warn('[VideoPlayerPage] 视频Surface失焦，表冠将不再缩放');
              })
              .onDigitalCrown((event: CrownEvent) => {
                event.stopPropagation();
                this.onDigitalCrownAction(event);
              })
              .width(this.baseWidth * this.curScale)
              .height(this.baseHeight * this.curScale)
              .translate({ x: this.curOffsetX, y: this.curOffsetY })

            if (this.isReconnecting) {
              Column() {
                LoadingProgress().width(40).height(40).color(Color.White)
                Text('正在重连 (' + this.retryCount + '/' + this.MAX_RETRY + ')')
                  .fontSize(12)
                  .fontColor(Color.White)
                  .margin({ top: 8 })
              }
              .justifyContent(FlexAlign.Center)
              .backgroundColor('rgba(0,0,0,0.3)')
              .borderRadius(12)
              .padding(16)
            } else if (this.isBuffering) {
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

            if (this.stateText || this.longPressSpeedText) {
              Row() {
                Text(this.longPressSpeedText !== '' ? this.longPressSpeedText : this.stateText)
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

            if (this.isSeekingByGesture) {
              Column({ space: 6 }) {
                Text(formatTime(this.seekPreviewMs))
                  .fontSize(20)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(Color.White)
                Progress({
                  value: this.seekPreviewMs,
                  total: this.totalDuration > 0 ? this.totalDuration : 1,
                  type: ProgressType.Linear
                })
                  .width(110)
                  .height(3)
                  .color('#FF69B4')
                  .backgroundColor('rgba(255,255,255,0.25)')
                Text(formatTime(this.totalDuration))
                  .fontSize(9)
                  .fontColor('#AAAAAA')
              }
              .padding({
                left: 16,
                right: 16,
                top: 10,
                bottom: 10
              })
              .backgroundColor('rgba(0,0,0,0.65)')
              .borderRadius(14)
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
              })
              .onActionCancel(() => {
                this.onPanCancel();
              }),
            LongPressGesture({ duration: 500 })
              .onAction(() => {
                this.onLongPressStart();
              })
              .onActionEnd(() => {
                this.onLongPressEnd();
              })
              .onActionCancel(() => {
                this.onLongPressEnd();
              })
          )
        )
        .id(this.VIDEO_FOCUS_ID)
        .focusable(true)
        .focusOnTouch(true)
        .defaultFocus(true)
        .onAppear(() => {
          this.ensureVideoFocus();
        })
        .onFocus(() => {
          console.info('[VideoPlayerPage] 视频容器获焦');
        })
        .onBlur(() => {
          console.warn('[VideoPlayerPage] 视频容器失焦');
        })
        .onDigitalCrown((event: CrownEvent) => {
          event.stopPropagation();
          this.onDigitalCrownAction(event);
        })

        // ── Controls 覆盖层 ──
        Column() {
          this.ControlsOverlay()
        }
        .visibility(this.showControls ? Visibility.Visible : Visibility.Hidden)
        .animation({ duration: 100, curve: Curve.EaseOut })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Color.Black)
      .gesture(
        TapGesture({ count: 1 }).onAction(() => {
          this.onSingleTap();
        })
      )
      // 兜底：视频画面失焦（例如焦点落在控制按钮上）时，表冠事件冒泡到这里仍可缩放
      .focusable(true)
      .onDigitalCrown((event: CrownEvent) => {
        event.stopPropagation();
        this.onDigitalCrownAction(event);
      })
      .bindSheet($$this.showMoreSheet, this.MoreSheet(), {
        detents: [SheetSize.MEDIUM,SheetSize.LARGE],
        backgroundColor: 'rgba(28,28,30,0.45)',
        blurStyle: BlurStyle.BACKGROUND_THIN,
        onDisappear: () => {
          this.clearMoreProgressTimer();
          if (this.isExiting) {
            return;
          }
          if (this.wasPlayingBeforeSheet) {
            this.resume();
          }
          // 面板关闭后强制把焦点还给视频画面，恢复表冠缩放
          setTimeout(() => {
            this.ensureVideoFocus();
          }, 300);
        }
      })
    }
    .hideBackButton(true).hideTitleBar(true)
    .onShown(() => {
      // NavDestination 完全显示后再抢焦点，转场期间 requestFocus 可能失败
      this.ensureVideoFocus();
    })
    .onReady((context: NavDestinationContext) => {
      let param = context.pathInfo.param as Record<string, Object>;
      if (param) {
        this.videoCard = param['videoCard'] as VideoCard;
        this.cid = param['cid'] as number;
        if (param['qn'] !== undefined) {
          this.qn = param['qn'] as number;
        }
        if (param['qnName'] !== undefined) {
          this.currentQnName = param['qnName'] as string;
        }
        if (param['offline'] === true) {
          this.startOfflinePlayback(param);
          return;
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
    this.showControls = true;
    this.clearControlsTimer();
    this.controlsTimerId = setTimeout(() => {
      this.showControls = false;
      if (!this.showMoreSheet) {
        this.ensureVideoFocus();
      }
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
    if (!this.showMoreSheet) {
      this.ensureVideoFocus();
    }
  }

  // ===================================================================
  //  焦点控制
  // ===================================================================

  /** 将焦点切换到指定 id 的组件（滚轮/表冠事件只分发给获焦组件） */
  private requestFocusById(id: string): void {
    try {
      this.getUIContext().getFocusController().requestFocus(id);
    } catch (e) {
      console.warn('[VideoPlayerPage] requestFocus 异常: ' + id + ' ' + String(e));
    }
  }

  /** 焦点回到视频画面：表冠缩放（XComponent 挂载后优先交给画面本体） */
  private requestVideoFocus(): void {
    let targetId: string = this.mContext !== undefined ? this.VIDEO_SURFACE_FOCUS_ID : this.VIDEO_FOCUS_ID;
    this.requestFocusById(targetId);
  }

  /**
   * 确保视频画面获焦：NavDestination 转场/首帧期间 requestFocus 可能失败，
   * 这里做少量退避重发；面板打开或页面退出时不再抢占焦点。
   */
  private ensureVideoFocus(attempt: number = 0): void {
    if (this.isExiting || this.showMoreSheet) {
      return;
    }
    this.requestVideoFocus();
    if (attempt >= 3) {
      return;
    }
    setTimeout(() => {
      this.ensureVideoFocus(attempt + 1);
    }, 200 * (attempt + 1));
  }

  /** 焦点回到更多面板列表：表冠滚动面板 */
  private requestSheetFocus(): void {
    this.requestFocusById(this.SHEET_LIST_FOCUS_ID);
  }

  // ===================================================================
  //  工具方法
  // ===================================================================

  openMoreSheet(): void {
    // 仅在此处上报观看进度（须在 pause 之前，否则会被 isPlaying 判断拦下）
    this.doReportProgress();
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
    // 面板拉起动画结束后把焦点交给面板列表，表冠才能滚动面板
    setTimeout(() => {
      if (this.showMoreSheet) {
        this.requestSheetFocus();
      }
    }, 300);
  }

  clearMoreProgressTimer(): void {
    if (this.moreProgressTimerId !== undefined) {
      clearInterval(this.moreProgressTimerId);
      this.moreProgressTimerId = undefined;
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
  ControlsOverlay() {
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
          this.clearControlsTimer();
          this.pageStack.pop();
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
          this.clearControlsTimer();
          this.openMoreSheet();
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
          this.toggleDanmaku();
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
  }

  @Builder
  MoreSheet() {
    VideoPlayerMoreSheetContent({
      currentProgress: this.currentProgress,
      totalDuration: this.totalDuration,
      isSeekLoading: this.isSeekLoading,
      currentSpeed: this.currentSpeed,
      currentVolume: this.currentVolume,
      currentBrightness: this.currentBrightness,
      availableQualities: this.availableQualities,
      currentQn: this.qn,
      batteryLevel: this.batteryLevel,
      sheetVisible: this.showMoreSheet,
      onSeekStart: (): void => {
        this.isSeeking = true;
      },
      onSeek: (value: number): void => {
        this.isSeeking = false;
        this.isSeekLoading = true;
        this.seekTo(value);
      },
      onSpeedChange: (speed: number): void => {
        this.currentSpeed = speed;
        this.setSpeed(speed);
      },
      onVolumeChange: (value: number): void => {
        this.currentVolume = value;
        try {
          let audioManager = harmoniousAudio.getAudioManager();
          audioManager.setVolume(
            harmoniousAudio.AudioVolumeType.MEDIA,
            Math.round(value * 15),
            (_err: Error) => {
            }
          );
        } catch (_e) { /* ignore */
        }
      },
      onBrightnessChange: (value: number): void => {
        this.currentBrightness = value;
        try {
          let uiContext = AppStorage.get<common.UIAbilityContext>('UiAbilityContext');
          if (uiContext) {
            window.getLastWindow(uiContext).then((win: window.Window) => {
              win.setWindowBrightness(value);
            });
          }
        } catch (_e) { /* ignore */
        }
      },
      onQualitySwitch: (qn: number): void => {
        this.switchQuality(qn);
      }
    })
  }

  /** 使用本地缓存文件播放（不请求网络） */
  private startOfflinePlayback(param: Record<string, Object>): void {
    this.isOfflinePlayback = true;
    this.videoUrl = (param['localVideoPath'] as string) || '';
    this.audioUrl = (param['localAudioPath'] as string) || '';
    this.isDashStream = param['localIsDash'] === true;
    let localDuration: number = (param['localDurationMs'] as number) || 0;
    if (localDuration > 0) {
      this.totalDuration = localDuration;
    }
    if (!this.videoUrl) {
      this.errorMsg = '缓存文件不存在';
      this.isLoading = false;
      return;
    }
    this.isLoading = false;
    if (this.isDashStream && this.audioUrl) {
      this.startAudioRendering();
    }
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
        let qq: number = result.acceptQuality[i] || 0;
        if (qq === 120 || qq === 116 || qq === 112) {
          continue;
        }
        qualities.push({
          name: result.acceptDescription[i],
          qn: qq
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
    if (this.isExiting || this.isOfflinePlayback || newQn === this.qn) {
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
    this.releaseAudioSafely();
    this.stopDanmakuTimer();
    this.stopSyncTimer();
    this.isLoading = true;
    this.errorMsg = '';
    try {
      let result: DashPlayUrlResult = await getDashPlayUrl(this.videoCard!.bvid, this.cid, this.qn);
      if (this.isExiting) {
        return;
      }
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
        if (this.qualitySeekTimerId !== undefined) {
          clearTimeout(this.qualitySeekTimerId);
        }
        this.qualitySeekTimerId = setTimeout(() => {
          this.qualitySeekTimerId = undefined;
          if (this.isExiting) {
            return;
          }
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
    if (this.isExiting) {
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

      if (this.isExiting) {
        this.releaseAudioSafely();
        return;
      }

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
    if (this.isExiting || !this.audioRenderer) {
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
    if (this.isOfflinePlayback || !this.isPlaying) {
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
    reportWatchProgress(vCard.aid, cid, progressSec).then(() => {
      // 上报结果无需提示
    }).catch(() => {
      // 忽略异常，避免未捕获的 Promise
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
    if (this.isExiting) {
      return;
    }
    if (playerReleaseInProgress) {
      // 上一次释放（退出/重置）尚未完成，等它收尾后再初始化，避免与 release 竞争
      if (this.restartTimerId !== undefined) {
        clearTimeout(this.restartTimerId);
      }
      this.restartTimerId = setTimeout(() => {
        this.restartTimerId = undefined;
        this.startPlay();
      }, 350);
      return;
    }
    if (!this.videoUrl || !this.mContext) {
      this.errorMsg = '播放器初始化失败';
      return;
    }
    this.isPlayerReleased = false;

    try {
      this.mIjkMediaPlayer.setDebug(true);
      this.mIjkMediaPlayer.setContext(this.mContext, this.XCOMPONENT_ID);
      this.mIjkMediaPlayer.native_setup();

      applyDefaultPlayerOptions(this.mIjkMediaPlayer);

      this.mIjkMediaPlayer.setOnPreparedListener({
        onPrepared: () => {
          if (this.isExiting) {
            return;
          }
          this.isBuffering = false;
          this.isReconnecting = false;
          this.hasPlaybackStarted = true;
          this.retryCount = 0;
          let preparedDuration: number = this.getDuration();
          if (preparedDuration > 0 || !this.isOfflinePlayback) {
            this.totalDuration = preparedDuration;
          }
          if (this.savedPositionOnError > 0) {
            let pos: number = this.savedPositionOnError;
            this.savedPositionOnError = 0;
            this.resume(pos);
            if (this.isDashStream && this.audioUrl) {
              this.audioInitStarted = false;
              this.startAudioRendering();
            }
          } else {
            this.resume();
          }
          this.barrageReady = true;
          this.startDanmakuTimer();
        }
      } as OnPreparedListener);

      this.mIjkMediaPlayer.setOnErrorListener({
        onError: (what: number, extra: number) => {
          if (this.isExiting) {
            return;
          }
          if (this.hasPlaybackStarted && this.retryCount < this.MAX_RETRY) {
            this.savedPositionOnError = this.getVideoPosition();
            this.retryCount++;
            this.isReconnecting = true;
            this.isBuffering = false;
            this.isPlaying = false;
            this.stopDanmakuTimer();
            this.stopSyncTimer();
            this.releaseAudioSafely();
            // 不在 native 回调栈内释放播放器，交给页面退出或重试前的安全释放流程
            if (this.retryTimerId !== undefined) {
              clearTimeout(this.retryTimerId);
            }
            this.retryTimerId = setTimeout(() => {
              this.retryTimerId = undefined;
              if (!this.isExiting && this.mContext !== undefined) {
                this.retryPlay();
              }
            }, 1500);
          } else {
            this.errorMsg = '播放失败 (' + what + ',' + extra + ')';
            this.isPlaying = false;
            this.isReconnecting = false;
            this.stopDanmakuTimer();
            this.releaseAudioSafely();
          }
        }
      } as OnErrorListener);

      this.mIjkMediaPlayer.setOnCompletionListener({
        onCompletion: () => {
          if (this.isExiting) {
            return;
          }
          this.isPlaying = false;
          this.stopDanmakuTimer();
          this.pause();
        }
      } as OnCompletionListener);

      this.mIjkMediaPlayer.setOnVideoSizeChangedListener({
        onVideoSizeChanged: (width: number, height: number) => {
          if (this.isExiting) {
            return;
          }
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
          if (this.isExiting) {
            return;
          }
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
          if (this.isExiting) {
            return;
          }
          if (what === 701) {
            this.handleBufferingStart();
          } else if (what === 702) {
            this.handleBufferingEnd();
          }
        }
      } as OnInfoListener);

      this.mIjkMediaPlayer.setMessageListener(); //不加这行就会SIGSEGV！！！！别问我怎么知道的，Debug了一整天😇

      setupPlayerHeaders(this.mIjkMediaPlayer);
      this.mIjkMediaPlayer.setDataSource(this.videoUrl);

      this.isBuffering = true;
      this.mIjkMediaPlayer.prepareAsync();
    } catch (e) {
      this.errorMsg = '播放器初始化失败';
    }
  }

  // ===================================================================
  //  清理
  // ===================================================================

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

  private releaseAudioSafely(): void {
    this.stopSyncTimer();
    try {
      this.audioRenderer?.release();
    } catch (_e) { /* ignore */ }
    this.audioRenderer = null;
    this.audioInitStarted = false;
  }

  /**
   * 安全释放播放器：幂等 + 延迟。
   * ijkplayer 的 release() 删除消息回调的 napi_ref 后，主线程里已排队的
   * after_message 仍会被执行并访问该引用，导致 SIGSEGV。延迟一个事件循环
   * 让这些回调先跑完再 release。
   */
  private releasePlayerSafely(): void {
    if (this.isPlayerReleased) {
      return;
    }
    this.isPlayerReleased = true;
    try {
      this.mIjkMediaPlayer.stop();
    } catch (_e) { /* ignore */ }
    playerReleaseInProgress = true;
    if (pendingPlayerReleaseTimer !== undefined) {
      clearTimeout(pendingPlayerReleaseTimer);
    }
    pendingPlayerReleaseTimer = setTimeout(() => {
      pendingPlayerReleaseTimer = undefined;
      try {
        this.mIjkMediaPlayer.release();
      } catch (_e) { /* ignore */ }
      playerReleaseInProgress = false;
    }, 300);
  }

  private clearPendingTimers(): void {
    if (this.retryTimerId !== undefined) {
      clearTimeout(this.retryTimerId);
      this.retryTimerId = undefined;
    }
    if (this.restartTimerId !== undefined) {
      clearTimeout(this.restartTimerId);
      this.restartTimerId = undefined;
    }
    if (this.qualitySeekTimerId !== undefined) {
      clearTimeout(this.qualitySeekTimerId);
      this.qualitySeekTimerId = undefined;
    }
    if (this.seekLoadingTimerId !== undefined) {
      clearTimeout(this.seekLoadingTimerId);
      this.seekLoadingTimerId = undefined;
    }
  }

  private retryPlay(): void {
    this.releasePlayerSafely();
    this.startPlay();
  }

  private resetPlayer(): void {
    this.releasePlayerSafely();
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
    this.crownLogCount++;
    if (this.crownLogCount <= 3 || this.crownLogCount % 20 === 0) {
      console.info('[VideoPlayerPage] Crown action=' + event.action
        + ' degree=' + event.degree + ' velocity=' + event.angularVelocity);
    }
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
    if (this.curScale > this.PAN_ZOOM_SCALE) {
      // 已缩放：拖动画面
      this.panMode = 1;
    } else if (this.totalDuration <= 0) {
      this.panMode = 3;
    } else {
      // 未缩放：待判定方向后调进度
      this.panMode = 0;
    }
  }

  private onPanUpdate(event: GestureEvent): void {
    if (this.panMode === 1) {
      this.curOffsetX = this.saveOffsetX + event.offsetX;
      this.curOffsetY = this.saveOffsetY + event.offsetY;
      return;
    }
    if (this.panMode === 0) {
      let absX: number = Math.abs(event.offsetX);
      let absY: number = Math.abs(event.offsetY);
      if (absX < this.SEEK_PAN_TRIGGER && absY < this.SEEK_PAN_TRIGGER) {
        return;
      }
      if (absX < absY) {
        // 竖直滑动不处理
        this.panMode = 3;
        return;
      }
      this.panMode = 2;
      this.beginSeekPreview();
    }
    if (this.panMode === 2) {
      this.updateSeekPreview(event.offsetX);
    }
  }

  private onPanEnd(): void {
    if (this.panMode === 1) {
      this.restrictBoundary();
    } else if (this.panMode === 2) {
      this.endSeekPreview(true);
    }
    this.panMode = 0;
  }

  private onPanCancel(): void {
    if (this.panMode === 2) {
      this.endSeekPreview(false);
    }
    this.panMode = 0;
  }

  private beginSeekPreview(): void {
    this.wasPlayingBeforeGestureSeek = this.isPlaying;
    if (this.isPlaying) {
      this.pause();
    }
    this.seekBaseMs = Math.max(0, this.getCurrentPosition());
    this.seekPreviewMs = this.seekBaseMs;
    this.seekHapticBucket = Math.floor(this.seekBaseMs / 10000);
    this.isSeekingByGesture = true;
    this.hideControls();
  }

  private updateSeekPreview(offsetX: number): void {
    let width: number = this.containerWidth > 0 ? this.containerWidth : 320;
    let rangeMs: number = this.totalDuration > 0 ? Math.min(this.SEEK_RANGE_MS, this.totalDuration) : this.SEEK_RANGE_MS;
    let target: number = Math.max(0, Math.min(this.totalDuration, this.seekBaseMs + offsetX / width * rangeMs));
    if (Math.round(target) === Math.round(this.seekPreviewMs)) {
      return;
    }
    this.seekPreviewMs = target;
    let bucket: number = Math.floor(target / 10000);
    if (bucket !== this.seekHapticBucket) {
      this.seekHapticBucket = bucket;
      this.vibrateTick();
    }
  }

  private endSeekPreview(applySeek: boolean): void {
    if (!this.isSeekingByGesture) {
      return;
    }
    let target: number = this.seekPreviewMs;
    let shouldResume: boolean = this.wasPlayingBeforeGestureSeek;
    this.isSeekingByGesture = false;
    this.wasPlayingBeforeGestureSeek = false;
    if (applySeek && Math.round(target) !== Math.round(this.seekBaseMs)) {
      this.seekTo(target);
    }
    if (shouldResume) {
      this.resume();
    }
  }

  private vibrateTick(): void {
    try {
      vibrator.startVibration({
        type: 'time',
        duration: 10
      }, {
        id: 0,
        usage: 'touch'
      });
    } catch (_e) { /* ignore */
    }
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
    this.speedBeforeLongPress = this.currentSpeed;
    this.longPressSpeedText = '3.0x';
    this.setSpeed(3.0);
  }

  private onLongPressEnd(): void {
    this.longPressSpeedText = '';
    this.setSpeed(this.speedBeforeLongPress);
  }

}
