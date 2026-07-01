/**
 * 动态 API
 * 这里bug最多了，主要是bilibili在收集API文档的人寄掉后又改了动态API
 * 能跑就行吧
 *
 */

import { httpGet, httpPostForm, ApiResponse, decodeHTML } from './CommonApi';
import { signWBI } from './WbiSign';
import { cookieMap } from './LoginApi';
import { Dynamic } from '../model/Dynamic';
import { UserCard } from '../model/UserCard';
import { VideoCard, ArticleCard } from '../model/ContentCard';

// ===== 常量 =====

const DYNAMIC_API_BASE: string = 'https://api.bilibili.com/x/polymer/web-dynamic/v1';

/** 功能性特性开关（与 web 端一致） */
const FEATURES: string =
  'itemOpusStyle,opusBigCover,listOnlyfans,onlyfansVote,' +
    'forwardListHidden,decorationCard,commentsNewVersion,' +
    'onlyfansAssetsV2,ugcDelete,onlyfansQaCard,eva3CardOpus';

// ===== 返回类型 =====

export interface DynamicListResult {
  /** 本页动态列表 */
  list: Dynamic[];

  /** 下一页偏移值，为空字符串 "" 表示已到底 */
  offset: string;

  /** 更新基线值（用于 checkDynamicUpdate），首页动态才有意义 */
  updateBaseline: string;
}

// ==================== 1. 获取动态列表（首页） ====================

/**
 * 获取首页动态瀑布流
 *
 * GET https://api.bilibili.com/x/polymer/web-dynamic/v1/feed/all
 *
 * @param offset  翻页偏移，首次传 ""，后续传上一轮返回的 offset
 * @param type    动态类型筛选："all" | "video" | "pgc" | "article"，默认 "all"
 * @returns       动态列表 + 下一页偏移 + 更新基线
 */
export async function getDynamicFeed(
  offset: string = '',
  type: string = 'all'
): Promise<DynamicListResult> {
  let url: string = DYNAMIC_API_BASE + '/feed/all'
    + '?type=' + type
    + (offset ? '&offset=' + offset : '')
    + '&features=' + FEATURES;

  url = await signWBI(url);
  console.info('[DynamicApi] getDynamicFeed url=' + url);

  const resp: ApiResponse = await httpGet(url);
  if (resp.code !== 0 || !resp.data) {
    console.error('[DynamicApi] getDynamicFeed fail: code=' + resp.code + ' msg=' + resp.message);
    const emptyResult: DynamicListResult = { list: [], offset: '', updateBaseline: '' };
    return emptyResult;
  }

  return parseDynamicList(resp.data as Record<string, Object>);
}

// ==================== 2. 获取用户空间动态 ====================

/**
 * 获取指定用户的动态
 *
 * GET https://api.bilibili.com/x/polymer/web-dynamic/v1/feed/space
 *
 * @param mid    目标用户 UID
 * @param offset 翻页偏移，首次传 ""
 * @returns      动态列表 + 下一页偏移
 */
export async function getUserDynamic(
  mid: number,
  offset: string = ''
): Promise<DynamicListResult> {
  let url: string = DYNAMIC_API_BASE + '/feed/space'
    + '?host_mid=' + mid
    + '&platform=web'
    + '&web_location=333.1387'
    + '&timezone_offset=-480'
    + (offset ? '&offset=' + offset : '')
    + '&features=' + FEATURES;

  url = await signWBI(url);
  console.info('[DynamicApi] getUserDynamic url=' + url);

  const resp: ApiResponse = await httpGet(url);
  if (resp.code !== 0 || !resp.data) {
    console.error('[DynamicApi] getUserDynamic fail: code=' + resp.code + ' msg=' + resp.message);
    const emptyResult: DynamicListResult = { list: [], offset: '', updateBaseline: '' };
    return emptyResult;
  }

  const data = resp.data as Record<string, Object>;
  const hasMore: boolean = (data['has_more'] as boolean) ?? false;
  const nextOffset: string = hasMore ? (data['offset'] as string ?? '') : '';

  const items = data['items'] as Array<Record<string, Object>> | undefined;
  const list: Dynamic[] = [];
  if (items) {
    for (let i = 0; i < items.length; i++) {
      list.push(parseDynamicItem(items[i]));
    }
  }

  const result: DynamicListResult = { list, offset: nextOffset, updateBaseline: '' };
  return result;
}

