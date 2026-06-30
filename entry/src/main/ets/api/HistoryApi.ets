/**
 * Bilibili 观看历史 & 稍后再看相关 API
 *
 * 接口文档（BAC Document）：
 *   - 上报观看进度: /docs/video/report.html
 *   - 稍后再看:     /docs/historytoview/toview.html
 */

import { ApiResponse, formatCount, httpGet, httpPostForm } from './CommonApi';
import { getCookieValue } from './CookiesApi';
import { VideoCard } from '../model/ContentCard';

// ===== 类型定义 =====

/** 上报观看进度结果 */
export interface ReportProgressResult {
  success: boolean;
  code: number;
  message: string;
}

/** 稍后再看列表结果 */
export interface ToViewListResult {
  items: VideoCard[];
  count: number;
  message: string;
}

/** 稍后再看写操作结果 */
export interface ToViewActionResult {
  success: boolean;
  code: number;
  message: string;
}

/** 历史记录分页游标 */
export interface HistoryCursor {
  max: number;
  viewAt: number;
  business: string;
}

/** 历史记录翻页结果 */
export interface HistoryListResult {
  items: VideoCard[];
  cursor: HistoryCursor;
  hasMore: boolean;
  message: string;
}

// ===== 观看进度上报 =====

/**
 * 上报视频观看进度（双端）
 *
 * 记录用户对某视频的观看进度，B 站将据此恢复播放位置。
 *
 * POST https://api.bilibili.com/x/v2/history/report
 * 认证方式：Cookie（SESSDATA）或 APP Token
 *
 * 注意：
 * - 需要登录（Cookie 中携带 SESSDATA）
 * - 如果需要上报到播放历史，建议周期性调用（如每 15 秒或暂停时），但本函数仅做单次进度上报
 * - progress 为 -1 或大于视频时长时，B 站会标记为已看完
 *
 * @param aid      稿件 avid（必要）
 * @param cid      视频 cid，用于识别分 P（必要）
 * @param progress 观看进度（非必要，单位秒，默认 0）
 * @returns 上报结果（success 为 true 表示成功）
 *
 * 使用示例：
 * ```typescript
 * let result = await reportWatchProgress(13662970, 126654047, 1248);
 * if (result.success) {
 *   console.info('观看进度上报成功');
 * }
 * ```
 */
export async function reportWatchProgress(aid: number, cid: number, progress?: number): Promise<ReportProgressResult> {
  let result: ReportProgressResult = {
    success: false,
    code: -1,
    message: ''
  };

  if (aid <= 0 || cid <= 0) {
    result.message = '无效的 aid 或 cid';
    console.warn('[HistoryApi] reportWatchProgress: 无效参数 aid=' + aid + ' cid=' + cid);
    return result;
  }

  let csrf: string = getCookieValue('bili_jct');
  if (!csrf) {
    result.code = -101;
    result.message = '未登录，无法上报';
    console.warn('[HistoryApi] reportWatchProgress: bili_jct 为空，未登录');
    return result;
  }

  let body: string = 'aid=' + aid.toString() +
    '&cid=' + cid.toString() +
    '&progress=' + ((progress ?? 0).toString()) +
    '&platform=android' +
    '&csrf=' + csrf;

  console.info('[HistoryApi] reportWatchProgress: aid=' + aid + ' cid=' + cid + ' progress=' + (progress ?? 0));

  try {
    let resp: ApiResponse = await httpPostForm(
      'https://api.bilibili.com/x/v2/history/report',
      body
    );

    result.code = resp.code;
    result.message = resp.message;

    if (resp.code === 0) {
      result.success = true;
      console.info('[HistoryApi] reportWatchProgress 成功: aid=' + aid + ' progress=' + (progress ?? 0));
    } else {
      console.warn('[HistoryApi] reportWatchProgress 失败: code=' + resp.code + ' msg=' + resp.message);
    }
  } catch (e) {
    result.message = String(e);
    console.error('[HistoryApi] reportWatchProgress 异常: ' + String(e));
  }

  return result;
}

