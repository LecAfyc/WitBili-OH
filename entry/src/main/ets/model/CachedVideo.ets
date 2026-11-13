/**
 * 已缓存视频数据模型
 *
 * 仅保存本地沙箱路径与展示信息，播放时不再访问网络。
 */

export class CachedVideo {
  bvid: string = '';
  aid: number = 0;
  cid: number = 0;
  qn: number = 0;
  qnName: string = '';
  title: string = '';
  upName: string = '';
  cover: string = '';
  videoPath: string = '';
  audioPath: string = '';
  isDash: boolean = false;
  durationMs: number = 0;
  totalBytes: number = 0;
  createdAt: number = 0;
}