// ==================== 3. 获取单条动态详情 ====================

/**
 * 获取单条动态的完整详情
 *
 * 这东西好像已经废弃了？？？后端似乎只会返回4101105了
 * 不过这个函数确实也没啥用
 * 但代码能跑就先不删了
 *
 * @param id 动态 ID
 * @returns  动态对象，失败返回 null
 */
export async function getDynamicDetail(id: number): Promise<Dynamic | null> {
  const url: string = DYNAMIC_API_BASE + '/detail?id=' + id;
  console.info('[DynamicApi] getDynamicDetail url=' + url);

  const resp: ApiResponse = await httpGet(url);
  if (resp.code !== 0 || !resp.data) {
    console.error('[DynamicApi] getDynamicDetail fail: code=' + resp.code + ' msg=' + resp.message);
    return null;
  }

  const data = resp.data as Record<string, Object>;
  const item = data['item'] as Record<string, Object> | undefined;
  if (!item) {
    return null;
  }

  return parseDynamicItem(item);
}

// ==================== 4. 检查动态更新 ====================

/**
 * 检查首页动态是否有新发布，返回新动态数量
 *
 * GET https://api.bilibili.com/x/polymer/web-dynamic/v1/feed/all/update
 *
 * @param type          动态类型："all" | "video" | "pgc" | "article"
 * @param updateBaseline 更新基线值（从 getDynamicFeed 返回的 updateBaseline）
 * @returns             新动态数量
 */
export async function checkDynamicUpdate(
  type: string,
  updateBaseline: string
): Promise<number> {
  const url: string = DYNAMIC_API_BASE + '/feed/all/update'
    + '?type=' + type
    + '&update_baseline=' + updateBaseline
    + '&web_location=333.1365';

  console.info('[DynamicApi] checkDynamicUpdate url=' + url);

  const resp: ApiResponse = await httpGet(url);
  if (resp.code !== 0 || !resp.data) {
    console.error('[DynamicApi] checkDynamicUpdate fail: code=' + resp.code);
    return 0;
  }

  const data = resp.data as Record<string, Object>;
  return (data['update_num'] as number) ?? 0;
}

// ==================== 5. 点赞 / 取消赞 ====================

/**
 * 点赞或取消赞动态
 *
 * POST https://api.vc.bilibili.com/dynamic_like/v1/dynamic_like/thumb
 *
 * @param dyid 动态 ID
 * @param like true = 点赞, false = 取消赞
 * @returns    是否操作成功
 */
export async function likeDynamic(dyid: number, like: boolean): Promise<boolean> {
  let csrf: string = cookieMap['bili_jct'] || AppStorage.get<string>('csrf') || '';
  if (!csrf) {
    console.warn('[DynamicApi] likeDynamic: csrf 为空');
    return false;
  }

  const formData: string =
    'dynamic_id=' + dyid
      + '&up=' + (like ? 1 : 2)
      + '&csrf_token=' + encodeURIComponent(csrf);

  console.info('[DynamicApi] likeDynamic: dyid=' + dyid + ' like=' + like);

  try {
    const resp: ApiResponse = await httpPostForm(
      'https://api.vc.bilibili.com/dynamic_like/v1/dynamic_like/thumb',
      formData
    );
    console.info('[DynamicApi] likeDynamic 响应 code=' + resp.code);
    return resp.code === 0;
  } catch (e) {
    console.error('[DynamicApi] likeDynamic 异常:', String(e));
    return false;
  }
}

// ==================== 内部解析函数 ====================

