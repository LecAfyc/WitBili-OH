/**
 * Bilibili 视频点赞 & 投币 API
 *
 */

import { cookieMap } from './LoginApi';
import { ApiResponse, httpGet, httpPostForm, HEADERS } from './CommonApi';
import { FavFolder } from '../model/FavFolder';

/** 操作结果 */
export interface ActionResult {
  success: boolean;
  message: string;
}


// ===== 判断状态（GET） =====

/**
 * 判断视频是否被点赞
 *
 * @returns true=已点赞 false=未点赞
 */
export async function checkHasLiked(aid: number): Promise<boolean> {
  if (!aid || aid <= 0) {
    return false;
  }
  let url: string = 'https://api.bilibili.com/x/web-interface/archive/has/like?aid=' + aid;
  try {
    let resp: ApiResponse = await httpGet(url);
    if (resp.code !== 0) {
      return false;
    }
    return (resp.data as number) === 1;
  } catch (e) {
    console.warn('[VideoAction] checkHasLiked 失败:', String(e));
    return false;
  }
}

/**
 * 判断视频被投币数量
 *
 * @returns 当前用户投币枚数 0/1/2
 */
export async function checkCoinCount(aid: number): Promise<number> {
  if (!aid || aid <= 0) {
    return 0;
  }
  let url: string = 'https://api.bilibili.com/x/web-interface/archive/coins?aid=' + aid;
  try {
    let resp: ApiResponse = await httpGet(url);
    if (resp.code !== 0 || !resp.data) {
      return 0;
    }
    let d: Record<string, Object> = resp.data as Record<string, Object>;
    return (d['multiply'] as number) || 0;
  } catch (e) {
    console.warn('[VideoAction] checkCoinCount 失败:', String(e));
    return 0;
  }
}


/**
 * 判断视频是否被收藏
 *
 * @param aid 稿件 avid
 * @returns true=已收藏 false=未收藏
 */
export async function checkHasFavoured(aid: number): Promise<boolean> {
  if (!aid || aid <= 0) {
    return false;
  }
  let url: string = 'https://api.bilibili.com/x/v2/fav/video/favoured?aid=' + aid;
  try {
    let resp: ApiResponse = await httpGet(url);
    if (resp.code !== 0 || !resp.data) {
      return false;
    }
    let d: Record<string, Object> = resp.data as Record<string, Object>;
    return (d['favoured'] as boolean) ?? false;
  } catch (e) {
    console.warn('[VideoAction] checkHasFavoured 失败:', String(e));
    return false;
  }
}

// ===== 执行操作（POST） =====

/**
 * 点赞 / 取消点赞视频
 *
 * @param aid  稿件 avid
 * @param like 1=点赞 2=取消赞
 * @returns { success, message }
 */
export async function likeVideo(aid: number, like: number): Promise<ActionResult> {
  // bili_jct 可能不在 cookieMap 中（序列化/恢复问题），从 AppStorage 兜底
  let csrf: string = cookieMap['bili_jct'] || AppStorage.get<string>('csrf') || '';
  if (!csrf) {
    console.warn('[VideoAction] likeVideo: csrf 为空');
    return { success: false, message: '登录状态已失效，请重新登录' };
  }
  console.info('[VideoAction] likeVideo: csrf前4位=' + csrf.substring(0, 4) + ' aid=' + aid);

  let formData: string = 'aid=' + aid + '&like=' + like + '&csrf=' + encodeURIComponent(csrf);
  try {
    let resp: ApiResponse = await httpPostForm('https://api.bilibili.com/x/web-interface/archive/like', formData);
    console.info('[VideoAction] likeVideo 响应 code=' + resp.code + ' msg=' + resp.message);
    if (resp.code === 0) {
      return { success: true, message: like === 1 ? '点赞成功' : '已取消点赞' };
    }
    if (resp.code === 65004) {
      return { success: false, message: '取消点赞失败' };
    }
    if (resp.code === 65006) {
      return { success: false, message: '已经点过赞了' };
    }
    if (resp.code === -111) {
      return { success: false, message: '校验失败，请重新登录' };
    }
    return { success: false, message: '操作失败(' + resp.code + '): ' + resp.message };
  } catch (e) {
    console.error('[VideoAction] likeVideo 异常:', String(e));
    return { success: false, message: '网络异常' };
  }
}

/**
 * 投币视频
 *
 * @param aid      稿件 avid
 * @param multiply 投币数量 1 或 2
 * @returns { success, message }
 */
