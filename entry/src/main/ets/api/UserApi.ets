/**
 * Bilibili 用户相关 API
 *
 */

import { FavFolder } from '../model/FavFolder';
import { UserCard, UserDetailCard } from '../model/UserCard';
import { VideoCard, ArticleCard } from '../model/ContentCard';
import { ApiResponse, formatCount, httpGet, httpPostForm } from './CommonApi';
import { signWBI } from './WbiSign';
import { getCookieValue } from './CookiesApi';

// ===== 类型定义 =====

/** 指定用户创建的收藏夹列表返回结果 */
export interface CreatedFavFolderResult {
  count: number; // 收藏夹总数
  folders: FavFolder[]; // 收藏夹列表
}

// ===== API =====

/**
 * 根据 UserCard 获取完整用户详情 UserDetailCard
 *
 * @param userCard 至少包含 mid 的 UserCard 对象
 * @returns 完整的 UserDetailCard，网络异常时返回基于输入构造的默认对象（各字段为默认值）
 */
export async function getUserDetail(userCard: UserCard): Promise<UserDetailCard> {
  // 基于输入构建默认结果
  let detail: UserDetailCard = new UserDetailCard(
    userCard.name,
    userCard.headImage,
    userCard.mid,
    userCard.isVip ?? false,
    userCard.level ?? '',
    userCard.desc ?? '',
    '', // sex
    false, // silence
    false, // is_followed
    0, // followings
    0, // followers
    0, // favourites
    0, // video
    0// opus
  );

  if (!userCard || userCard.mid <= 0) {
    console.warn('[UserApi] getUserDetail: 无效的 mid=' + userCard?.mid);
    return detail;
  }

  let midStr: string = userCard.mid.toString();

  try {
    // 并发请求 3 个 API
    let GeneratedDestructArray_1 = await Promise.all([
      httpGet('https://api.bilibili.com/x/web-interface/card?mid=' + midStr + '&photo=false'),
      httpGet('https://api.bilibili.com/x/relation/stat?vmid=' + midStr),
      httpGet('https://api.bilibili.com/x/space/navnum?mid=' + midStr)
    ]);
    let cardResp = GeneratedDestructArray_1[0];
    let relationResp = GeneratedDestructArray_1[1];
    let navnumResp = GeneratedDestructArray_1[2];

    // ===== 1. 用户名片信息 =====
    if (cardResp.code === 0 && cardResp.data) {
      let dataObj: Record<string, Object> = cardResp.data as Record<string, Object>;
      let card: Record<string, Object> = dataObj['card'] as Record<string, Object>;

      if (card) {
        detail.name = (card['name'] as string) || detail.name;
        detail.headImage = (card['face'] as string) || detail.headImage;
        detail.sex = (card['sex'] as string) || '';
        detail.desc = (card['sign'] as string) || detail.desc;

        // 等级（number 0-6 → string）
        let levelInfo: Record<string, Object> = card['level_info'] as Record<string, Object>;
        if (levelInfo) {
          let currentLevel: number = (levelInfo['current_level'] as number) ?? -1;
          if (currentLevel >= 0) {
            detail.level = currentLevel.toString();
          }
        }

        // 大会员状态
        let vip: Record<string, Object> = card['vip'] as Record<string, Object>;
        if (vip) {
          detail.isVip = (vip['vipStatus'] as number) === 1;
        }

        // 封禁状态（spacesta: 0=正常, -2=被封）
        let spacesta: number = (card['spacesta'] as number) ?? 0;
        detail.silence = (spacesta === -2);
      }

      // 是否已关注（data.following 为 bool）
      detail.is_followed = (dataObj['following'] as boolean) ?? false;
    }

    // ===== 2. 关系状态数（关注/粉丝） =====
    if (relationResp.code === 0 && relationResp.data) {
      let relData: Record<string, Object> = relationResp.data as Record<string, Object>;
      detail.followings = (relData['following'] as number) ?? 0;
      detail.followers = (relData['follower'] as number) ?? 0;
    }

    // ===== 3. 用户导航栏状态数（投稿视频、动态、收藏夹） =====
    if (navnumResp.code === 0 && navnumResp.data) {
      let navData: Record<string, Object> = navnumResp.data as Record<string, Object>;
      detail.video = (navData['video'] as number) ?? 0;
      // opus/upos 都是动态数，字段名可能因 API 版本不同
      detail.opus = (navData['opus'] as number) ?? (navData['upos'] as number) ?? 0;

      // 公开收藏夹数
      let favourite: Record<string, Object> = navData['favourite'] as Record<string, Object>;
      if (favourite) {
        detail.favourites = (favourite['guest'] as number) ?? 0;
      }
    }

    console.info('[UserApi] getUserDetail 成功: mid=' + midStr +
      ' name=' + detail.name +
      ' followers=' + detail.followers +
      ' video=' + detail.video);
  } catch (e) {
    console.error('[UserApi] getUserDetail 异常: ' + String(e));
  }

  return detail;
}