/** 解析 data 中的 items 列表 */
function parseDynamicList(data: Record<string, Object>): DynamicListResult {
  const hasMore: boolean = (data['has_more'] as boolean) ?? false;
  const nextOffset: string = hasMore ? (data['offset'] as string ?? '') : '';
  const updateBaseline: string = (data['update_baseline'] as string) ?? '';

  const items = data['items'] as Array<Record<string, Object>> | undefined;
  const list: Dynamic[] = [];
  if (items) {
    for (let i = 0; i < items.length; i++) {
      list.push(parseDynamicItem(items[i]));
    }
  }

  const result: DynamicListResult = { list, offset: nextOffset, updateBaseline };
  return result;
}

/** 解析单条动态 JSON item → Dynamic 模型 */
function parseDynamicItem(item: Record<string, Object>): Dynamic {
  const dyn = new Dynamic();

  // --- id ---
  const idStr = item['id_str'] as string | undefined;
  if (idStr) {
    dyn.dynamicId = Number(idStr);
  }
  dyn.type = (item['type'] as string) ?? '';

  // --- basic ---
  const basic = item['basic'] as Record<string, Object> | undefined;
  if (basic) {
    const cidStr = basic['comment_id_str'] as string | undefined;
    if (cidStr) {
      dyn.comment_id = Number(cidStr);
    }
    dyn.comment_type = (basic['comment_type'] as number) ?? 0;
  }

  // --- 不存在动态 ---
  if (dyn.type === 'DYNAMIC_TYPE_NONE') {
    dyn.message = '[动态不存在]';
    return dyn;
  }

  // --- modules ---
  const modules = item['modules'] as Record<string, Object> | undefined;
  if (!modules) {
    return dyn;
  }

  // --- module_author: 发布者 ---
  const author = modules['module_author'] as Record<string, Object> | undefined;
  if (author) {
    dyn.userInfo = new UserCard(
      author['name'] as string ?? '',
      author['face'] as string ?? '',
      Number(author['mid'] ?? 0)
    );
    if ((author['following'] as boolean) !== undefined) {
      dyn.userInfo.isVip = (author['following'] as boolean);
    }
    const vipJson = author['vip'] as Record<string, Object> | undefined;
    if (vipJson) {
      const nicknameColor = vipJson['nickname_color'] as string | undefined;
      // isVip: vip 信息暂不单独存，UserCard 的 isVip 用于标识会员
    }
    dyn.pubTime = (author['pub_time'] as string) ?? '';
  }

  // --- module_dynamic: 动态主体 ---
  const moduleDyn = modules['module_dynamic'] as Record<string, Object> | undefined;
  if (moduleDyn) {
    // desc → 富文本内容
    const desc = moduleDyn['desc'] as Record<string, Object> | undefined;
    if (desc) {
      const richTextNodes = desc['rich_text_nodes'] as Array<Record<string, Object>> | undefined;
      parseRichText(richTextNodes, dyn);
    }

    // major → 附加内容
    const major = moduleDyn['major'] as Record<string, Object> | undefined;
    if (major) {
      parseMajor(major, dyn);
    }
  }

  // --- module_stat: 统计数据 ---
  const moduleStat = modules['module_stat'] as Record<string, Object> | undefined;
  if (moduleStat) {
    const likeStat = moduleStat['like'] as Record<string, Object> | undefined;
    if (likeStat) {
      dyn.stats.like = (likeStat['count'] as number) ?? 0;
      dyn.stats.liked = (likeStat['status'] as boolean) ?? false;
    }
  }

  // --- module_more: 权限 ---
  const moduleMore = modules['module_more'] as Record<string, Object> | undefined;
  if (moduleMore) {
    const threePointItems = moduleMore['three_point_items'] as Array<Record<string, Object>> | undefined;
    if (threePointItems) {
      for (let i = 0; i < threePointItems.length; i++) {
        const tp = threePointItems[i];
        if ((tp['type'] as string) === 'THREE_POINT_DELETE') {
          dyn.canDelete = true;
          break;
        }
      }
    }
  }

  // --- orig: 被转发的原动态（递归） ---
  const orig = item['orig'] as Record<string, Object> | undefined;
  if (orig) {
    dyn.dynamic_forward = parseDynamicItem(orig);
  }

  return dyn;
}

