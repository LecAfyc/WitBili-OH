/**
 * 评论区 API
 *
 * 基于 Bilibili BAC 文档的评论区相关接口封装。
 * 只使用翻页加载模式（x/v2/reply），不使用懒加载（需要 Wbi 签名）。
 * 不做热评、投票、粉丝灯牌等未提及功能。
 *
 * 对外函数：
 *   1. getCommentCount(aid) → 视频评论总数
 *   2. getCommentList(aid, pn) → 当前页评论列表 + 总数
 *   3. getCommentReplies(type, oid, root, pn) → 指定评论的回复列表 + 总数
 *   4. likeComment(type, oid, rpid, action) → 点赞/取消赞评论
 *   5. hateComment(type, oid, rpid, action) → 点踩/取消踩评论
 */

import { httpGet, httpPostForm, ApiResponse, decodeHTML } from './CommonApi';
import { cookieMap } from './LoginApi';
import { SingleComment } from '../model/CommentCard';
import { UserCard } from '../model/UserCard';

// ===== 常量 =====

const API_BASE: string = 'https://api.bilibili.com/x/v2/reply';

// ===== 返回包装 =====

export interface PagedComments {
  list: SingleComment[];
  total: number;  // 根评论总数（不是含回复的总数）
}

export interface PagedReplies {
  list: SingleComment[];
  total: number;  // 回复总数
}

// ===== 辅助：将 API JSON 解析为 SingleComment =====

