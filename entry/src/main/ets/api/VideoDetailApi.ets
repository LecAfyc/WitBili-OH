/**
 * Bilibili 视频详情 API
 *
 */

import { ApiResponse, httpGet, HEADERS } from './CommonApi';
import { UserCard } from '../model/UserCard';
import { VideoCard } from '../model/ContentCard';
import { VideoPage } from '../model/VideoPage';
import { signWBI } from './WbiSign';

// ===== 类型定义 =====

/** 视频详情 API 完整返回，对应 VideoDetailPage 的全部 @State 资源 */
export interface VideoDetailResult {
  pageParam: VideoCard; // title, cover, view(aid,bvid)
  up: UserCard; // name, headImage, mid
  staff: Array<UserCard>; // 合作成员列表（无合作时为空数组）
  staffRoles: Array<string>; // 合作成员角色称谓（与 staff 等长，一一对应）
  danmakus: number;
  time: number; // 发布时间戳（秒）
  duration: number; // 视频总时长（秒）
  tags: Array<string>; // 标签名列表
  desc: string; // 简介（使用 desc 而非 desc_v2）
  like: number;
  coin: number;
  favorite: number;
  share: number;
  pages: Array<VideoPage>; // 分P列表（无分P时长度为0）
}

/** 标签 API 返回的单个标签对象 */
interface TagItem {
  tag_id: number;
  tag_name: string;
  jump_url: string;
}

/** 合作成员原始结构 */
interface StaffRaw {
  mid: number;
  name: string;
  face: string;
  title: string;
  // 还有 follower/vip 等字段，不需要
}

/** 分P原始结构 */
interface PageRaw {
  cid: number;
  page: number;
  part: string;
  duration: number;
}

// ===== 视频流播放地址返回结构（简化版） =====

export interface PlayUrlResult {
  /** 视频流 URL（durl 格式，音视频合一） */
  videoUrl: string;

  /** 弹幕 URL */
  danmakuUrl: string;

  /** 可用清晰度描述列表（如 ["高清 1080P", "高清 720P", ...]） */
  acceptDescription: string[];

  /** 可用清晰度值列表（如 [80, 64, 32]） */
  acceptQuality: number[];

  /** 续播进度（秒） */
  lastPlayTime: number;
}

// ===== 视频基本信息 API =====

/**
 * 获取视频详细信息
 *
 * @param bvid 稿件 bvid
 * @param aid  稿件 avid（与 bvid 二选一，优先使用 bvid）
 */