/**
 * 解析富文本节点 → message + emoteMap + memberMap
 *
 * 支持的节点类型：
 *   RICH_TEXT_NODE_TYPE_TEXT    → 纯文本
 *   RICH_TEXT_NODE_TYPE_EMOJI   → 表情（emoteMap）
 *   RICH_TEXT_NODE_TYPE_AT      → @提及（memberMap）
 *   RICH_TEXT_NODE_TYPE_WEB     → 链接（原文保留）
 */
function parseRichText(
  nodes: Array<Record<string, Object>> | undefined,
  dyn: Dynamic
): void {
  if (!nodes || nodes.length === 0) {
    return;
  }

  let textBuilder: string = '';
  const emoteMap: Map<string, string> = new Map();
  const memberMap: Map<string, UserCard> = new Map();

  for (let i = 0; i < nodes.length; i++) {
    const node = nodes[i];
    const nodeType = (node['type'] as string) ?? 'RICH_TEXT_NODE_TYPE_TEXT';

    switch (nodeType) {
      case 'RICH_TEXT_NODE_TYPE_EMOJI': {
        const text = (node['text'] as string) ?? '';
        textBuilder += text;
        const emoji = node['emoji'] as Record<string, Object> | undefined;
        if (emoji) {
          let emojiText = (emoji['text'] as string) ?? '';
          // ⚠️ API 返回的 emoji.text 带方括号 "[doge]"，
          // 存入时去掉括号便于 UI 按捕获组查找（m[1] 为括号内内容）
          if (emojiText.length >= 2 && emojiText.startsWith('[') && emojiText.endsWith(']')) {
            emojiText = emojiText.substring(1, emojiText.length - 1);
          }
          const iconUrl = (emoji['icon_url'] as string) ?? '';
          const size: number = (emoji['size'] as number) ?? 1;
          if (emojiText && iconUrl) {
            // 编码大小信息到 value：url||size（1=小 2=大）
            emoteMap.set(emojiText, iconUrl + '||' + size);
          }
        }
        break;
      }
      case 'RICH_TEXT_NODE_TYPE_AT': {
        const text = (node['text'] as string) ?? '';
        textBuilder += text;
        const rid = Number(node['rid'] ?? 0);
        // 去掉 "@" 和末尾空格获取用户名
        let uname: string = text;
        if (uname.startsWith('@')) {
          uname = uname.substring(1);
        }
        uname = uname.trim();
        if (uname && rid > 0) {
          const card = new UserCard(uname, '', rid);
          memberMap.set(uname, card);
        }
        break;
      }
      case 'RICH_TEXT_NODE_TYPE_WEB': {
        textBuilder += (node['orig_text'] as string) ?? '';
        break;
      }
      case 'RICH_TEXT_NODE_TYPE_TEXT':
      default: {
        textBuilder += (node['text'] as string) ?? '';
        break;
      }
    }
  }

  dyn.message = decodeHTML(textBuilder);
  dyn.emoteMap = emoteMap;
  dyn.memberMap = memberMap;
}

/**
 * 解析 major 附加内容 → major_type + major_object + pictures + title
 */
