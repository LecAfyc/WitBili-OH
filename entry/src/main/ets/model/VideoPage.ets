/**
 * 视频分P（分段）数据模型
 */
export class VideoPage {
  cid: number = 0; // 分P cid
  page: number = 0; // 分P序号（从1开始）
  part: string = ''; // 分P标题
  duration: number = 0; // 分P时长（秒）

  constructor(cid?: number, page?: number, part?: string, duration?: number) {
    if (cid !== undefined) {
      this.cid = cid;
    }
    if (page !== undefined) {
      this.page = page;
    }
    if (part !== undefined) {
      this.part = part;
    }
    if (duration !== undefined) {
      this.duration = duration;
    }
  }
}
