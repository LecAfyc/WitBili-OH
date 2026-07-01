/**
 * Bilibili 搜索 API
 *
 */

import { ApiResponse, formatCount, httpGet } from './CommonApi';
import { ArticleCard, VideoCard } from '../model/ContentCard';
import { UserCard } from '../model/UserCard';
import { signWBI } from './WbiSign';
import { decodeHTML } from './CommonApi';

// ===== 常量 =====

/** 分类搜索 API 地址（需要 WBI 签名） */
const SEARCH_TYPE_URL: string = 'https://api.bilibili.com/x/web-interface/wbi/search/type';

/** 每页条数 */
const PAGE_SIZE: number = 20;

// ===== 工具函数 =====

/**
 * 移除标题中的 XML 高亮标签
 * B 站搜索结果标题会用 <em class="keyword">xxx</em> 标记匹配关键字。
 * 然后调用 decodeHTML() 转义 HTML 字符实体。
 */
function stripEmTags(text: string): string {
  let stripped: string = '';
  let inTag: boolean = false;
  for (let i: number = 0; i < text.length; i++) {
    let ch: string = text[i];
    if (ch === '<') {
      inTag = true;
      continue;
    }
    if (ch === '>') {
      inTag = false;
      continue;
    }
    if (!inTag) {
      stripped += ch;
    }
  }
  return decodeHTML(stripped);
}

/**
 * 安全获取字符串字段值（防止 undefined 转换异常）
 */
function safeStr(val: Object | undefined | null, fallback: string): string {
  if (val === undefined || val === null) {
    return fallback;
  }
  return String(val);
}

/**
 * 安全获取数字字段值
 */
function safeNum(val: Object | undefined | null, fallback: number): number {
  if (val === undefined || val === null) {
    return fallback;
  }
  if (typeof val === 'number') {
    return val;
  }
  let n: number = Number(val);
  return isNaN(n) ? fallback : n;
}

// ===== 构建 WBI 签名的 URL =====

/**
 * 给分类搜索 URL 加上 WBI 签名
 */
async function buildSignedSearchUrl(searchType: string, keyword: string, page: number): Promise<string> {
  let query: string = 'search_type=' + encodeURIComponent(searchType) +
    '&keyword=' + encodeURIComponent(keyword) +
    '&page=' + page.toString();

  let url: string = SEARCH_TYPE_URL + '?' + query;
  url = await signWBI(url);
  return url;
}

// ===== 视频搜索 =====

/**
 * 搜索视频
 *
 * 调用 B 站分类搜索接口（search_type=video），返回 VideoCard 数组。
 *
 * @param keyword 搜索关键词（必填，空字符串返回空数组）
 * @param page    页码（从 1 开始，默认 1）
 * @returns VideoCard[] 视频卡片列表
 */
export async function searchVideos(keyword: string, page: number = 1): Promise<VideoCard[]> {
  let kw: string = keyword.trim();
  if (!kw) {
    return [];
  }
  if (page < 1) {
    page = 1;
  }

  console.info('[SearchApi] searchVideos keyword=' + kw + ' page=' + page);

  let url: string = await buildSignedSearchUrl('video', kw, page);
  let resp: ApiResponse = await httpGet(url, { logTag: '[SearchApi]' });

  if (resp.code !== 0) {
    console.warn('[SearchApi] 搜索视频失败: code=' + resp.code + ' msg=' + resp.message);
    return [];
  }
  if (!resp.data) {
    console.warn('[SearchApi] 搜索视频失败: data 为空');
    return [];
  }

  let d: Record<string, Object> = resp.data as Record<string, Object>;
  let rawResults: Object[] | undefined = d['result'] as Object[] | undefined;

  if (!rawResults || rawResults.length === 0) {
    return [];
  }

  console.info('[SearchApi] 视频结果数: ' + rawResults.length);

  let result: VideoCard[] = [];
  for (let i: number = 0; i < rawResults.length; i++) {
    let item: Record<string, Object> = rawResults[i] as Record<string, Object>;

    let type: string = safeStr(item['type'], '');
    if (type !== 'video') {
      continue;
    }

    let title: string = stripEmTags(safeStr(item['title'], ''));
    let author: string = safeStr(item['author'], '');
    let play: number = safeNum(item['play'], 0);
    let pic: string = safeStr(item['pic'], '');
    pic = pic.startsWith("https:") ? pic : "https:" + pic;
    console.info("[SearchApi] pic(processed) = " + pic);
    let aid: number = safeNum(item['aid'], 0);
    let bvid: string = safeStr(item['bvid'], '');

    console.info("[SearchApi] i=" + i + " item=" + JSON.stringify(item));

    result.push(new VideoCard(title, author, formatCount(play), pic, aid, bvid));
  }

  return result;
}

// ===== 用户搜索 =====