// ===== 粉丝 / 关注 =====

/** 粉丝列表翻页结果 */
export interface FollowListResult {
  users: UserCard[];
  total: number;

  /** 是否因隐私设置不可见 */
  invisible: boolean;

  /** 错误消息 */
  message: string;
}

/**
 * 将 API 返回的关系列表 item 转为 UserCard
 */
function relationItemToUserCard(item: Record<string, Object>): UserCard {
  let vip: Record<string, Object> = item['vip'] as Record<string, Object>;
  let isVip: boolean = vip ? (vip['vipStatus'] as number) === 1 : false;

  return new UserCard(
    (item['uname'] as string) || '',
    (item['face'] as string) || '',
    (item['mid'] as number) || 0,
    isVip,
    undefined, // level
    (item['sign'] as string) || ''
  );
}

/**
 * 查询用户的粉丝列表（翻页）
 *
 * @param vmid  目标用户 mid
 * @param pn    页码（默认 1）
 * @param ps    每页数量（默认 50，最大 50）
 * @returns 粉丝列表结果
 */
export async function getUserFans(vmid: number, pn?: number, ps?: number): Promise<FollowListResult> {
  let result: FollowListResult = {
    users: [],
    total: 0,
    invisible: false,
    message: ''
  };

  if (vmid <= 0) {
    console.warn('[UserApi] getUserFans: 无效的 vmid=' + vmid);
    return result;
  }

  let params: string[] = [];
  params.push('vmid=' + vmid.toString());
  params.push('pn=' + ((pn ?? 1).toString()));
  params.push('ps=' + ((ps ?? 50).toString()));

  let url: string = 'https://api.bilibili.com/x/relation/fans?' + params.join('&');

  try {
    let resp: ApiResponse = await httpGet(url);

    if (resp.code === 22118) {
      result.invisible = true;
      result.message = '该用户设置了隐私保护，粉丝列表不可见';
      console.warn('[UserApi] getUserFans: 隐私设置不可见, vmid=' + vmid);
      return result;
    }

    if (resp.code !== 0) {
      result.message = resp.message;
      console.warn('[UserApi] getUserFans 失败: code=' + resp.code + ' msg=' + resp.message);
      return result;
    }

    if (!resp.data) {
      return result;
    }

    let dataObj: Record<string, Object> = resp.data as Record<string, Object>;
    result.total = (dataObj['total'] as number) ?? 0;

    let listArr: Object[] | undefined = dataObj['list'] as Object[] | undefined;
    if (!listArr) {
      return result;
    }

    for (let i: number = 0; i < listArr.length; i++) {
      let item: Record<string, Object> = listArr[i] as Record<string, Object>;
      result.users.push(relationItemToUserCard(item));
    }

    console.info('[UserApi] getUserFans 成功: vmid=' + vmid +
      ' total=' + result.total + ' loaded=' + result.users.length);
  } catch (e) {
    console.error('[UserApi] getUserFans 异常: ' + String(e));
  }

  return result;
}

/**
 * 查询用户的关注列表（翻页）
 *
 * @param vmid  目标用户 mid
 * @param pn    页码（默认 1）
 * @param ps    每页数量（默认 50，最大 50）
 * @returns 关注列表结果
 */