// ===== 稍后再看 - 添加 =====

/**
 * 将视频加入稍后再看
 *
 * POST https://api.bilibili.com/x/v2/history/toview/add
 *
 * 认证方式：Cookie（SESSDATA）
 * 最多添加 100 个视频到稍后再看列表。
 *
 * @param aid  稿件 avid（非必要，与 bvid 二选一）
 * @param bvid 稿件 bvid（非必要，与 aid 二选一）
 * @returns 操作结果
 *
 * 使用示例：
 * ```typescript
 * let res = await addToView(41687433);
 * if (res.success) console.info('已加入稍后再看');
 * ```
 */
export async function addToView(aid?: number, bvid?: string): Promise<ToViewActionResult> {
  let result: ToViewActionResult = {
    success: false,
    code: -1,
    message: ''
  };

  if (!aid && !bvid) {
    result.message = 'aid 或 bvid 至少提供一项';
    console.warn('[HistoryApi] addToView: 参数为空');
    return result;
  }

  let csrf: string = getCookieValue('bili_jct');
  if (!csrf) {
    result.code = -101;
    result.message = '未登录，无法操作';
    console.warn('[HistoryApi] addToView: bili_jct 为空，未登录');
    return result;
  }

  let body: string = '';
  if (aid !== undefined && aid > 0) {
    body = 'aid=' + aid.toString() + '&csrf=' + csrf;
  } else if (bvid !== undefined && bvid.length > 0) {
    body = 'bvid=' + bvid + '&csrf=' + csrf;
  } else {
    result.message = 'aid 或 bvid 值无效';
    return result;
  }

  console.info('[HistoryApi] addToView: body=' + body);

  try {
    let resp: ApiResponse = await httpPostForm(
      'https://api.bilibili.com/x/v2/history/toview/add',
      body
    );

    result.code = resp.code;
    result.message = resp.message;

    if (resp.code === 0) {
      result.success = true;
      console.info('[HistoryApi] addToView 成功');
    } else {
      console.warn('[HistoryApi] addToView 失败: code=' + resp.code + ' msg=' + resp.message);
    }
  } catch (e) {
    result.message = String(e);
    console.error('[HistoryApi] addToView 异常: ' + String(e));
  }

  return result;
}

// ===== 稍后再看 - 获取列表 =====

/**
 * 获取稍后再看视频列表
 *
 * GET https://api.bilibili.com/x/v2/history/toview
 *
 * 认证方式：Cookie（SESSDATA）
 * 返回的列表按添加顺序排序，最多 100 项。
 * 返回值统一为 VideoCard[]，仅填充 title / upName / formatedView / cover / aid / bvid。
 *
 * @returns 稍后再看视频列表
 *
 * 使用示例：
 * ```typescript
 * let list = await getToViewList();
 * console.info('稍后再看共 ' + list.count + ' 个视频');
 * for (let v of list.items) {
 *   console.info(v.title + ' ' + v.bvid);
 * }
 * ```
 */