function parseCommentItem(item: Record<string, Object>): SingleComment {
  const comment = new SingleComment();

  // --- member → sender ---
  const member = item['member'] as Record<string, Object> | undefined;
  if (member) {
    const sender = new UserCard();
    sender.name = (member['uname'] as string) ?? '';
    sender.headImage = (member['avatar'] as string) ?? '';
    sender.mid = Number(member['mid'] ?? 0);

    // level_info.current_level
    const levelInfo = member['level_info'] as Record<string, Object> | undefined;
    if (levelInfo && levelInfo['current_level'] !== undefined) {
      sender.level = String(levelInfo['current_level']);
    }

    // vip.vipType → isVip
    const vip = member['vip'] as Record<string, Object> | undefined;
    if (vip) {
      sender.isVip = (vip['vipType'] as number ?? 0) > 0;
    }

    comment.sender = sender;
  }

  // --- 顶层字段 ---
  comment.rpid = (item['rpid'] as number) ?? 0;
  comment.oid = (item['oid'] as number) ?? 0;

  // --- reply_control → time_desc / ip_desc ---
  const replyCtrl = item['reply_control'] as Record<string, Object> | undefined;
  if (replyCtrl) {
    comment.time_desc = (replyCtrl['time_desc'] as string) ?? '';
    // location 格式为 "IP属地：陕西"，直接存
    comment.ip_desc = (replyCtrl['location'] as string) ?? '';
  }

  // --- content ---
  const content = item['content'] as Record<string, Object> | undefined;
  if (content) {
    comment.message = decodeHTML((content['message'] as string) ?? '');

    // emote → emoteMap: { "表情名" → "图片url" }
    // ⚠️ API 返回的 key 带方括号 "[大哭]"，存入时去掉括号便于 UI 按捕获组查找
    const emote = content['emote'] as Record<string, Object> | undefined;
    if (emote) {
      const keys: string[] = Object.keys(emote);
      console.info('[CommentApi] emote count: ' + keys.length);
      for (let i = 0; i < keys.length; i++) {
        const fullKey = keys[i];  // "[大哭]"
        const name = fullKey.length >= 2 ? fullKey.substring(1, fullKey.length - 1) : fullKey;
        const emojiObj = emote[fullKey] as Record<string, Object> | undefined;
        const url = emojiObj ? (emojiObj['url'] as string) : '';
        if (url) {
          // 编码大小信息到 value 中：url||size （size: 1=小 2=大）
          const meta = emojiObj!['meta'] as Record<string, Object> | undefined;
          const size: number = (meta && meta['size'] as number) || 1;
          comment.emoteMap.set(name, url + '||' + size);
          console.info('[CommentApi] emote: "' + name + '" size=' + size + ' -> ' + url.substring(0, 50));
        } else {
          console.info('[CommentApi] emote skip (no url): "' + fullKey + '"');
        }
      }
    } else {
      console.info('[CommentApi] no emote in content');
    }

    // members → memberMap: { "用户名" → UserCard }
    const members = content['members'] as Array<Record<string, Object>> | undefined;
    if (members) {
      for (let i = 0; i < members.length; i++) {
        const m = members[i];
        const uname = m['uname'] as string | undefined;
        if (uname) {
          const card = new UserCard();
          card.name = uname;
          card.mid = Number(m['mid'] ?? 0);
          comment.memberMap.set(uname, card);
        }
      }
    }

    // --- 当前用户操作状态（0=无 1=已点赞 2=已点踩） ---
  comment.action = (item['action'] as number) ?? 0;

  // 部分响应的 content 中有 pictures 字段（评论区带图）
    // 自动转为缩略图 URL，避免手表加载原图
    const pics = content['pictures'] as Array<Record<string, Object>> | undefined;
    if (pics) {
      const picUrls: string[] = [];
      for (let i = 0; i < pics.length; i++) {
        const imgSrc = pics[i]['img_src'] as string | undefined;
        if (imgSrc) {
          picUrls.push(imgSrc);
        }
      }
      if (picUrls.length > 0) {
        comment.pictures = picUrls;
      }
    }
  }

  // --- 点赞 & 回复数 ---
  comment.likes = (item['like'] as number) ?? 0;
  // count = 二级评论条数，rcount 也是，优先用 count
  comment.replys = (item['count'] as number) ?? 0;
  if (comment.replys === 0) {
    comment.replys = (item['rcount'] as number) ?? 0;
  }

  // --- 热评（精选回复）：API 在 replies 字段中带最多 3 条预览 ——
  const previewReplies = item['replies'] as Array<Record<string, Object>> | undefined;
  if (previewReplies) {
    const hotTexts: string[] = [];
    for (let i = 0; i < previewReplies.length && i < 2; i++) {
      const reply = previewReplies[i];
      const c = reply['content'] as Record<string, Object> | undefined;
      const member = reply['member'] as Record<string, Object> | undefined;
      const uname = member ? (member['uname'] as string) : '';
      if (c && c['message']) {
        hotTexts.push(uname + '：' + decodeHTML(c['message'] as string));
      }
    }
    comment.hotReply = hotTexts;
  }

  // --- isOnTop：由调用方根据 upper.top 判断，不在此处理 ---

  return comment;
}

// ===== 操作结果类型 =====

export interface ActionResult {
  success: boolean;
  message: string;
}

// ===== 4. 点赞/取消赞评论 =====

/**
 * 点赞或取消赞评论
 * POST https://api.bilibili.com/x/v2/reply/action
 *
 * @param type   评论区类型（视频=1）
 * @param oid    目标评论区 id（视频 aid）
 * @param rpid   目标评论 rpid
 * @param action 操作：0=取消赞 1=点赞
 * @returns { success, message }
 */