export async function getUserFollowings(vmid: number, pn?: number, ps?: number): Promise<FollowListResult> {
  let result: FollowListResult = {
    users: [],
    total: 0,
    invisible: false,
    message: ''
  };

  if (vmid <= 0) {
    console.warn('[UserApi] getUserFollowings: 无效的 vmid=' + vmid);
    return result;
  }

  let params: string[] = [];
  params.push('vmid=' + vmid.toString());
  params.push('pn=' + ((pn ?? 1).toString()));
  params.push('ps=' + ((ps ?? 50).toString()));

  let url: string = 'https://api.bilibili.com/x/relation/followings?' + params.join('&');

  try {
    let resp: ApiResponse = await httpGet(url);

    // 隐私设置：22115 或 22118
    if (resp.code === 22115 || resp.code === 22118) {
      result.invisible = true;
      result.message = '该用户设置了隐私保护，关注列表不可见';
      console.warn('[UserApi] getUserFollowings: 隐私设置不可见, vmid=' + vmid);
      return result;
    }

    if (resp.code !== 0) {
      result.message = resp.message;
      console.warn('[UserApi] getUserFollowings 失败: code=' + resp.code + ' msg=' + resp.message);
      return result;
    }

    if (!resp.data) {
      return result;
    }

    let dataObj: Record<string, Object> = resp.data as Record<string, Object>;
    result.total = (dataObj['total'] as number) ?? 0;

    let listArr: Object[] | undefined = dataObj['list'] as Object[] | undefined;
    if (!listArr) {
      return result;
    }

    for (let i: number = 0; i < listArr.length; i++) {
      let item: Record<string, Object> = listArr[i] as Record<string, Object>;
      result.users.push(relationItemToUserCard(item));
    }

    console.info('[UserApi] getUserFollowings 成功: vmid=' + vmid +
      ' total=' + result.total + ' loaded=' + result.users.length);
  } catch (e) {
    console.error('[UserApi] getUserFollowings 异常: ' + String(e));
  }

  return result;
}

// ===== 投稿视频 =====

/** 投稿视频列表翻页结果 */
export interface VideoListResult {
  videos: VideoCard[];
  total: number;
  message: string;
}

/**
 * 查询用户投稿视频列表（翻页）
 *
 * @param mid  目标用户 mid
 * @param pn   页码（默认 1）
 * @param ps   每页数量（默认 30，最大 50）
 * @returns 视频列表结果
 */
export async function getUserVideos(mid: number, pn?: number, ps?: number): Promise<VideoListResult> {
  let result: VideoListResult = {
    videos: [],
    total: 0,
    message: ''
  };

  if (mid <= 0) {
    console.warn('[UserApi] getUserVideos: 无效的 mid=' + mid);
    return result;
  }

  let params: string[] = [];
  params.push('mid=' + mid.toString());
  params.push('pn=' + ((pn ?? 1).toString()));
  params.push('ps=' + ((ps ?? 30).toString()));

  let url: string = 'https://api.bilibili.com/x/space/wbi/arc/search?' + params.join('&');

  try {
    url = await signWBI(url);
    console.log("[UserApi] url=" + url)
    let resp: ApiResponse = await httpGet(url);

    if (resp.code !== 0) {
      result.message = resp.message;
      console.warn('[UserApi] getUserVideos 失败: code=' + resp.code + ' msg=' + resp.message);
      return result;
    }

    if (!resp.data) {
      return result;
    }

    let dataObj: Record<string, Object> = resp.data as Record<string, Object>;

    // 分页信息
    let pageObj: Record<string, Object> = dataObj['page'] as Record<string, Object>;
    if (pageObj) {
      result.total = (pageObj['count'] as number) ?? 0;
    }

    // 视频列表嵌套在 data.list.vlist
    let listObj: Record<string, Object> = dataObj['list'] as Record<string, Object>;
    if (!listObj) {
      return result;
    }

    let vlistArr: Object[] | undefined = listObj['vlist'] as Object[] | undefined;
    if (!vlistArr) {
      return result;
    }

    for (let i: number = 0; i < vlistArr.length; i++) {
      let item: Record<string, Object> = vlistArr[i] as Record<string, Object>;

      let video: VideoCard = new VideoCard(
        (item['title'] as string) || '',
        (item['author'] as string) || '',
        formatCount((item['play'] as number) ?? 0),
        (item['pic'] as string) || '',
        (item['aid'] as number) || 0,
        (item['bvid'] as string) || ''
      );

      result.videos.push(video);
    }

    console.info('[UserApi] getUserVideos 成功: mid=' + mid +
      ' total=' + result.total + ' loaded=' + result.videos.length);
  } catch (e) {
    console.error('[UserApi] getUserVideos 异常: ' + String(e));
  }

  return result;
}