export async function getToViewList(): Promise<ToViewListResult> {
  let result: ToViewListResult = {
    items: [],
    count: 0,
    message: ''
  };

  let csrf: string = getCookieValue('bili_jct');
  if (!csrf) {
    result.message = '未登录，无法获取稍后再看';
    console.warn('[HistoryApi] getToViewList: bili_jct 为空，未登录');
    return result;
  }

  console.info('[HistoryApi] getToViewList');

  try {
    let resp: ApiResponse = await httpGet('https://api.bilibili.com/x/v2/history/toview');

    if (resp.code !== 0) {
      result.message = resp.message;
      console.warn('[HistoryApi] getToViewList 失败: code=' + resp.code + ' msg=' + resp.message);
      return result;
    }

    if (!resp.data) {
      return result;
    }

    let dataObj: Record<string, Object> = resp.data as Record<string, Object>;
    result.count = (dataObj['count'] as number) ?? 0;

    let listArr: Object[] | undefined = dataObj['list'] as Object[] | undefined;
    if (!listArr) {
      return result;
    }

    for (let i: number = 0; i < listArr.length; i++) {
      let item: Record<string, Object> = listArr[i] as Record<string, Object>;

      let owner: Record<string, Object> = item['owner'] as Record<string, Object>;
      let ownerName: string = owner ? ((owner['name'] as string) || '') : '';

      let stat: Record<string, Object> = item['stat'] as Record<string, Object>;
      let playNum: number = stat ? ((stat['view'] as number) ?? 0) : 0;

      let video: VideoCard = new VideoCard(
        (item['title'] as string) || '',
        ownerName,
        formatCount(playNum),
        (item['pic'] as string) || '',
        (item['aid'] as number) || 0,
        (item['bvid'] as string) || ''
      );

      result.items.push(video);
    }

    console.info('[HistoryApi] getToViewList 成功: count=' + result.count + ' loaded=' + result.items.length);
  } catch (e) {
    result.message = String(e);
    console.error('[HistoryApi] getToViewList 异常: ' + String(e));
  }

  return result;
}

// ===== 稍后再看 - 删除 =====

/**
 * 从稍后再看列表中删除视频
 *
 * POST https://api.bilibili.com/x/v2/history/toview/del
 *
 * 认证方式：Cookie（SESSDATA）
 * 两个参数互斥：
 *   - 传入 aid：删除指定视频
 *   - 传入 viewed=true：删除所有已观看的视频
 *
 * @param aid    删除的目标记录的 avid（非必要）
 * @param viewed 是否删除所有已观看的视频（非必要，默认 false）
 * @returns 操作结果
 *
 * 使用示例：
 * ```typescript
 * let res = await deleteToView(540580868);
 * let res2 = await deleteToView(undefined, true);
 * ```
 */
export async function deleteToView(aid?: number, viewed?: boolean): Promise<ToViewActionResult> {
  let result: ToViewActionResult = {
    success: false,
    code: -1,
    message: ''
  };

  let csrf: string = getCookieValue('bili_jct');
  if (!csrf) {
    result.code = -101;
    result.message = '未登录，无法操作';
    console.warn('[HistoryApi] deleteToView: bili_jct 为空，未登录');
    return result;
  }

  let body: string = 'csrf=' + csrf;

  if (aid !== undefined && aid > 0) {
    body = 'aid=' + aid.toString() + '&csrf=' + csrf;
    console.info('[HistoryApi] deleteToView: aid=' + aid);
  } else if (viewed === true) {
    body = 'viewed=true&csrf=' + csrf;
    console.info('[HistoryApi] deleteToView: 删除所有已观看');
  } else {
    result.message = '请指定 aid 或设置 viewed=true';
    console.warn('[HistoryApi] deleteToView: 未指定删除目标');
    return result;
  }

  try {
    let resp: ApiResponse = await httpPostForm(
      'https://api.bilibili.com/x/v2/history/toview/del',
      body
    );

    result.code = resp.code;
    result.message = resp.message;

    if (resp.code === 0) {
      result.success = true;
      console.info('[HistoryApi] deleteToView 成功');
    } else {
      console.warn('[HistoryApi] deleteToView 失败: code=' + resp.code + ' msg=' + resp.message);
    }
  } catch (e) {
    result.message = String(e);
    console.error('[HistoryApi] deleteToView 异常: ' + String(e));
  }

  return result;
}

// ===== 观看历史记录 =====