/**
 * 搜索用户
 *
 * 调用 B 站分类搜索接口（search_type=bili_user），返回 UserCard 数组。
 *
 * @param keyword 搜索关键词（必填，空字符串返回空数组）
 * @param page    页码（从 1 开始，默认 1）
 * @returns UserCard[] 用户卡片列表
 */
export async function searchUsers(keyword: string, page: number = 1): Promise<UserCard[]> {
  let kw: string = keyword.trim();
  if (!kw) {
    return [];
  }
  if (page < 1) {
    page = 1;
  }

  console.info('[SearchApi] searchUsers keyword=' + kw + ' page=' + page);

  let url: string = await buildSignedSearchUrl('bili_user', kw, page);
  let resp: ApiResponse = await httpGet(url, { logTag: '[SearchApi]' });

  if (resp.code !== 0) {
    console.warn('[SearchApi] 搜索用户失败: code=' + resp.code + ' msg=' + resp.message);
    return [];
  }
  if (!resp.data) {
    console.warn('[SearchApi] 搜索用户失败: data 为空');
    return [];
  }

  let d: Record<string, Object> = resp.data as Record<string, Object>;
  let rawResults: Object[] | undefined = d['result'] as Object[] | undefined;

  if (!rawResults || rawResults.length === 0) {
    return [];
  }

  console.info('[SearchApi] 用户结果数: ' + rawResults.length);

  let result: UserCard[] = [];
  for (let i: number = 0; i < rawResults.length; i++) {
    let item: Record<string, Object> = rawResults[i] as Record<string, Object>;

    // 过滤非 bili_user 类型
    let type: string = safeStr(item['type'], '');
    if (type !== 'bili_user') {
      continue;
    }

    // 必填字段
    let uname: string = stripEmTags(safeStr(item['uname'], ''));
    let upic: string = safeStr(item['upic'], '');
    upic = upic.startsWith("https:") ? upic : "https:" + upic;
    let mid: number = safeNum(item['mid'], 0);

    // 可选字段
    let usign: string = safeStr(item['usign'], '');
    let levelNum: number = safeNum(item['level'], 0);
    let level: string = levelNum.toString();

    // B 站搜索结果中没有 isVip 字段，留空不传
    result.push(new UserCard(uname, upic, mid, undefined, level, usign));
  }

  return result;
}

// ===== 专栏搜索 =====

/**
 * 搜索专栏
 *
 * @param keyword 搜索关键词（必填，空字符串返回空数组）
 * @param page    页码（从 1 开始，默认 1）
 * @returns ArticleCard[] 专栏卡片列表
 */
export async function searchArticles(keyword: string, page: number = 1): Promise<ArticleCard[]> {
  let kw: string = keyword.trim();
  if (!kw) {
    return [];
  }
  if (page < 1) {
    page = 1;
  }

  console.info('[SearchApi] searchArticles keyword=' + kw + ' page=' + page);

  let url: string = await buildSignedSearchUrl('article', kw, page);
  let resp: ApiResponse = await httpGet(url, { logTag: '[SearchApi]' });

  if (resp.code !== 0) {
    console.warn('[SearchApi] 搜索专栏失败: code=' + resp.code + ' msg=' + resp.message);
    return [];
  }
  if (!resp.data) {
    console.warn('[SearchApi] 搜索专栏失败: data 为空');
    return [];
  }

  let d: Record<string, Object> = resp.data as Record<string, Object>;
  let rawResults: Object[] | undefined = d['result'] as Object[] | undefined;

  if (!rawResults || rawResults.length === 0) {
    return [];
  }

  console.info('[SearchApi] 专栏结果数: ' + rawResults.length);

  let result: ArticleCard[] = [];
  for (let i: number = 0; i < rawResults.length; i++) {
    let item: Record<string, Object> = rawResults[i] as Record<string, Object>;

    let type: string = safeStr(item['type'], '');
    if (type !== 'article') {
      continue;
    }

    let title: string = stripEmTags(safeStr(item['title'], ''));
    let view: number = safeNum(item['view'], 0);
    let cvid: number = safeNum(item['id'], 0);

    // image_urls 是封面图组，都保留下来
    let covers: string[] = [];
    let rawCovers: Object[] | undefined = item['image_urls'] as Object[] | undefined;
    if (rawCovers && rawCovers.length > 0) {
      for (let j: number = 0; j < rawCovers.length; j++) {
        let coverUrl: string = safeStr(rawCovers[j], '');
        if (coverUrl) {
          coverUrl = coverUrl.startsWith('https:') ? coverUrl : 'https:' + coverUrl;
          covers.push(coverUrl);
        }
      }
    }

    // 专栏搜索结果不含作者名，upName 留空
    result.push(new ArticleCard(title, '', formatCount(view), covers, cvid));
  }

  return result;
}