// ===== 投稿专栏 =====

/** 投稿专栏列表翻页结果 */
export interface ArticleListResult {
  articles: ArticleCard[];
  total: number;
  message: string;
}

/**
 * 查询用户投稿专栏列表（翻页）
 *
 * @param mid   目标用户 mid
 * @param pn    页码（默认 1）
 * @param ps    每页数量（默认 30，范围 [1, 30]）
 * @param sort  排序方式，'publish_time'=最新发布, 'view'=最多阅读（默认 'publish_time'）
 * @returns 专栏列表结果
 */
export async function getUserArticles(mid: number, pn?: number, ps?: number,
  sort?: string): Promise<ArticleListResult> {
  let result: ArticleListResult = {
    articles: [],
    total: 0,
    message: ''
  };

  if (mid <= 0) {
    console.warn('[UserApi] getUserArticles: 无效的 mid=' + mid);
    return result;
  }

  let params: string[] = [];
  params.push('mid=' + mid.toString());
  params.push('pn=' + ((pn ?? 1).toString()));
  params.push('ps=' + ((ps ?? 30).toString()));
  params.push('sort=' + (sort ?? 'publish_time'));

  let url: string = 'https://api.bilibili.com/x/space/wbi/article?' + params.join('&');

  try {
    url = await signWBI(url);
    let resp: ApiResponse = await httpGet(url);

    if (resp.code !== 0) {
      result.message = resp.message;
      console.warn('[UserApi] getUserArticles 失败: code=' + resp.code + ' msg=' + resp.message);
      return result;
    }

    if (!resp.data) {
      return result;
    }

    let dataObj: Record<string, Object> = resp.data as Record<string, Object>;
    result.total = (dataObj['count'] as number) ?? 0;

    let articlesArr: Object[] | undefined = dataObj['articles'] as Object[] | undefined;
    if (!articlesArr) {
      return result;
    }

    for (let i: number = 0; i < articlesArr.length; i++) {
      let item: Record<string, Object> = articlesArr[i] as Record<string, Object>;

      // 提取作者名
      let author: Record<string, Object> = item['author'] as Record<string, Object>;
      let upName: string = author ? ((author['name'] as string) || '') : '';

      // 提取阅读数
      let stats: Record<string, Object> = item['stats'] as Record<string, Object>;
      let view: string = stats ? formatCount((stats['view'] as number) ?? 0) : '0';

      // 提取封面图列表
      let covers: string[] = [];
      let imageUrlsArr: Object[] | undefined = item['image_urls'] as Object[] | undefined;
      if (imageUrlsArr) {
        for (let j: number = 0; j < imageUrlsArr.length; j++) {
          covers.push(imageUrlsArr[j] as string);
        }
      }

      let article: ArticleCard = new ArticleCard(
        (item['title'] as string) || '',
        upName,
        view,
        covers,
        (item['id'] as number) || 0
      );

      result.articles.push(article);
    }

    console.info('[UserApi] getUserArticles 成功: mid=' + mid +
      ' total=' + result.total + ' loaded=' + result.articles.length);
  } catch (e) {
    console.error('[UserApi] getUserArticles 异常: ' + String(e));
  }

  return result;
}

// ===== 关注 / 取关 =====

/** 关注操作结果 */
export interface ModifyRelationResult {
  success: boolean;
  code: number;
  message: string;
}

/** 可用的操作代码 */
export enum RelationAct {
  FOLLOW = 1, // 关注
  UNFOLLOW = 2, // 取关
  UNSUB_SILENT = 4, // 取消悄悄关注
  BLOCK = 5, // 拉黑
  UNBLOCK = 6, // 取消拉黑
  KICK_FAN = 7 // 踢出粉丝
}