export async function likeComment(type: number, oid: number, rpid: number, action: number): Promise<ActionResult> {
  let csrf: string = cookieMap['bili_jct'] || AppStorage.get<string>('csrf') || '';
  if (!csrf) {
    console.warn('[CommentApi] likeComment: csrf 为空');
    return { success: false, message: '登录状态已失效，请重新登录' };
  }
  console.info('[CommentApi] likeComment: rpid=' + rpid + ' action=' + action);

  let formData: string = 'type=' + type + '&oid=' + oid + '&rpid=' + rpid + '&action=' + action + '&csrf=' + encodeURIComponent(csrf);
  try {
    let resp: ApiResponse = await httpPostForm('https://api.bilibili.com/x/v2/reply/action', formData);
    console.info('[CommentApi] likeComment 响应 code=' + resp.code + ' msg=' + resp.message);
    if (resp.code === 0) {
      return { success: true, message: action === 1 ? '点赞成功' : '已取消点赞' };
    }
    if (resp.code === 12004) return { success: false, message: '禁止操作' };
    if (resp.code === 12006) return { success: false, message: '评论已删除' };
    if (resp.code === -111) return { success: false, message: '校验失败，请重新登录' };
    if (resp.code === -101) return { success: false, message: '登录状态已失效' };
    return { success: false, message: '操作失败(' + resp.code + ')' };
  } catch (e) {
    console.error('[CommentApi] likeComment 异常:', String(e));
    return { success: false, message: '网络异常' };
  }
}

// ===== 5. 点踩/取消踩评论 =====

/**
 * 点踩或取消踩评论
 * POST https://api.bilibili.com/x/v2/reply/hate
 *
 * @param type   评论区类型（视频=1）
 * @param oid    目标评论区 id（视频 aid）
 * @param rpid   目标评论 rpid
 * @param action 操作：0=取消踩 1=点踩
 * @returns { success, message }
 */
export async function hateComment(type: number, oid: number, rpid: number, action: number): Promise<ActionResult> {
  let csrf: string = cookieMap['bili_jct'] || AppStorage.get<string>('csrf') || '';
  if (!csrf) {
    console.warn('[CommentApi] hateComment: csrf 为空');
    return { success: false, message: '登录状态已失效，请重新登录' };
  }
  console.info('[CommentApi] hateComment: rpid=' + rpid + ' action=' + action);

  let formData: string = 'type=' + type + '&oid=' + oid + '&rpid=' + rpid + '&action=' + action + '&csrf=' + encodeURIComponent(csrf);
  try {
    let resp: ApiResponse = await httpPostForm('https://api.bilibili.com/x/v2/reply/hate', formData);
    console.info('[CommentApi] hateComment 响应 code=' + resp.code + ' msg=' + resp.message);
    if (resp.code === 0) {
      return { success: true, message: action === 1 ? '点踩成功' : '已取消点踩' };
    }
    if (resp.code === 12004) return { success: false, message: '禁止操作' };
    if (resp.code === 12006) return { success: false, message: '评论已删除' };
    if (resp.code === -111) return { success: false, message: '校验失败，请重新登录' };
    if (resp.code === -101) return { success: false, message: '登录状态已失效' };
    return { success: false, message: '操作失败(' + resp.code + ')' };
  } catch (e) {
    console.error('[CommentApi] hateComment 异常:', String(e));
    return { success: false, message: '网络异常' };
  }
}

// ===== 1. 获取视频评论总数 =====
/**
 * 获取视频的评论总数
 * @param id     视频 aid / 动态id / 专栏cvid
 * @param types  评论区类型数组 1=视频，12=专栏，17=动态，默认为[1]
 * @returns 评论总数（根评论数）
 */
export async function getCommentCount(id: number, types: number[] = [1]): Promise<number> {
  for (let i: number = 0; i < types.length; i++) {
    const type: number = types[i];
    const url: string = API_BASE + '/count?type=' + type + '&oid=' + id;
    const resp: ApiResponse = await httpGet(url);

    if (resp.code === 0 && resp.data) {
      const data = resp.data as Record<string, Object>;
      return (data['count'] as number) ?? 0;
    }
    console.warn('[CommentApi] count fail for type=' + type + ': code=' + resp.code + ' msg=' + resp.message);
  }
  console.error('[CommentApi] all types failed for id=' + id);
  return 0;
}

