/**
 * HTTP 流式文件下载器
 *
 * 使用 requestInStream + dataReceive 将视频/音频流直接写入沙箱文件，
 * 避免大文件整块读入内存。
 */

import { http } from '@kit.NetworkKit';
import { fileIo } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { getCookieString } from '../api/CookiesApi';
import { HEADERS } from '../api/CommonApi';

export interface DownloadTick {
  receivedBytes: number;
  totalBytes: number;
  /** 0-100；无法确定总大小时为 -1 */
  percent: number;
}

export type DownloadTickCallback = (tick: DownloadTick) => void;

export class HttpFileDownloader {
  private request: http.HttpRequest | null = null;
  private file: fileIo.File | null = null;
  private cancelled: boolean = false;
  private activePath: string = '';
  private rejectFn: ((error: Error) => void) | null = null;

  isCancelled(): boolean {
    return this.cancelled;
  }

  /** 取消当前下载，并删除未完成的文件 */
  cancel(): void {
    if (this.cancelled) {
      return;
    }
    this.cancelled = true;
    try {
      this.request?.destroy();
    } catch (_e) { /* ignore */
    }
    this.request = null;
    this.closeFile(true);
    let reject: ((error: Error) => void) | null = this.rejectFn;
    this.rejectFn = null;
    if (reject) {
      reject(new Error('下载已取消'));
    }
  }

  /**
   * 下载单个文件
   * @returns 实际写入的字节数
   */
  async download(url: string, filePath: string, onTick: DownloadTickCallback): Promise<number> {
    this.cancelled = false;
    this.activePath = filePath;
    this.deleteFile(filePath);

    let file: fileIo.File = fileIo.openSync(filePath,
      fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
    this.file = file;

    let req: http.HttpRequest = http.createHttp();
    this.request = req;

    let headers: Record<string, string> = {
      'User-Agent': HEADERS['User-Agent'],
      'Referer': HEADERS['Referer'],
      'Origin': HEADERS['Origin'],
      'Accept': '*/*'
    };
    let cookie: string = getCookieString();
    if (cookie) {
      headers['Cookie'] = cookie;
    }

    let options: http.HttpRequestOptions = {
      method: http.RequestMethod.GET,
      header: headers,
      connectTimeout: 15000,
      // 大文件下载不设读取超时，避免传输被中断
      readTimeout: 0,
      usingCache: false
    };

    return new Promise<number>((resolve, reject) => {
      let settled: boolean = false;
      let totalBytes: number = 0;
      let receivedBytes: number = 0;

      let fail = (message: string): void => {
        if (settled) {
          return;
        }
        settled = true;
        this.rejectFn = null;
        this.request = null;
        try {
          req.destroy();
        } catch (_e) { /* ignore */
        }
        this.closeFile(true);
        reject(new Error(message));
      };

      this.rejectFn = (error: Error): void => {
        if (settled) {
          return;
        }
        settled = true;
        this.closeFile(true);
        reject(error);
      };

      req.on('dataReceiveProgress', (info: http.DataReceiveProgressInfo) => {
        totalBytes = info.totalSize;
      });

      req.on('dataReceive', (data: ArrayBuffer) => {
        if (settled || this.cancelled) {
          return;
        }
        try {
          fileIo.writeSync(file.fd, data);
        } catch (_e) {
          fail('写入缓存文件失败');
          return;
        }
        receivedBytes += data.byteLength;
        let percent: number = totalBytes > 0 ? receivedBytes * 100 / totalBytes : -1;
        let tick: DownloadTick = {
          receivedBytes: receivedBytes,
          totalBytes: totalBytes,
          percent: Math.min(99, percent < 0 ? -1 : percent)
        };
        onTick(tick);
      });

      req.on('dataEnd', () => {
        if (settled) {
          return;
        }
        settled = true;
        this.rejectFn = null;
        this.request = null;
        this.closeFile(false);
        this.activePath = '';
        try {
          req.destroy();
        } catch (_e) { /* ignore */
        }
        resolve(receivedBytes);
      });

      req.requestInStream(url, options).then((code: number) => {
        if (code !== 200 && code !== 206) {
          fail('HTTP ' + code);
        }
      }).catch((err: BusinessError) => {
        if (this.cancelled) {
          return;
        }
        fail(err.message || '网络错误');
      });
    });
  }

  private closeFile(deleteFile: boolean): void {
    let f: fileIo.File | null = this.file;
    this.file = null;
    if (f) {
      try {
        fileIo.closeSync(f);
      } catch (_e) { /* ignore */
      }
    }
    if (deleteFile) {
      this.deleteFile(this.activePath);
      this.activePath = '';
    }
  }

  private deleteFile(path: string): void {
    if (!path) {
      return;
    }
    try {
      if (fileIo.accessSync(path)) {
        fileIo.unlinkSync(path);
      }
    } catch (_e) { /* ignore */
    }
  }
}