/**
 * 操作用户关系（关注/取关/拉黑等）
 *
 * @param fid  目标用户 mid
 * @param act  操作代码（建议使用 RelationAct 枚举）
 * @returns 操作结果
 */
export async function modifyRelation(fid: number, act: RelationAct): Promise<ModifyRelationResult> {
  let result: ModifyRelationResult = {
    success: false,
    code: -1,
    message: ''
  };

  if (fid <= 0) {
    result.message = '无效的目标用户 mid';
    console.warn('[UserApi] modifyRelation: 无效的 fid=' + fid);
    return result;
  }

  let csrf: string = getCookieValue('bili_jct');
  if (!csrf) {
    result.code = -101;
    result.message = '未登录，无法操作';
    console.warn('[UserApi] modifyRelation: bili_jct 为空，未登录');
    return result;
  }

  // 构建 POST body
  let body: string = 'fid=' + fid.toString() + '&act=' + act.toString() + '&csrf=' + csrf;

  let actName: string = RelationAct[act] || ('未知(' + act + ')');

  console.info('[UserApi] modifyRelation: fid=' + fid + ' act=' + actName);

  try {
    let resp: ApiResponse = await httpPostForm(
      'https://api.bilibili.com/x/relation/modify',
      body
    );

    result.code = resp.code;
    result.message = resp.message;

    if (resp.code === 0) {
      result.success = true;
      console.info('[UserApi] modifyRelation 成功: fid=' + fid + ' act=' + actName);
    } else {
      console.warn('[UserApi] modifyRelation 失败: fid=' + fid +
        ' act=' + actName + ' code=' + resp.code + ' msg=' + resp.message);
    }
  } catch (e) {
    result.message = String(e);
    console.error('[UserApi] modifyRelation 异常: ' + String(e));
  }

  return result;
}

/**
 * 快捷关注用户
 *
 * @param fid 目标用户 mid
 * @returns 操作结果
 */
export async function followUser(fid: number): Promise<ModifyRelationResult> {
  return modifyRelation(fid, RelationAct.FOLLOW);
}

/**
 * 快捷取关用户
 *
 * @param fid 目标用户 mid
 * @returns 操作结果
 */
export async function unfollowUser(fid: number): Promise<ModifyRelationResult> {
  return modifyRelation(fid, RelationAct.UNFOLLOW);
}

// ===== 收藏夹视频 =====

/** 收藏夹内容明细列表翻页结果 */
export interface FavResourceListResult {
  videos: VideoCard[];
  hasMore: boolean;
  total: number;
  message: string;
}

/**
 * 获取目标收藏夹的所有视频（翻页）
 *
 * @param mediaId  目标收藏夹 mlid（完整 id，必要）
 * @param pn       页码（非必要，默认 1）
 * @param ps       每页数量（非必要，默认 20，范围 1-20）
 * @returns 视频列表和分页信息
 *
 */