export async function getVideoDetail(bvid?: string, aid?: number): Promise<VideoDetailResult> {
  // ---- 构建 URL ----
  let url: string = 'https://api.bilibili.com/x/web-interface/view?';
  if (bvid) {
    url += 'bvid=' + encodeURIComponent(bvid);
  } else if (aid !== undefined && aid > 0) {
    url += 'aid=' + aid.toString();
  } else {
    throw new Error('getVideoDetail: 需要 bvid 或 aid');
  }

  // ---- 请求 ----
  let resp: ApiResponse = await httpGet(url);
  if (resp.code !== 0) {
    throw new Error('获取视频详情失败: code=' + resp.code + ' msg=' + resp.message);
  }
  if (!resp.data) {
    throw new Error('获取视频详情失败: data 为空');
  }

  let d: Record<string, Object> = resp.data as Record<string, Object>;

  // ---- 解析 owner ----
  let ownerObj: Record<string, Object> = (d['owner'] as Record<string, Object>) || {};
  let up: UserCard = new UserCard(
    (ownerObj['name'] as string) || '',
    (ownerObj['face'] as string) || '',
    (ownerObj['mid'] as number) || 0
  );

  // ---- 解析 staff（合作成员） ----
  // staff 是可选的——非合作视频无此字段
  let staffArr: Array<UserCard> = [];
  let staffRoles: Array<string> = [];
  let rawStaff: Object[] | undefined = d['staff'] as Object[] | undefined;
  if (rawStaff && rawStaff.length > 0) {
    for (let i: number = 0; i < rawStaff.length; i++) {
      let s: StaffRaw = rawStaff[i] as StaffRaw;
      staffArr.push(new UserCard(
        s.name || '',
        s.face || '',
        s.mid || 0
      ));
      staffRoles.push(s.title || '合作者');
    }
  }

  // ---- 解析 pages（分P列表） ----
  // pages 是可选的——但即使单P也可能有这个字段（长度为1），
  let pagesArr: Array<VideoPage> = [];
  let rawPages: Object[] | undefined = d['pages'] as Object[] | undefined;
  let rawCid: number | undefined = d['cid'] as number | undefined;
  console.info("[VideoDetailApi] Here!")
  console.info("[VideoDetailApi] rawPages=" + JSON.stringify(rawPages))
  console.info("[VideoDetailApi] rawCid=" + JSON.stringify(rawCid))
  if (rawPages && rawPages.length > 0) {
    for (let i: number = 0; i < rawPages.length; i++) {
      let p: PageRaw = rawPages[i] as PageRaw;
      pagesArr.push(new VideoPage(
        p.cid || 0,
        p.page || 0,
        p.part || '',
        p.duration || 0
      ));
    }
  } else if (rawCid) {
    pagesArr.push(new VideoPage(rawCid || 0, 0, '', 0));
    console.info("[VideoDetailApi] cid=" + (rawCid || 0))
  } else {
    console.warn("[VideoDetailApi] 无法获取视频cid")
  }

  // ---- 解析 stat ----
  let statObj: Record<string, Object> = (d['stat'] as Record<string, Object>) || {};
  let viewNum: number = (statObj['view'] as number) || 0;
  let danmakuNum: number = (statObj['danmaku'] as number) || 0;
  let shareNum: number = (statObj['share'] as number) || 0;
  let likeNum: number = (statObj['like'] as number) || 0;
  let coinNum: number = (statObj['coin'] as number) || 0;
  let favoriteNum: number = (statObj['favorite'] as number) || 0;

  // ---- 组装 pageParam（VideoCard） ----
  let bvidStr: string = (d['bvid'] as string) || bvid || '';
  let aidNum: number = (d['aid'] as number) || aid || 0;
  let pageParam: VideoCard = new VideoCard(
    (d['title'] as string) || '',
    up.name,
    viewNum.toString(), // view 是 string，转成字符串
    (d['pic'] as string) || '',
    aidNum,
    bvidStr
  );

  // ---- 提取其他字段 ----
  let pubdate: number = (d['pubdate'] as number) || 0;
  let duration: number = (d['duration'] as number) || 0;
  let descText: string = (d['desc'] as string) || '';

  // ---- 结果 ----
  return {
    pageParam: pageParam,
    up: up,
    staff: staffArr,
    staffRoles: staffRoles,
    danmakus: danmakuNum,
    time: pubdate,
    duration: duration,
    tags: [],
    desc: descText,
    like: likeNum,
    coin: coinNum,
    favorite: favoriteNum,
    share: shareNum,
    pages: pagesArr
  };
}

// ===== 视频标签 API =====

/**
 * 获取视频标签列表
 *
 * 返回 tag_name 字符串数组，方便 UI 直接使用。
 */
export async function getVideoTags(bvid: string): Promise<Array<string>> {
  if (!bvid) {
    return [];
  }

  let url: string = 'https://api.bilibili.com/x/web-interface/view/detail/tag?bvid=' + encodeURIComponent(bvid);
  let resp: ApiResponse = await httpGet(url);

  if (resp.code !== 0 || !resp.data) {
    console.warn('[VideoDetailApi] 获取标签失败, code=' + resp.code);
    return [];
  }

  // data 本身就是标签列表，不是 { tags: [...] }
  let tagArr: Object[] = resp.data as Object[];
  console.info('[VideoDetailApi] tag条数 = ' + tagArr.length);
  if (!tagArr || tagArr.length === 0) {
    return [];
  }

  let result: Array<string> = [];
  for (let i: number = 0; i < tagArr.length; i++) {
    let item: TagItem = tagArr[i] as TagItem;
    if (item.tag_name) {
      result.push(item.tag_name);
    }
  }
  return result;
}


// 这是durl版本视频链接获取，其实B站很少有这样的视频了
// Dash解析请移步VideoStreamApi
/**
 * 获取视频播放地址（durl 格式，音视频合一）
 *
 * @param bvid  稿件 bvid
 * @param cid   分P cid（必填）
 */
