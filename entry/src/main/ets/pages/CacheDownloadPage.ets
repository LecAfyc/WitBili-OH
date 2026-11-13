/**
 * 视频缓存下载页
 *
 * 路由参数：{ videoCard, cid, qn, qnName, durationMs }
 *
 * 前台流式下载视频（DASH 时额外下载音频），完成后写入缓存索引，
 * 可直接跳转离线播放。
 */

import { fileIo } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { VideoCard } from '../model/ContentCard';
import { CachedVideo } from '../model/CachedVideo';
import { CacheStreamResult, getCacheStreams } from '../api/VideoStreamApi';
import { bv2av } from '../api/CommonApi';
import { HttpFileDownloader, DownloadTick } from '../utils/HttpFileDownloader';
import {
  addCachedVideo,
  ensureCacheDir,
  findCachedVideo,
  formatBytes,
  createOfflinePlayParam,
  removeCachedVideo
} from '../utils/VideoCacheStore';

@Component
export struct CacheDownloadPage {
  @Consume('pageStack') pageStack: NavPathStack;
  @State title: string = '';
  @State qnName: string = '';
  @State percent: number = 0;
  @State statusText: string = '正在解析视频地址...';
  @State errorText: string = '';
  @State isDownloading: boolean = false;
  @State isDone: boolean = false;
  private videoCard: VideoCard = new VideoCard();
  private cid: number = 0;
  private qn: number = 80;
  private durationMs: number = 0;
  private downloader: HttpFileDownloader | null = null;
  private started: boolean = false;
  private pageAlive: boolean = true;
  private lastTickMs: number = 0;
  private videoPath: string = '';
  private audioPath: string = '';
  private savedEntry: CachedVideo | null = null;