export async function getFavResourceList(mediaId: number, pn?: number, ps?: number): Promise<FavResourceListResult> {
  let result: FavResourceListResult = {
    videos: [],
    hasMore: false,
    total: 0,
    message: ''
  };

  if (mediaId <= 0) {
    console.warn('[UserApi] getFavResourceList: 无效的 mediaId=' + mediaId);
    return result;
  }

  let params: string[] = [];
  params.push('media_id=' + mediaId.toString());
  params.push('pn=' + ((pn ?? 1).toString()));
  params.push('ps=' + ((ps ?? 20).toString()));
  params.push('platform=web');

  let url: string = 'https://api.bilibili.com/x/v3/fav/resource/list?' + params.join('&');

  try {
    let resp: ApiResponse = await httpGet(url);

    if (resp.code !== 0) {
      result.message = resp.message;
      console.warn('[UserApi] getFavResourceList 失败: code=' + resp.code + ' msg=' + resp.message);
      return result;
    }

    if (!resp.data) {
      console.warn('[UserApi] getFavResourceList: data 为空, mediaId=' + mediaId);
      return result;
    }

    let dataObj: Record<string, Object> = resp.data as Record<string, Object>;

    // 收藏夹元数据中的内容总数
    let infoObj: Record<string, Object> = dataObj['info'] as Record<string, Object>;
    if (infoObj) {
      result.total = (infoObj['media_count'] as number) ?? 0;
    }

    // 是否还有下一页
    result.hasMore = (dataObj['has_more'] as boolean) ?? false;

    // 收藏夹内容列表
    let mediasArr: Object[] | undefined = dataObj['medias'] as Object[] | undefined;
    if (!mediasArr) {
      return result;
    }

    for (let i: number = 0; i < mediasArr.length; i++) {
      let item: Record<string, Object> = mediasArr[i] as Record<string, Object>;

      // 只提取视频类型（type=2），跳过音频和视频合集
      let itemType: number = (item['type'] as number) ?? 0;
      if (itemType !== 2) {
        continue;
      }

      // 提取 UP 主名
      let upper: Record<string, Object> = item['upper'] as Record<string, Object>;
      let upName: string = upper ? ((upper['name'] as string) || '') : '';

      // 提取播放数
      let cntInfo: Record<string, Object> = item['cnt_info'] as Record<string, Object>;
      let playNum: number = cntInfo ? ((cntInfo['play'] as number) ?? 0) : 0;

      let video: VideoCard = new VideoCard(
        (item['title'] as string) || '',
        upName,
        formatCount(playNum),
        (item['cover'] as string) || '',
        (item['id'] as number) || 0,
        (item['bvid'] as string) || (item['bv_id'] as string) || ''
      );

      result.videos.push(video);
    }

    console.info('[UserApi] getFavResourceList 成功: mediaId=' + mediaId +
      ' total=' + result.total + ' loaded=' + result.videos.length +
      ' hasMore=' + result.hasMore);
  } catch (e) {
    console.error('[UserApi] getFavResourceList 异常: ' + String(e));
  }

  return result;
}

/**
 * 补全单个收藏夹的详细信息（cover、ctime、media_count）
 *
 * @param folder 至少包含 mlid 的 FavFolder 对象
 * @returns 补全后的同一个 FavFolder 对象（原地修改）
 *
 */
export async function fillFavFolderDetail(folder: FavFolder): Promise<FavFolder> {
  if (!folder || folder.mlid <= 0) {
    console.warn('[UserApi] fillFavFolderDetail: 无效的 mlid=' + folder?.mlid);
    return folder;
  }

  let url: string = 'https://api.bilibili.com/x/v3/fav/folder/info?media_id=' + folder.mlid.toString();

  try {
    let resp: ApiResponse = await httpGet(url);

    if (resp.code !== 0) {
      console.error(
        '[UserApi] 获取收藏夹详情失败: mlid=' + folder.mlid + ' code=' + resp.code + ' msg=' + resp.message);
      return folder;
    }

    if (!resp.data) {
      console.warn('[UserApi] 收藏夹详情为空: mlid=' + folder.mlid);
      return folder;
    }

    let d: Record<string, Object> = resp.data as Record<string, Object>;
    folder.cover = (d['cover'] as string) || '';
    folder.ctime = (d['ctime'] as number) || 0;
    folder.media_count = (d['media_count'] as number) || 0;

    // 如果创建时未传 name 或 name 为空，也可以用 API 返回的 title 补上
    if (!folder.name) {
      folder.name = (d['title'] as string) || '';
    }

    console.info('[UserApi] 收藏夹详情已补全: ' + folder.name + ' media_count=' + folder.media_count);
  } catch (e) {
    console.error('[UserApi] 获取收藏夹详情异常: ' + String(e));
  }

  return folder;
}

/**
 * 获取指定用户创建的所有收藏夹
 *
 * @param upMid    目标用户 mid（必要）
 * @param type     目标内容属性（非必要，0=全部 2=视频稿件，默认 0）
 * @param rid      稿件 avid（非必要），传入后响应中的 fav_state 字段表示该稿件是否已加入该收藏夹
 *                 1=已加入，0=未加入。用于在打开收藏面板时预点亮已收藏的收藏夹
 * @returns 收藏夹列表
 */
