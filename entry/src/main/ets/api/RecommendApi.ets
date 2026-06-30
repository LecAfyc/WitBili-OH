/**
 * Bilibili 推荐 API
 * 参考 https://api.bilibili.com/x/web-interface/wbi/index/top/feed/rcmd 文档
 * 以及 BiliClient (Android) 项目的 RecommendApi.java
 *
 * 分页机制（用于获取不同推荐内容）：
 *   fresh_idx     — 当前翻页号，从 1 开始
 *   fresh_idx_1h  — 与 fresh_idx 相同
 *   fetch_row     — 本次抓取的最后一行行号，初始 1，每次递归加上本次抓取行数
 *   ps            — 每页条数，默认 12，最大 30
 */

import { VideoCard } from '../model/ContentCard';
import { signWBI } from './WbiSign';
import { ApiResponse, httpGet, HEADERS } from './CommonApi';
import { formatCount, decodeHTML } from './CommonApi';

// ===== 常量 =====
const PAGE_SIZE: number = 12;       // 每页条数（文档说明默认12）
const REFRESH_SKIP_PAGES: number = 6;   // 每次下拉刷新跳过多少页
const LAUNCH_PAGE_RANGE: number = 20;   // 冷启动随机偏移 1~20 页

// ===== 分页游标状态（模块级，跨页面持久化） =====
// 每次冷启动随机偏移起始页，避免每次打开都看到同一批推荐
let currentFreshIdx: number = 1 + Math.floor(Math.random() * LAUNCH_PAGE_RANGE);
let currentFetchRow: number = 1 + (currentFreshIdx - 1) * PAGE_SIZE;
let currentUniqId: number = generateUniqId();

/** 生成新的 uniq_id（每次刷新调用） */
function generateUniqId(): number {
  return Math.floor(Math.random() * (1500000000000 - 1300000000000) + 1300000000000);
}

/**
 * 刷新游标（下拉刷新时调用）
 *
 * 关键设计：不重置回第1页，而是向前跳转若干页。
 * B站推荐API对同一组 fresh_idx/fetch_row 会缓存结果，
 * 如果每次刷新都回到第1页，永远拿不到新内容。
 * 前进跳页 → 服务端返回没见过的推荐 → 刷新有效。
 */
export function resetRecommendCursor(): void {
  // 向前跳页，不是回到原点
  currentFreshIdx += REFRESH_SKIP_PAGES;
  currentFetchRow += REFRESH_SKIP_PAGES * PAGE_SIZE;
  currentUniqId = generateUniqId();
}

// ===== 工具函数（托管至 CommentApi） =====
// formatCount()、decodeHTML() 见 CommentApi.ets




// ===== 推荐 API 返回结构 =====

export interface RecommendResult {
  items: VideoCard[];
}

// ===== 单视频推荐 API =====

/**
 * 获取指定视频下方的相关视频推荐列表
 *
 * GET https://api.bilibili.com/x/web-interface/archive/related
 *
 * 最多返回 40 条推荐视频，返回结构与视频详情接口的 data 对象相同（不含分P信息）。
 *
 * @param aid 稿件 avid（与 bvid 二选一）
 * @param bvid 稿件 bvid（与 aid 二选一）
 * @returns 推荐视频列表
 */
export async function getRelatedVideos(aid?: number, bvid?: string): Promise<VideoCard[]> {
  let result: VideoCard[] = [];

  // 构建 URL
  let url: string = 'https://api.bilibili.com/x/web-interface/archive/related?';
  if (bvid) {
    url += 'bvid=' + encodeURIComponent(bvid);
  } else if (aid !== undefined && aid > 0) {
    url += 'aid=' + aid.toString();
  } else {
    console.warn('[RecommendApi] getRelatedVideos: 需要 aid 或 bvid');
    return result;
  }

  // 发起请求
  let apiResp: ApiResponse = await httpGet(url);
  if (apiResp.code !== 0) {
    console.error('[RecommendApi] getRelatedVideos 错误:', apiResp.code.toString(), apiResp.message);
    return result;
  }

  if (!apiResp.data) {
    return result;
  }

  // data 本身就是数组（非嵌套在对象中）
  let itemArr: Object[] = apiResp.data as Object[];
  if (!itemArr || itemArr.length === 0) {
    return result;
  }

  console.info('[RecommendApi] getRelatedVideos 获取到 ' + itemArr.length.toString() + ' 条推荐');

  for (let i: number = 0; i < itemArr.length; i++) {
    let card: Record<string, Object> = itemArr[i] as Record<string, Object>;
    let itemAid: number = (card['aid'] as number) || 0;
    if (!itemAid) {
      continue;
    }

    let cover: string = (card['pic'] as string) || '';
    let title: string = decodeHTML((card['title'] as string) || '');
    let itemBvid: string = (card['bvid'] as string) || '';

    let upName: string = '';
    let owner: Object | undefined = card['owner'];
    if (owner) {
      let ownerObj: Record<string, Object> = owner as Record<string, Object>;
      upName = (ownerObj['name'] as string) || '';
    }

    let viewStr: string = '0';
    let stat: Object | undefined = card['stat'];
    if (stat) {
      let statObj: Record<string, Object> = stat as Record<string, Object>;
      let viewNum: number = (statObj['view'] as number) || 0;
      viewStr = formatCount(viewNum) + '观看';
    }

    result.push(new VideoCard(title, upName, viewStr, cover, itemAid, itemBvid));
  }

  return result;
}