/**
 * 获取视频评论区的一页评论（翻页加载模式，不包含热评）
 * @param id     视频 aid / 动态id / 专栏cvid
 * @param pn     页码（从 1 开始）
 * @param ps     每页条数（1-20，默认 20）
 * @param sort   排序：0=按时间 1=按点赞 2=按回复（默认 0）
 * @param types  评论区类型数组 1=视频，12=专栏，17=动态，默认为[1]
 * @returns      当前页评论列表 + 根评论总数
 */
export async function getCommentList(
  id: number,
  pn: number,
  ps: number = 20,
  sort: number = 1,
  types: number[] = [1]
): Promise<PagedComments> {
  for (let i: number = 0; i < types.length; i++) {
    const type: number = types[i];
    let url: string = API_BASE
      + '?type=' + type
      + '&oid=' + id
      + '&pn=' + pn
      + '&ps=' + ps
      + '&sort=' + sort;

    console.info("[CommentApi] url = " + url)

    const resp: ApiResponse = await httpGet(url);

    if (resp.code !== 0 || !resp.data) {
      console.warn('[CommentApi] list fail for type=' + type + ': code=' + resp.code + ' msg=' + resp.message);
      continue;
    }

    const data = resp.data as Record<string, Object>;

    // 总条数
    const page = data['page'] as Record<string, Object> | undefined;
    const total: number = (page ? (page['count'] as number) : 0) ?? 0;

    // 评论列表
    let hots = data['hots'] as Array<Record<string, Object>> | undefined;
    let list: SingleComment[] = [];

    if (hots) {
      for (let j: number = 0; j < hots.length; j++) {
        list.push(parseCommentItem(hots[j]));
      }
    }

    let replies = data['replies'] as Array<Record<string, Object>> | undefined;

    if (replies) {
      for (let j: number = 0; j < replies.length; j++) {
        list.push(parseCommentItem(replies[j]));
      }
    }

    // 处理置顶评论（upper.top），仅第一页才插入
    if (pn === 1) {
      const upper = data['upper'] as Record<string, Object> | undefined;
      if (upper) {
        const top = upper['top'] as Record<string, Object> | undefined;
        if (top) {
          const topComment = parseCommentItem(top);
          topComment.isOnTop = true;
          // 置顶评论插到最前面
          list.unshift(topComment);
        }
      }
    }

    return { list, total };
  }
  console.error('[CommentApi] all types failed for id=' + id + ' pn=' + pn);
  return { list: [], total: 0 };
}


// ===== 3. 获取指定评论的回复 =====

/**
 * 获取某条评论的回复列表
 * @param type  评论区类型（视频=1）
 * @param oid   目标评论区 id（视频 aid）
 * @param root  目标评论的 rpid
 * @param pn    页码（从 1 开始）
 * @param ps    每页条数（1-20，默认 20）
 * @returns     回复列表 + 回复总数
 */
export async function getCommentReplies(
  type: number,
  oid: number,
  root: number,
  pn: number,
  ps: number = 20
): Promise<PagedReplies> {
  const url: string = API_BASE + '/reply'
    + '?type=' + type
    + '&oid=' + oid
    + '&root=' + root
    + '&pn=' + pn
    + '&ps=' + ps;

  const resp: ApiResponse = await httpGet(url);

  if (resp.code !== 0 || !resp.data) {
    console.error('[CommentApi] replies fail: code=' + resp.code + ' msg=' + resp.message);
    return { list: [], total: 0 };
  }

  const data = resp.data as Record<string, Object>;

  // 总回复数（data.page.count）
  const page = data['page'] as Record<string, Object> | undefined;
  const total: number = (page ? (page['count'] as number) : 0) ?? 0;

  // 回复列表
  const replies = data['replies'] as Array<Record<string, Object>> | undefined;
  const list: SingleComment[] = [];
  if (replies) {
    for (let i = 0; i < replies.length; i++) {
      list.push(parseCommentItem(replies[i]));
    }
  }

  return { list, total };
}