export async function getUserCreatedFavFolders(upMid: number, type?: number,
  rid?: number): Promise<CreatedFavFolderResult> {
  let result: CreatedFavFolderResult = {
    count: 0,
    folders: []
  };

  // 构建 URL 参数
  let params: string[] = [];
  params.push('up_mid=' + upMid.toString());
  if (type !== undefined) {
    params.push('type=' + type.toString());
  }
  if (rid !== undefined && rid > 0) {
    params.push('rid=' + rid.toString());
    console.info('[UserApi] rid=' + rid);
  }

  let url: string = 'https://api.bilibili.com/x/v3/fav/folder/created/list-all?' + params.join('&');

  try {
    let resp: ApiResponse = await httpGet(url);

    if (resp.code !== 0) {
      console.error('[UserApi] 获取收藏夹失败: code=' + resp.code + ' msg=' + resp.message);
      return result;
    }

    if (!resp.data) {
      console.warn('[UserApi] 用户 ' + upMid + ' 无公开收藏夹');
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

      let folder: FavFolder = new FavFolder(
        (item['title'] as string) || '',
        (item['id'] as number) || 0
      );
      folder.fav_state = (item['fav_state'] as number) ?? 0;

      result.folders.push(folder);
    }

    console.info('[UserApi] 用户 ' + upMid + ' 收藏夹数=' + result.count + ' 实际获取=' + result.folders.length);
  } catch (e) {
    console.error('[UserApi] 获取收藏夹异常: ' + String(e));
  }

  return result;
}

// ===== 批量用户名片信息 =====

/**
 * 根据 uid 列表批量获取用户基本信息（用户名、头像、等级、VIP）
 * 返回 data 字段为以 uid 字符串为 key 的对象
 */
export async function getBatchUserCards(uids: number[]): Promise<Map<number, UserCard>> {
  let cardMap: Map<number, UserCard> = new Map();

  if (uids.length === 0) {
    return cardMap;
  }

  let uidsStr: string = uids[0].toString();
  for (let i: number = 1; i < uids.length; i++) {
    uidsStr += ',' + uids[i];
  }

  try {
    let url: string = 'https://api.bilibili.com/x/polymer/pc-electron/v1/user/cards?uids=' + uidsStr;
    let resp: ApiResponse = await httpGet(url);

    if (resp.code !== 0 || !resp.data) {
      console.warn('[UserApi] getBatchUserCards 失败: code=' + resp.code + ' msg=' + resp.message);
      return cardMap;
    }

    let data: Record<string, Object> = resp.data as Record<string, Object>;

    let keys: string[] = Object.keys(data);
    for (let i: number = 0; i < keys.length; i++) {
      let uidKey: string = keys[i];
      let uid: number = parseInt(uidKey);
      if (isNaN(uid) || uid <= 0) {
        continue;
      }

      let cardObj: Record<string, Object> = data[uidKey] as Record<string, Object>;
      if (!cardObj) {
        continue;
      }

      let name: string = (cardObj['name'] as string) || '';
      let face: string = (cardObj['face'] as string) || '';

      // VIP 信息
      let vip: Record<string, Object> | undefined = cardObj['vip'] as Record<string, Object> | undefined;
      let isVip: boolean = false;
      if (vip) {
        let vipType: number = (vip['vipType'] as number) ?? (vip['type'] as number) ?? 0;
        let vipStatus: number = (vip['vipStatus'] as number) ?? (vip['status'] as number) ?? 0;
        isVip = vipType > 0 && vipStatus === 1;
      }

      // 等级信息
      let level: string = '';
      let levelInfo: Record<string, Object> | undefined = cardObj['level_info'] as Record<string, Object> | undefined;
      if (levelInfo && levelInfo['current_level'] !== undefined) {
        level = String(levelInfo['current_level']);
      }

      let userCard: UserCard = new UserCard(name, face, uid, isVip, level);
      cardMap.set(uid, userCard);
    }

    console.info('[UserApi] getBatchUserCards 成功: ' + cardMap.size + ' 个用户');
  } catch (e) {
    console.error('[UserApi] getBatchUserCards 异常: ' + String(e));
  }

  return cardMap;
}