/**
 * 获取观看历史记录列表（游标翻页）
 *
 * GET https://api.bilibili.com/x/web-interface/history/cursor
 *
 * 认证方式：Cookie（SESSDATA）
 *
 * 翻页方式（游标翻页 / 类无限滚动）：
 *   1. 首次调用：不传 max 参数（默认 0），获取第一页
 *   2. 加载下一页：传入上一页返回的 cursor 中的 max 和 viewAt
 *
 * 返回值统一为 VideoCard[]，仅填充 title / upName / cover / aid / bvid。
 * formatedView 无法从本 API 获取，保持默认空字符串。
 *
 * @param max      上一页最后一个记录的历史游标 oid（非必要，默认 0）
 * @param viewAt   上一页最后一个记录的观看时间戳（非必要，默认 0）
 * @param ps       每页数量（非必要，范围 1-30，默认 20）
 * @returns 历史记录列表和翻页游标
 *
 * 使用示例：
 * ```typescript
 * let page1 = await getHistoryList();
 * for (let v of page1.items) {
 *   console.info(v.title + ' ' + v.bvid);
 * }
 *
 * if (page1.hasMore) {
 *   let c = page1.cursor;
 *   let page2 = await getHistoryList(c.max, c.viewAt);
 * }
 * ```
 */
export async function getHistoryList(
  max?: number,
  viewAt?: number,
  ps?: number
): Promise<HistoryListResult> {
  let result: HistoryListResult = {
    items: [],
    cursor: { max: 0, viewAt: 0, business: '' },
    hasMore: false,
    message: ''
  };

  let csrf: string = getCookieValue('bili_jct');
  if (!csrf) {
    result.message = '未登录，无法获取历史记录';
    console.warn('[HistoryApi] getHistoryList: bili_jct 为空，未登录');
    return result;
  }

  let params: string[] = [];
  params.push('max=' + ((max ?? 0).toString()));
  params.push('ps=' + ((ps ?? 20).toString()));
  params.push('type=archive');
  if (viewAt !== undefined && viewAt > 0) {
    params.push('view_at=' + viewAt.toString());
  }

  let url: string = 'https://api.bilibili.com/x/web-interface/history/cursor?' + params.join('&');

  console.info('[HistoryApi] getHistoryList: max=' + (max ?? 0) + ' ps=' + (ps ?? 20));

  try {
    let resp: ApiResponse = await httpGet(url);

    if (resp.code !== 0) {
      result.message = resp.message;
      console.warn('[HistoryApi] getHistoryList 失败: code=' + resp.code + ' msg=' + resp.message);
      return result;
    }

    if (!resp.data) {
      return result;
    }

    let dataObj: Record<string, Object> = resp.data as Record<string, Object>;

    // 游标
    let cursorObj: Record<string, Object> = dataObj['cursor'] as Record<string, Object>;
    if (cursorObj) {
      result.cursor.max = (cursorObj['max'] as number) ?? 0;
      result.cursor.viewAt = (cursorObj['view_at'] as number) ?? 0;
      result.cursor.business = (cursorObj['business'] as string) || '';
    }

    // 是否有更多
    result.hasMore = (dataObj['has_more'] as boolean) ?? false;

    // 历史记录列表
    let listArr: Object[] | undefined = dataObj['list'] as Object[] | undefined;
    if (!listArr) {
      return result;
    }

    for (let i: number = 0; i < listArr.length; i++) {
      let item: Record<string, Object> = listArr[i] as Record<string, Object>;

      // 嵌套的 history 对象含核心 id 信息
      let history: Record<string, Object> = item['history'] as Record<string, Object>;

      let video: VideoCard = new VideoCard(
        (item['title'] as string) || '',
        (item['author_name'] as string) || '',
        '',  // formatedView: 历史记录 API 未提供播放数
        (item['cover'] as string) || (item['covers'] as string) || '',
        (history ? ((history['oid'] as number) || 0) : 0),
        (history ? ((history['bvid'] as string) || '') : '')
      );

      result.items.push(video);
    }

    console.info('[HistoryApi] getHistoryList 成功: loaded=' + result.items.length + ' hasMore=' + result.hasMore);
  } catch (e) {
    result.message = String(e);
    console.error('[HistoryApi] getHistoryList 异常: ' + String(e));
  }

  return result;
}
