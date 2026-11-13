/**
 * 视频缓存索引管理
 *
 * 缓存文件保存在应用沙箱 filesDir/video_cache 下，
 * 索引保存在同目录的 cache_index.json 中。
 */

import { fileIo } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { CachedVideo } from '../model/CachedVideo';
import { VideoCard } from '../model/ContentCard';

const CACHE_DIR_NAME: string = 'video_cache';
const INDEX_FILE_NAME: string = 'cache_index.json';

/** 确保缓存目录存在并返回目录路径 */
export function ensureCacheDir(context: common.UIAbilityContext): string {
  let dir: string = context.filesDir + '/' + CACHE_DIR_NAME;
  try {
    if (!fileIo.accessSync(dir)) {
      fileIo.mkdirSync(dir, true);
    }
  } catch (e) {
    console.error('[VideoCacheStore] 创建缓存目录失败: ' + String(e));
  }
  return dir;
}

function getIndexPath(context: common.UIAbilityContext): string {
  return ensureCacheDir(context) + '/' + INDEX_FILE_NAME;
}

function parseCachedVideo(raw: Record<string, Object>): CachedVideo {
  let item: CachedVideo = new CachedVideo();
  item.bvid = (raw['bvid'] as string) || '';
  item.aid = (raw['aid'] as number) || 0;
  item.cid = (raw['cid'] as number) || 0;
  item.qn = (raw['qn'] as number) || 0;
  item.qnName = (raw['qnName'] as string) || '';
  item.title = (raw['title'] as string) || '';
  item.upName = (raw['upName'] as string) || '';
  item.cover = (raw['cover'] as string) || '';
  item.videoPath = (raw['videoPath'] as string) || '';
  item.audioPath = (raw['audioPath'] as string) || '';
  item.isDash = raw['isDash'] === true;
  item.durationMs = (raw['durationMs'] as number) || 0;
  item.totalBytes = (raw['totalBytes'] as number) || 0;
  item.createdAt = (raw['createdAt'] as number) || 0;
  return item;
}

/** 读取全部缓存记录（按创建时间倒序） */
export function loadCachedVideos(context: common.UIAbilityContext): CachedVideo[] {
  let indexPath: string = getIndexPath(context);
  if (!fileIo.accessSync(indexPath)) {
    return [];
  }
  try {
    let text: string = fileIo.readTextSync(indexPath);
    if (!text) {
      return [];
    }
    let parsed: Object = JSON.parse(text) as Object;
    if (!(parsed instanceof Array)) {
      return [];
    }
    let rawList: Object[] = parsed as Object[];
    let result: CachedVideo[] = [];
    for (let i: number = 0; i < rawList.length; i++) {
      result.push(parseCachedVideo(rawList[i] as Record<string, Object>));
    }
    result.sort((a: CachedVideo, b: CachedVideo): number => b.createdAt - a.createdAt);
    return result;
  } catch (e) {
    console.error('[VideoCacheStore] 读取索引失败: ' + String(e));
    return [];
  }
}

/** 写入索引文件 */
export function saveCachedVideos(context: common.UIAbilityContext, list: CachedVideo[]): void {
  try {
    let indexPath: string = getIndexPath(context);
    let file = fileIo.openSync(indexPath,
      fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
    try {
      fileIo.writeSync(file.fd, JSON.stringify(list));
    } finally {
      fileIo.closeSync(file);
    }
  } catch (e) {
    console.error('[VideoCacheStore] 写入索引失败: ' + String(e));
  }
}

/** 判断是否为同一条缓存（同一稿件分P的同一清晰度） */
export function isSameCachedVideo(a: CachedVideo, b: CachedVideo): boolean {
  return a.bvid === b.bvid && a.cid === b.cid && a.qn === b.qn;
}

export function findCachedVideo(context: common.UIAbilityContext, bvid: string, cid: number,
  qn: number): CachedVideo | null {
  let list: CachedVideo[] = loadCachedVideos(context);
  for (let i: number = 0; i < list.length; i++) {
    if (list[i].bvid === bvid && list[i].cid === cid && list[i].qn === qn) {
      return list[i];
    }
  }
  return null;
}

/** 新增缓存记录；同稿件同分P同清晰度会被替换 */
export function addCachedVideo(context: common.UIAbilityContext, entry: CachedVideo): void {
  let list: CachedVideo[] = loadCachedVideos(context);
  let result: CachedVideo[] = [];
  for (let i: number = 0; i < list.length; i++) {
    if (!isSameCachedVideo(list[i], entry)) {
      result.push(list[i]);
    }
  }
  result.unshift(entry);
  saveCachedVideos(context, result);
}

function deleteFileIfExists(path: string): void {
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

/** 删除缓存记录及其本地文件 */
export function removeCachedVideo(context: common.UIAbilityContext, target: CachedVideo): void {
  deleteFileIfExists(target.videoPath);
  deleteFileIfExists(target.audioPath);
  let list: CachedVideo[] = loadCachedVideos(context);
  let result: CachedVideo[] = [];
  for (let i: number = 0; i < list.length; i++) {
    if (!isSameCachedVideo(list[i], target)) {
      result.push(list[i]);
    }
  }
  saveCachedVideos(context, result);
}

/** 文件大小展示 */
export function formatBytes(bytes: number): string {
  if (bytes <= 0) {
    return '0 B';
  }
  if (bytes < 1024) {
    return bytes.toString() + ' B';
  }
  if (bytes < 1024 * 1024) {
    return (bytes / 1024).toFixed(1) + ' KB';
  }
  if (bytes < 1024 * 1024 * 1024) {
    return (bytes / 1024 / 1024).toFixed(1) + ' MB';
  }
  return (bytes / 1024 / 1024 / 1024).toFixed(2) + ' GB';
}

/** 构造离线播放页参数 */
export function createOfflinePlayParam(entry: CachedVideo): Record<string, Object> {
  let card: VideoCard = new VideoCard(entry.title, entry.upName, '', entry.cover, entry.aid, entry.bvid);
  let param: Record<string, Object> = {
    'videoCard': card,
    'cid': entry.cid,
    'qn': entry.qn,
    'qnName': entry.qnName,
    'offline': true,
    'localVideoPath': entry.videoPath,
    'localAudioPath': entry.audioPath,
    'localIsDash': entry.isDash,
    'localDurationMs': entry.durationMs
  };
  return param;
}