function parseMajor(major: Record<string, Object>, dyn: Dynamic): void {
  const majorType = (major['type'] as string) ?? '';
  dyn.major_type = majorType;

  switch (majorType) {
    case 'MAJOR_TYPE_ARCHIVE': {
      const archive = major['archive'] as Record<string, Object> | undefined;
      if (archive) {
        dyn.major_object = parseVideoCard(archive);
      }
      break;
    }
    case 'MAJOR_TYPE_UGC_SEASON': {
      const ugc = major['ugc_season'] as Record<string, Object> | undefined;
      if (ugc) {
        dyn.major_object = parseVideoCard(ugc);
      }
      break;
    }
    case 'MAJOR_TYPE_PGC': {
      const pgc = major['pgc'] as Record<string, Object> | undefined;
      if (pgc) {
        const card = new VideoCard(
          pgc['title'] as string ?? '',
          '追番',
          (pgc['stat'] as Record<string, Object> | undefined)?.['play'] as string ?? '',
          pgc['cover'] as string ?? '',
          Number(pgc['epid'] ?? 0),
          ''
        );
        // PGC 的 aid 需要从 epid 换算，这里暂用 epid 标记
        dyn.major_object = card;
      }
      break;
    }
    case 'MAJOR_TYPE_ARTICLE': {
      const article = major['article'] as Record<string, Object> | undefined;
      if (article) {
        const covers = (article['covers'] as Array<string>) ?? [];
        dyn.major_object = new ArticleCard(
          article['title'] as string ?? '',
          '投稿文章',
          article['label'] as string ?? '',
          covers,
          Number(article['id'] ?? 0)
        );
      }
      break;
    }
    case 'MAJOR_TYPE_DRAW': {
      const draw = major['draw'] as Record<string, Object> | undefined;
      if (draw) {
        const items = draw['items'] as Array<Record<string, Object>> | undefined;
        if (items) {
          const pics: string[] = [];
          for (let i = 0; i < items.length; i++) {
            const src = items[i]['src'] as string;
            if (src) {
              pics.push(src);
            }
          }
          dyn.pictures = pics;
          dyn.major_object = pics;
        }
      }
      break;
    }
    case 'MAJOR_TYPE_OPUS': {
      const opus = major['opus'] as Record<string, Object> | undefined;
      if (opus) {
        dyn.title = (opus['title'] as string) ?? '';

        const pics = opus['pics'] as Array<Record<string, Object>> | undefined;
        if (pics) {
          const picUrls: string[] = [];
          for (let i = 0; i < pics.length; i++) {
            const url = pics[i]['url'] as string;
            if (url) {
              picUrls.push(url);
            }
          }
          dyn.pictures = picUrls;
          dyn.major_object = picUrls;
        }

        const summary = opus['summary'] as Record<string, Object> | undefined;
        if (summary) {
          const summaryNodes = summary['rich_text_nodes'] as Array<Record<string, Object>> | undefined;
          // Opus 的 summary 覆盖 desc，先完整解析再用
          const tempDyn = new Dynamic();
          parseRichText(summaryNodes, tempDyn);
          if (tempDyn.message) {
            dyn.message = tempDyn.message;
            // 合并 emoteMap / memberMap
            tempDyn.emoteMap.forEach((v, k) => dyn.emoteMap.set(k, v));
            tempDyn.memberMap.forEach((v, k) => dyn.memberMap.set(k, v));
          }
        }
      }
      break;
    }
    case 'MAJOR_TYPE_LIVE_RCMD':
    case 'MAJOR_TYPE_LIVE': {
      // 直播暂不做
      dyn.message = (dyn.message ? dyn.message + '\n' : '') + '[直播动态暂不支持]';
      break;
    }
    case 'MAJOR_TYPE_COMMON': {
      // 活动类动态，仅文本
      break;
    }
    default: {
      dyn.message = (dyn.message ? dyn.message + '\n' : '')
        + '[*暂不支持此类型动态|' + majorType + ']';
      break;
    }
  }
}

/** 解析视频卡片 JSON → VideoCard */
function parseVideoCard(json: Record<string, Object>): VideoCard {
  const stat = json['stat'] as Record<string, Object> | undefined;
  const playCount = stat ? (stat['play'] as string ?? '') : '';
  return new VideoCard(
    json['title'] as string ?? '',
    '投稿视频',
    playCount,
    json['cover'] as string ?? '',
    Number(json['aid'] ?? 0),
    json['bvid'] as string ?? ''
  );
}
