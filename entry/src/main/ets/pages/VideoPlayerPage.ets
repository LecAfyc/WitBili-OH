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
import { applyDefaultPlayerOptions, setupPlayerHeaders } from '../utils/VideoPlayerUtils';
import { VideoPlayerControls } from '../components/VideoPlayerControls';
import { VideoPlayerMoreSheetContent } from '../components/VideoPlayerMoreSheetContent';

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

        // ── Controls 覆盖层 ──
        VideoPlayerControls({
          isPlaying: this.isPlaying,
          danmakuEnabled: this.danmakuEnabled,
          onBack: (): void => {
            this.clearControlsTimer();
            this.pageStack.pop();
          },
          onMore: (): void => {
            this.clearControlsTimer();
            this.openMoreSheet();
          },
          onToggleDanmaku: (): void => {
            this.toggleDanmaku();
          },
          onTogglePlayPause: (): void => {
            this.togglePlayPause();
            this.clearControlsTimer();
            this.showControlsWithTimer();
          },
          onHideControls: (): void => {
            this.hideControls();
          }
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
    VideoPlayerMoreSheetContent({
      currentProgress: this.currentProgress,
      totalDuration: this.totalDuration,
      isSeekLoading: this.isSeekLoading,
      currentSpeed: this.currentSpeed,
      currentVolume: this.currentVolume,
      currentBrightness: this.currentBrightness,
      availableQualities: this.availableQualities,
      currentQn: this.qn,
      currentTimeDisplay: this.currentTimeDisplay,
      batteryLevel: this.batteryLevel,
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

      applyDefaultPlayerOptions(this.mIjkMediaPlayer);

      this.mIjkMediaPlayer.setOnPreparedListener({
        onPrepared: () => {
          this.isBuffering = false;
          this.isReconnecting = false;
          this.hasPlaybackStarted = true;
          this.retryCount = 0;
          this.totalDuration = this.getDuration();
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
          if (this.hasPlaybackStarted && this.retryCount < this.MAX_RETRY) {
            this.savedPositionOnError = this.getVideoPosition();
            this.retryCount++;
            this.isReconnecting = true;
            this.isBuffering = false;
            this.isPlaying = false;
            this.stopDanmakuTimer();
            this.releasePlayer();
            this.releaseAudio();
            setTimeout(() => {
              if (this.mContext !== undefined) {
                this.retryPlay();
              }
            }, 1500);
          } else {
            this.errorMsg = '播放失败 (' + what + ',' + extra + ')';
            this.isPlaying = false;
            this.isReconnecting = false;
            this.stopDanmakuTimer();
            this.releaseAudio();
          }
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

  private retryPlay(): void {
    this.resetPlayer();
    this.startPlay();
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

}