export async function getVideoPlayUrl(bvid: string, cid: number): Promise<PlayUrlResult> {
  // 1. 构建原始 URL（使用新 WBI 端点）
  let url: string = 'https://api.bilibili.com/x/player/wbi/playurl?'
    + 'bvid=' + encodeURIComponent(bvid)
    + '&cid=' + cid.toString()
    + '&fnval=16'         // MP4 格式（durl）
    + '&fourk=1'; // 允许 4K 画质

  // 2. WBI 签名（强制要求）
  let signedUrl: string = await signWBI(url);
  console.info('[VideoDetailApi] signed playurl: ' + signedUrl);

  // 3. 发送请求
  let resp: ApiResponse = await httpGet(signedUrl);
  if (resp.code !== 0) {
    throw new Error('获取视频播放地址失败: code=' + resp.code + ' msg=' + resp.message);
  }
  if (!resp.data) {
    throw new Error('获取视频播放地址失败: data 为空');
  }

  let d: Record<string, Object> = resp.data as Record<string, Object>;
  let durl: object[] = d['durl'] as object[] || [];

  if (durl.length === 0) {
    throw new Error('获取视频播放地址失败: durl 为空');
  }

  // 取第一个分片 URL，并清洗转义符（B 站返回的 URL 中 \u0026 需还原为 &）
  let firstSeg: Record<string, Object> = durl[0] as Record<string, Object>;
  let rawUrl: string = (firstSeg['url'] as string) || '';
  let videoUrl: string = rawUrl.replace(/\\u0026/g, '&');

  let descriptions: string[] = d['accept_description'] as string[] || [];
  let qualities: number[] = d['accept_quality'] as number[] || [];
  let lastPlayTime: number = (d['last_play_time'] as number) || 0;

  // 弹幕 URL 保持不变
  let danmakuUrl: string = 'https://comment.bilibili.com/' + cid.toString() + '.xml';

  return {
    videoUrl: videoUrl,
    danmakuUrl: danmakuUrl,
    acceptDescription: descriptions,
    acceptQuality: qualities,
    lastPlayTime: lastPlayTime
  };
}


// ===== 视频可用清晰度列表 =====

export interface VideoQuality {
  name: string;
  qn: number;
}

export async function getVideoQualities(bvid: string, cid: number): Promise<Array<VideoQuality>> {
  let url: string = 'https://api.bilibili.com/x/player/wbi/playurl?'
    + 'bvid=' + encodeURIComponent(bvid)
    + '&cid=' + cid.toString()
    + '&fnval=16'
    + '&fourk=1';

  let signedUrl: string = await signWBI(url);
  let resp: ApiResponse = await httpGet(signedUrl);
  let dataObj: Record<string, Object> | null = resp.data as Record<string, Object> | null;

  if (!dataObj) {
    throw new Error('获取清晰度列表失败: data 为空');
  }

  console.info("[getVideoQualities] resp.data = " + JSON.stringify(dataObj))
  let descriptions: string[] = dataObj['accept_description'] as string[] || [];
  let qualities: number[] = dataObj['accept_quality'] as number[] || [];

  let result: Array<VideoQuality> = [];
  for (let i: number = 0; i < descriptions.length; i++) {
    result.push({
      name: descriptions[i],
      qn: qualities[i] || 0
    });
  }

  return result;
}


// ===== 批量获取视频详情（含标签） =====

/**
 * 一次性获取视频详情 + 标签
 * 内部依次调用 getVideoDetail() 和 getVideoTags()，合并返回。
 */
export async function getFullVideoDetail(bvid?: string, aid?: number): Promise<VideoDetailResult> {
  // 1. 获取基本信息
  let detail: VideoDetailResult = await getVideoDetail(bvid, aid);

  // 2. 获取标签（需要 bvid）
  let bvidStr: string = bvid || detail.pageParam.bvid;
  if (bvidStr) {
    try {
      let tags: Array<string> = await getVideoTags(bvidStr);
      detail.tags = tags;
    } catch (e) {
      console.warn('[VideoDetailApi] 获取标签异常:', String(e));
    }
  }

  return detail;
}