export async function addCoin(aid: number, multiply: number): Promise<ActionResult> {
  let csrf: string = cookieMap['bili_jct'] || AppStorage.get<string>('csrf') || '';
  if (!csrf) {
    console.warn('[VideoAction] addCoin: csrf 为空');
    return { success: false, message: '登录状态已失效，请重新登录' };
  }
  console.info('[VideoAction] addCoin: csrf前4位=' + csrf.substring(0, 4) + ' aid=' + aid);

  let formData: string = 'aid=' + aid + '&multiply=' + multiply + '&select_like=0&csrf=' + encodeURIComponent(csrf);
  try {
    let resp: ApiResponse = await httpPostForm('https://api.bilibili.com/x/web-interface/coin/add', formData);
    console.info('[VideoAction] addCoin 响应 code=' + resp.code + ' msg=' + resp.message);
    if (resp.code === 0) {
      return { success: true, message: '已投币 ' + multiply + ' 枚' };
    }
    if (resp.code === -104) {
      return { success: false, message: '硬币不足' };
    }
    if (resp.code === 34002) {
      return { success: false, message: '不能给自己投币' };
    }
    if (resp.code === 34004) {
      return { success: false, message: '操作太快了，请稍后再试' };
    }
    if (resp.code === 34005) {
      return { success: false, message: '已达投币上限' };
    }
    return { success: false, message: '投币失败(' + resp.code + '): ' + resp.message };
  } catch (e) {
    console.error('[VideoAction] addCoin 异常:', String(e));
    return { success: false, message: '网络异常' };
  }
}

// ===== 收藏操作（POST） =====

/**
 * 将视频加入/移出指定收藏夹
 *
 * 支持同时添加和删除，适用于用户从收藏半模态中切换选择后的批量提交。
 *
 * @param aid           稿件 avid
 * @param addFolders    要加入的收藏夹列表（取其中 mlid）
 * @param deleteFolders 要移出的收藏夹列表（取其中 mlid），可选
 * @returns { success, message }
 */
export async function addVideoToFavFolders(aid: number, addFolders: FavFolder[],
  deleteFolders?: FavFolder[]): Promise<ActionResult> {
  if (!aid || aid <= 0) {
    return { success: false, message: '无效的 avid' };
  }

  let csrf: string = cookieMap['bili_jct'] || AppStorage.get<string>('csrf') || '';
  if (!csrf) {
    console.warn('[VideoAction] addVideoToFavFolders: csrf 为空');
    return { success: false, message: '登录状态已失效，请重新登录' };
  }

  // 拼接 add_media_ids（逗号分隔的 mlid）
  let addMediaIds: string[] = [];
  if (addFolders) {
    for (let i: number = 0; i < addFolders.length; i++) {
      if (addFolders[i].mlid > 0) {
        addMediaIds.push(addFolders[i].mlid.toString());
      }
    }
  }

  // 拼接 del_media_ids（逗号分隔的 mlid）
  let delMediaIds: string[] = [];
  if (deleteFolders) {
    for (let i: number = 0; i < deleteFolders.length; i++) {
      if (deleteFolders[i].mlid > 0) {
        delMediaIds.push(deleteFolders[i].mlid.toString());
      }
    }
  }

  // 如果 add 和 del 都为空，报错
  if (addMediaIds.length === 0 && delMediaIds.length === 0) {
    return { success: false, message: '请选择至少一个收藏夹' };
  }

  let formData: string = 'rid=' + aid + '&type=2';
  if (addMediaIds.length > 0) {
    formData += '&add_media_ids=' + encodeURIComponent(addMediaIds.join(','));
  }
  if (delMediaIds.length > 0) {
    formData += '&del_media_ids=' + encodeURIComponent(delMediaIds.join(','));
  }
  formData += '&csrf=' + encodeURIComponent(csrf);

  console.info('[VideoAction] addVideoToFavFolders: aid=' + aid +
    ' add=' + addMediaIds.join(',') +
    ' del=' + delMediaIds.join(','));

  try {
    let resp: ApiResponse = await httpPostForm('https://api.bilibili.com/x/v3/fav/resource/deal', formData);
    console.info('[VideoAction] addVideoToFavFolders 响应 code=' + resp.code + ' msg=' + resp.message);

    if (resp.code === 0) {
      return { success: true, message: '已收藏到 ' + addMediaIds.length + ' 个收藏夹' };
    }
    if (resp.code === 11201) {
      return { success: false, message: '已经收藏过了' };
    }
    if (resp.code === 11203) {
      return { success: false, message: '达到收藏上限' };
    }
    if (resp.code === -111) {
      return { success: false, message: '校验失败，请重新登录' };
    }
    if (resp.code === -101) {
      return { success: false, message: '登录状态已失效，请重新登录' };
    }
    if (resp.code === -403) {
      return { success: false, message: '访问权限不足' };
    }
    if (resp.code === 10003) {
      return { success: false, message: '稿件不存在' };
    }
    if (resp.code === -400) {
      return { success: false, message: '请求参数错误' };
    }
    return { success: false, message: '操作失败(' + resp.code + '): ' + resp.message };
  } catch (e) {
    console.error('[VideoAction] addVideoToFavFolders 异常:', String(e));
    return { success: false, message: '网络异常' };
  }
}