// ===== 首页推荐 API =====



/**
 * 获取推荐视频列表
 *
 * 分页机制（文档说明）：
 *   fresh_idx     — 当前翻页号，从 1 开始递增
 *   fetch_row     — 本次抓取的最后一行行号，初始 1
 *                   每次请求后: fetch_row = 前次 fetch_row + 前次返回的 item 数量
 *
 * 首次请求不带 fresh_idx / fetch_row → 获取初始推荐
 * 后续请求带上这些参数 → 获取不同推荐内容
 * 刷新 → resetRecommendCursor() 重置游标
 */
export async function getRecommend(): Promise<RecommendResult> {
  let result: RecommendResult = {
    items: []
  };

  // 构建参数
  let params: string[] = [
    'web_location=1430650',
    'feed_version=V8',
    'homepage_ver=1',
    'uniq_id=' + currentUniqId,
    'screen=466-466',
    'fresh_type=4',          // 相关性（值越大越相关）
    'ps=' + PAGE_SIZE.toString()
  ];

  // 关键：传入游标参数以获取不同内容
  // fresh_idx / fresh_idx_1h / fetch_row 均为 1 起始
  params.push('fresh_idx=' + currentFreshIdx.toString());
  params.push('fresh_idx_1h=' + currentFreshIdx.toString());
  params.push('fetch_row=' + currentFetchRow.toString());

  let rawUrl: string = 'https://api.bilibili.com/x/web-interface/wbi/index/top/feed/rcmd?' + params.join('&');

  // WBI 签名
  let signedUrl: string = await signWBI(rawUrl);

  // 发起请求
  let apiResp: ApiResponse = await httpGet(signedUrl);
  if (apiResp.code !== 0) {
    console.error('[RecommendApi] 错误:', apiResp.code.toString(), apiResp.message);
    return result;
  }

  if (!apiResp.data) {
    return result;
  }

  let dataObj: Record<string, Object> = apiResp.data as Record<string, Object>;

  // === 提取视频列表 ===
  let itemArr: Object[] | undefined = dataObj['item'] as Object[] | undefined;
  if (!itemArr) {
    return result;
  }

  // === 更新游标（在解析 item 之前记录数量） ===
  let itemCount: number = itemArr.length;
  currentFreshIdx++;
  currentFetchRow += itemCount;

  for (let i: number = 0; i < itemArr.length; i++) {
    let card: Record<string, Object> = itemArr[i] as Record<string, Object>;
    let bvid: string = (card['bvid'] as string) || '';
    if (!bvid) {
      // 跳过广告卡片（非视频类型）
      continue;
    }

    let cover: string = (card['pic'] as string) || '';
    let title: string = decodeHTML((card['title'] as string) || '');

    let upName: string = '';
    let owner: Object | undefined = card['owner'];
    if (owner) {
      let ownerObj: Record<string, Object> = owner as Record<string, Object>;
      upName = (ownerObj['name'] as string) || '';
    }

    let viewStr: string = '0';
    let stat: Object | undefined = card['stat'];
    if (stat) {
      let statObj: Record<string, Object> = stat as Record<string, Object>;
      let viewNum: number = (statObj['view'] as number) || 0;
      viewStr = formatCount(viewNum) + '观看';
    }

    let aid: number = (card['aid'] as number) || 0;

    result.items.push(new VideoCard(title, upName, viewStr, cover, aid, bvid));
  }

  return result;
}
