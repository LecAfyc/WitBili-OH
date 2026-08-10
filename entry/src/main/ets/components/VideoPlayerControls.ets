/**
 * 视频播放器控制层参数类
 *
 * 控制层 UI 已内联到 VideoPlayerPage.ControlsOverlay() @Builder 方法，
 * 此处保留参数类供后续可能的复用场景。
 */

export class VideoPlayerControlsParams {
  isPlaying: boolean = false;
  danmakuEnabled: boolean = false;
  onBack: () => void = (): void => {};
  onMore: () => void = (): void => {};
  onToggleDanmaku: () => void = (): void => {};
  onTogglePlayPause: () => void = (): void => {};
  onHideControls: () => void = (): void => {};
}
