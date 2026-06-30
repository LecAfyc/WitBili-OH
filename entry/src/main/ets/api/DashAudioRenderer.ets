/**
 * DASH 音频渲染器（仅 AVPlayer）
 * 播放 DASH 的 .m4s 音频分片，支持音画同步漂移修正。
 */

import { media } from '@kit.MediaKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { getCookieString } from './CookiesApi';
import { HEADERS } from './CommonApi';

export enum AudioRenderState {
  IDLE = 'idle',
  PREPARING = 'preparing',
  PLAYING = 'playing',
  PAUSED = 'paused',
  COMPLETED = 'completed',
  ERROR = 'error',
  RELEASED = 'released'
}

export type AudioStateCallback = (state: AudioRenderState, message?: string) => void;

export class DashAudioRenderer {
  private avPlayer: media.AVPlayer | null = null;
  private state: AudioRenderState = AudioRenderState.IDLE;
  private stateCallback: AudioStateCallback | null = null;

  // 同步相关
  private readonly MAX_DRIFT_MS: number = 1000;
  private firstAudioPosMs: number = -1;
  private lastDiagLogMs: number = 0;
  private playStartMs: number = 0;
  private seekCount: number = 0;

  onStateChange(callback: AudioStateCallback): void {
    this.stateCallback = callback;
  }

  private setState(newState: AudioRenderState, message?: string): void {
    if (newState === this.state) return;
    let old = this.state;
    this.state = newState;
    console.info('[DashAudioRenderer] ' + old + ' → ' + newState + (message ? ' (' + message + ')' : ''));
    this.stateCallback?.(newState, message);
  }

  getState(): AudioRenderState {
    return this.state;
  }

  getCurrentPositionMs(): number {
    return this.avPlayer?.currentTime ?? -1;
  }

  isAudioPlaying(): boolean {
    return this.state === AudioRenderState.PLAYING;
  }

  // ===== 初始化 =====

  async init(url: string): Promise<void> {
    this.firstAudioPosMs = -1;
    this.lastDiagLogMs = 0;
    this.playStartMs = 0;
    this.seekCount = 0;

    try {
      await this.initAVPlayer(url);
    } catch (e) {
      this.releaseSync();
      this.setState(AudioRenderState.ERROR, 'AVPlayer 初始化失败');
      throw new Error('DashAudioRenderer 初始化失败: ' + String(e));
    }
  }

  private async initAVPlayer(url: string): Promise<void> {
    let avp: media.AVPlayer = await media.createAVPlayer();
    this.avPlayer = avp;
    this.setState(AudioRenderState.PREPARING);

    let headers: Record<string, string> = {
      'User-Agent': HEADERS['User-Agent'],
      'Referer': HEADERS['Referer'],
      'Origin': HEADERS['Origin']
    };
    let cookieStr: string = getCookieString();
    if (cookieStr) headers['Cookie'] = cookieStr;

    let mediaSource: media.MediaSource = media.createMediaSourceWithUrl(url, headers);
    let strategy: media.PlaybackStrategy = { preferredBufferDuration: 20 };

    await new Promise<void>((resolve, reject) => {
      const timeoutId = setTimeout(() => reject(new Error('AVPlayer init 超时')), 25000);

      avp.on('stateChange', (state: string): void => {
        switch (state) {
          case 'initialized':
            avp.prepare();
            return;
          case 'prepared':
            clearTimeout(timeoutId);
            resolve();
            return;
          case 'error':
            clearTimeout(timeoutId);
            reject(new Error('AVPlayer 进入 error'));
            return;
          case 'playing':
            this.setState(AudioRenderState.PLAYING);
            return;
          case 'paused':
            this.setState(AudioRenderState.PAUSED);
            return;
          case 'completed':
            this.setState(AudioRenderState.COMPLETED);
            return;
        }
      });

      avp.on('error', (err: BusinessError): void => {
        clearTimeout(timeoutId);
        reject(new Error('AVPlayer error: ' + err.message));
      });

      avp.setMediaSource(mediaSource, strategy);
    });
  }

  // ===== 播放控制 =====

  play(): void {
    let s = this.getState();
    if (!this.avPlayer || s === AudioRenderState.RELEASED || s === AudioRenderState.ERROR) return;
    try {
      this.playStartMs = Date.now();
      this.avPlayer.play();
      this.setState(AudioRenderState.PLAYING);
    } catch (e) {
      console.error('[DashAudioRenderer] play 失败: ' + String(e));
    }
  }

  pause(): void {
    this.avPlayer?.pause();
    this.setState(AudioRenderState.PAUSED);
  }

  setSpeed(speed: number): void {
    try {
      this.avPlayer?.setSpeed(Math.max(0.5, Math.min(3.0, speed)));
    } catch (e) {
      console.warn('[DashAudioRenderer] setSpeed 失败: ' + String(e));
    }
  }

  seekTo(positionMs: number): void {
    this.seekCount++;
    this.avPlayer?.seek(Math.round(positionMs));
  }

  stop(): void {
    try {
      this.avPlayer?.stop();
    } catch (_e) { /* ignore */ }
    this.setState(AudioRenderState.IDLE);
  }

  release(): void {
    this.releaseSync();
  }

  private releaseSync(): void {
    try {
      this.avPlayer?.release();
    } catch (e) {
      console.warn('[DashAudioRenderer] release: ' + String(e));
    }
    this.avPlayer = null;
    this.setState(AudioRenderState.RELEASED);
  }

  // ===== 音画同步 =====

  syncPosition(videoPositionMs: number): void {
    if (!this.avPlayer || (this.state !== AudioRenderState.PLAYING && this.state !== AudioRenderState.PAUSED)) {
      return;
    }
    try {
      let audioPosMs: number = this.getCurrentPositionMs();
      let nowMs: number = Date.now();
      let elapsedSincePlay: number = nowMs - this.playStartMs;

      if (audioPosMs > 0 && this.firstAudioPosMs <= 0) {
        this.firstAudioPosMs = audioPosMs;
        console.info('[DashAudioRenderer] ⏱ 首次音频位置: ' + audioPosMs + 'ms');
      }

      if (nowMs - this.lastDiagLogMs > 5000) {
        this.lastDiagLogMs = nowMs;
        console.info('[DashAudioRenderer] 📊 a=' + Math.round(audioPosMs) + 'ms v=' + Math.round(videoPositionMs) + 'ms seek#' + this.seekCount);
      }

      if (audioPosMs <= 0 || (elapsedSincePlay < 2000 && audioPosMs < 1000)) return;

      let drift: number = audioPosMs - videoPositionMs;
      if (Math.abs(drift) > this.MAX_DRIFT_MS && Math.abs(drift) < 30000) {
        console.info('[DashAudioRenderer] 🔄 漂移' + Math.round(drift) + 'ms，seek');
        this.seekTo(videoPositionMs);
      } else if (Math.abs(drift) >= 30000) {
        console.warn('[DashAudioRenderer] ⚠️ 漂移过大 ' + Math.round(drift) + 'ms，跳过 seek');
      }
    } catch (e) {
      console.warn('[DashAudioRenderer] syncPosition: ' + String(e));
    }
  }
}