  build() {
    NavDestination() {
      Column() {
        Row() {
          Text('缓存').fontSize(16).fontColor('#EEEEEE').fontWeight(FontWeight.Medium)
          Blank()
          Text(this.qnName).fontSize(10).fontColor('#FB7299')
        }
        .width('82%')


        Blank()

        Stack() {
          Progress({ value: this.percent, total: 100, type: ProgressType.Ring })
            .width(116)
            .height(116)
            .color('#FB7299')
            .backgroundColor('rgba(255,255,255,0.12)')
          Column() {
            if (this.isDone) {
              Text('✓').fontSize(30).fontColor('#FB7299')
            } else {
              Text(this.percent.toString() + '%')
                .fontSize(this.percent >= 100 ? 24 : 26)
                .fontWeight(FontWeight.Medium)
                .fontColor('#FFFFFF')
            }
            Text(this.isDone ? '已完成' : (this.errorText ? '失败' : '下载中'))
              .fontSize(9)
              .fontColor('#AAAAAA')
              .margin({ top: 2 })
          }
        }
        .width(116)
        .height(116)

        Text(this.statusText)
          .fontSize(12)
          .fontColor(this.isDone ? '#FB7299' : '#CCCCCC')
          .margin({ top: 10 })
          .maxLines(2)
          .textAlign(TextAlign.Center)

        if (this.errorText) {
          Text(this.errorText)
            .fontSize(10)
            .fontColor('#FF6B6B')
            .maxLines(2)
            .textAlign(TextAlign.Center)
            .width('82%')
            .margin({ top: 4 })
        }

        Blank()

        Row({ space: 10 }) {
          if (this.isDone) {
            Button('完成')
              .fontSize(14)
              .fontColor('#EEEEEE')
              .backgroundColor('rgba(66,66,66,0.8)')
              .height(42)
              .layoutWeight(1)
              .borderRadius(21)
              .onClick(() => {
                this.pageStack.pop();
              })
          } else if (this.errorText) {
            Button('重试')
              .fontSize(14)
              .fontColor('#FFFFFF')
              .backgroundColor('#FB7299')
              .height(42)
              .layoutWeight(1)
              .borderRadius(21)
              .onClick(() => {
                this.retry();
              })
            Button('返回')
              .fontSize(14)
              .fontColor('#EEEEEE')
              .backgroundColor('rgba(66,66,66,0.8)')
              .height(42)
              .layoutWeight(1)
              .borderRadius(21)
              .onClick(() => {
                this.pageStack.pop();
              })
          } else {
            Button(this.isDownloading ? '取消' : '返回')
              .fontSize(14)
              .fontColor('#EEEEEE')
              .backgroundColor('rgba(66,66,66,0.8)')
              .height(42)
              .width('60%')
              .borderRadius(21)
              .onClick(() => {
                this.cancelAndExit();
              })
          }
        }
        .width('82%')
        .justifyContent(FlexAlign.Center)
      }
      .width('100%')
      .height('100%')
      .padding({
        left: 16,
        right: 16,
        top: 30,
        bottom: 30
      })
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .hideBackButton(true)
    .hideTitleBar(true)
    .backgroundImage($r('app.media.oobe'))
    .onReady((context: NavDestinationContext) => {
      let param: Record<string, Object> = context.pathInfo.param as Record<string, Object>;
      if (param) {
        this.videoCard = param['videoCard'] as VideoCard;
        this.cid = (param['cid'] as number) || 0;
        this.qn = (param['qn'] as number) || 80;
        this.qnName = (param['qnName'] as string) || '';
        this.durationMs = (param['durationMs'] as number) || 0;
      }
      if (!this.videoCard) {
        this.errorText = '参数错误';
        this.statusText = '无法开始下载';
        return;
      }
      this.title = this.videoCard.title || '未知视频';
      if (!this.qnName) {
        this.qnName = this.getQnLabel(this.qn);
      }
      if (!this.videoCard.bvid || this.cid <= 0) {
        this.errorText = '视频信息不完整';
        this.statusText = '无法开始下载';
        return;
      }
      this.startDownload();
    })
  }

  aboutToAppear(): void {
    this.pageAlive = true;
  }

  aboutToDisappear(): void {
    this.pageAlive = false;
    this.downloader?.cancel();
  }

  private getQnLabel(qn: number): string {
    if (qn === 120) {
      return '4K';
    }
    if (qn === 116) {
      return '1080P60';
    }
    if (qn === 80) {
      return '1080P';
    }
    if (qn === 74) {
      return '720P60';
    }
    if (qn === 64) {
      return '720P';
    }
    if (qn === 32) {
      return '480P';
    }
    if (qn === 16) {
      return '360P';
    }
    return 'qn' + qn.toString();
  }

  private async startDownload(): Promise<void> {
    if (this.started) {
      return;
    }
    this.started = true;
    this.errorText = '';
    this.isDone = false;
    this.isDownloading = true;
    this.percent = 0;
    this.statusText = '正在解析视频地址...';
    this.lastTickMs = 0;
    let downloader: HttpFileDownloader = new HttpFileDownloader();
    this.downloader = downloader;

    let context: common.UIAbilityContext | undefined =
      AppStorage.get<common.UIAbilityContext>('UiAbilityContext');
    if (!context) {
      this.fail('无法获取应用上下文');
      return;
    }

    try {
      let streams: CacheStreamResult = await getCacheStreams(this.videoCard.bvid, this.cid, this.qn);
      if (!this.pageAlive || downloader.isCancelled()) {
        return;
      }

      let existing: CachedVideo | null = findCachedVideo(context, this.videoCard.bvid, this.cid, this.qn);

      let cacheDir: string = ensureCacheDir(context);
      let stamp: number = Date.now();
      let baseName: string = this.videoCard.bvid + '_' + this.cid.toString() + '_' + this.qn.toString()
        + '_' + stamp.toString();
      this.videoPath = cacheDir + '/' + baseName + (streams.isDash ? '_video.m4s' : '.mp4');
      this.audioPath = streams.isDash
        ? cacheDir + '/' + baseName + '_audio.m4s'
        : '';

      this.statusText = streams.isDash ? '正在下载视频...' : '正在下载...';
      let videoBytes: number = await downloader.download(streams.videoUrl, this.videoPath,
        (tick: DownloadTick) => {
          this.onFileTick(tick, 0, streams);
        });
      if (!this.pageAlive || downloader.isCancelled()) {
        return;
      }

      let audioBytes: number = 0;
      if (this.audioPath) {
        this.statusText = '正在下载音频...';
        this.percent = Math.max(this.percent, 85);
        audioBytes = await downloader.download(streams.audioUrl, this.audioPath,
          (tick: DownloadTick) => {
            this.onFileTick(tick, 1, streams);
          });
        if (!this.pageAlive || downloader.isCancelled()) {
          return;
        }
      }

      if (videoBytes <= 0) {
        throw new Error('视频文件为空');
      }

      let entry: CachedVideo = new CachedVideo();
      entry.bvid = this.videoCard.bvid;
      entry.aid = this.videoCard.aid;
      if (entry.aid <= 0) {
        try {
          entry.aid = bv2av(this.videoCard.bvid);
        } catch (_e) {
          entry.aid = 0;
        }
      }
      entry.cid = this.cid;
      entry.qn = this.qn;
      entry.qnName = this.qnName;
      entry.title = this.title;
      entry.upName = this.videoCard.upName;
      entry.cover = this.videoCard.cover;
      entry.videoPath = this.videoPath;
      entry.audioPath = this.audioPath;
      entry.isDash = streams.isDash;
      entry.durationMs = streams.durationMs > 0 ? streams.durationMs : this.durationMs;
      entry.totalBytes = videoBytes + audioBytes;
      entry.createdAt = Date.now();
      // 下载成功后才替换旧缓存，避免失败时丢失已有缓存
      if (existing !== null) {
        removeCachedVideo(context, existing);
      }
      addCachedVideo(context, entry);

      this.savedEntry = entry;
      this.percent = 100;
      this.isDone = true;
      this.isDownloading = false;
      this.statusText = '缓存完成 · ' + formatBytes(entry.totalBytes);
      this.getUIContext().getPromptAction().showToast({ message: '缓存完成' });
    } catch (e) {
      if (!this.pageAlive || downloader.isCancelled()) {
        return;
      }
      this.cleanupPartialFiles();
      this.fail(e instanceof Error ? e.message : String(e));
    }
  }

  private onFileTick(tick: DownloadTick, stage: number, streams: CacheStreamResult): void {
    if (!this.pageAlive) {
      return;
    }
    let estimatedTotal: number = streams.estimatedBytes;
    if (estimatedTotal <= 0 && this.durationMs > 0) {
      estimatedTotal = this.getEstimatedBytesFromBitrate();
    }

    let fileProgress: number = 0;
    if (tick.totalBytes > 0) {
      fileProgress = tick.receivedBytes / tick.totalBytes;
    } else if (estimatedTotal > 0) {
      let estimate: number = stage === 0
        ? (streams.isDash ? estimatedTotal * 0.85 : estimatedTotal)
        : estimatedTotal * 0.15;
      fileProgress = estimate > 0 ? tick.receivedBytes / estimate : 0;
    }
    fileProgress = Math.max(0, Math.min(1, fileProgress));

    let overall: number = stage === 0
      ? (streams.isDash ? fileProgress * 85 : fileProgress * 100)
      : 85 + fileProgress * 15;
    let newPercent: number = Math.min(99, Math.floor(overall));

    let now: number = Date.now();
    if (newPercent === this.percent && now - this.lastTickMs < 200) {
      return;
    }
    this.lastTickMs = now;
    this.percent = newPercent;
  }

  /** 无 Content-Length 时按清晰度码率估算总大小 */
  private getEstimatedBytesFromBitrate(): number {
    if (this.durationMs <= 0) {
      return 0;
    }
    let bitrate: number = 3000000;
    if (this.qn <= 16) {
      bitrate = 400000;
    } else if (this.qn <= 32) {
      bitrate = 800000;
    } else if (this.qn <= 64) {
      bitrate = 1600000;
    } else if (this.qn <= 80) {
      bitrate = 3000000;
    } else {
      bitrate = 5000000;
    }
    return Math.floor(bitrate / 8 * (this.durationMs / 1000));
  }

  private fail(message: string): void {
    this.isDownloading = false;
    this.isDone = false;
    this.errorText = message;
    this.statusText = '下载失败';
  }

  private cleanupPartialFiles(): void {
    this.deleteFile(this.videoPath);
    this.deleteFile(this.audioPath);
  }

  private deleteFile(path: string): void {
    if (!path) {
      return;
    }
    try {
      if (fileIo.accessSync(path)) {
        fileIo.unlinkSync(path);
      }
    } catch (_e) { /* ignore */ }
  }

  private cancelAndExit(): void {
    if (this.isDone) {
      this.pageStack.pop();
      return;
    }
    this.downloader?.cancel();
    this.cleanupPartialFiles();
    this.pageStack.pop();
  }

  private retry(): void {
    this.started = false;
    this.savedEntry = null;
    this.percent = 0;
    this.errorText = '';
    this.startDownload();
  }

  private openOfflinePlayer(): void {
    let entry: CachedVideo | null = this.savedEntry;
    if (entry === null) {
      return;
    }
    this.pageStack.pushPath({
      name: 'VideoPlayer',
      param: createOfflinePlayParam(entry)
    });
  }
}
