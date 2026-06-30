/**
 * 专栏 / Opus API
 *
 * 最纯粹的shit山之一
 * 这可能是除了视频播放页面以外的最石的代码
 *
 */

import { http } from '@kit.NetworkKit';
import { httpGet, httpPostForm, ApiResponse, decodeHTML, formatCount } from './CommonApi';
import { signWBI } from './WbiSign';
import { cookieMap } from './LoginApi';
import { ArticleInfo, ArticleStats } from '../model/ArticleInfo';
import { Opus, OpusType } from '../model/Opus';
import { UserCard } from '../model/UserCard';
import { ArticleParagraph, ParagraphType, ListStyle } from '../model/ArticleParagraph';
import { VideoCard, ArticleCard } from '../model/ContentCard';


// =================================================================
//  1. 内部工具：解析 HTML 中嵌入的 INITIAL_STATE JSON
// =================================================================

/**
 * 剥除 HTML 标签，提取纯文本。
 * 处理 <p>、<br>、<img> 等内联块级标签时插入换行。
 */
function stripHtmlTags(html: string): string {
  if (!html) return '';
  // 块级标签前后加换行
  let text: string = html
    .replace(/<\/?p[^>]*>/gi, '\n')
    .replace(/<br\s*\/?>/gi, '\n')
    .replace(/<\/?div[^>]*>/gi, '\n')
    .replace(/<\/?li[^>]*>/gi, '\n')
    .replace(/<\/?h[1-6][^>]*>/gi, '\n')
    .replace(/<\/?blockquote[^>]*>/gi, '\n')
    .replace(/<img[^>]*>/gi, '[图片]')
    .replace(/<[^>]+>/g, '')   // 移除剩余所有标签
    .replace(/&nbsp;/g, ' ')
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/\n{3,}/g, '\n\n')  // 合并过多空行
    .trim();
  return text;
}

/**
 * 从 HTML 页面中提取 window.__INITIAL_STATE__ 的 JSON 对象。
 *
 * B 站的 /opus/{id} 页面在 <script> 中嵌入了：
 *   window.__INITIAL_STATE__ = { ... };
 * 此函数通过定位标记 + 花括号匹配提取完整 JSON。
 */
function extractInitState(html: string): Record<string, Object> | null {
  const marker: string = 'window.__INITIAL_STATE__=';
  const startIdx: number = html.indexOf(marker);
  if (startIdx < 0) {
    console.error('[ArticleApi] 未找到 __INITIAL_STATE__');
    return null;
  }

  const jsonStart: number = startIdx + marker.length;
  let braceDepth: number = 0;
  let inString: boolean = false;
  let escape: boolean = false;
  let endIdx: number = -1;

  for (let i: number = jsonStart; i < html.length; i++) {
    const ch: string = html[i];

    if (escape) {
      escape = false;
      continue;
    }

    if (ch === '\\' && inString) {
      escape = true;
      continue;
    }

    if (ch === '"') {
      inString = !inString;
      continue;
    }

    if (!inString) {
      if (ch === '{') {
        braceDepth++;
      } else if (ch === '}') {
        braceDepth--;
        if (braceDepth === 0) {
          endIdx = i + 1;
          break;
        }
      } else if (ch === ';' && braceDepth === 0) {
        // 意外遇到分号，说明 JSON 可能已结束
        break;
      }
    }
  }

  if (endIdx < 0) {
    console.error('[ArticleApi] 未找到 __INITIAL_STATE__ 的闭合大括号');
    return null;
  }

  const jsonStr: string = html.substring(jsonStart, endIdx);

  try {
    const parsed: Record<string, Object> = JSON.parse(jsonStr) as Record<string, Object>;
    return parsed;
  } catch (e) {
    console.error('[ArticleApi] __INITIAL_STATE__ JSON 解析失败:', String(e));
    return null;
  }
}

// =================================================================
//  2. 新版 Opus：从 HTML 页面获取作品详情
// =================================================================

/**
 * 获取 Opus 作品详情（新版统一接口）
 *
 * 访问 B 站前端页面 {id}，从 HTML 内嵌的 __INITIAL_STATE__.detail 中提取数据。
 *
 * @param id 作品 ID。
 *            id > 100000000  → 直接访问 /opus/{id}（Opus 统一 ID）
 *            id ≤ 100000000 → 先访问 /read/cv{id}（自动重定向到 /opus/{id}）
 * @returns 解析后的 Opus 对象，失败返回 null
 */
export async function getOpus(id: number): Promise<Opus | null> {
  // 构造 URL
  const baseUrl: string = id > 100000000
    ? 'https://www.bilibili.com/opus/' + id
    : 'https://www.bilibili.com/read/cv' + id;

  console.info('[ArticleApi] getOpus url=' + baseUrl);

  try {
    // 直接使用 http 模块获取 HTML（httpGet 会尝试 JSON 解析，不适合 HTML 页面）
    const html: string = await fetchPage(baseUrl);
    if (!html) {
      console.error('[ArticleApi] getOpus 页面获取为空');
      return null;
    }

    const initState: Record<string, Object> | null = extractInitState(html);
    if (!initState) {
      console.error('[ArticleApi] getOpus 未找到 INITIAL_STATE');
      // 取不到 INITIAL_STATE 时尝试访问旧版 API 降级
      const fallback: Opus | null = await tryFallbackOldDynamic(id, html);
      return fallback;
    }

    // 新版 B 站 /opus/{id} 页面的 INITIAL_STATE 结构：
    // 专栏/图文数据存在 'opus' key 下（非 'detail'），而不是 'detail'
    let detail: Record<string, Object> | undefined = initState['detail'] as Record<string, Object> | undefined;

    // 尝试从 'opus' 字段提取
    if (!detail) {
      const opusState: Record<string, Object> | undefined = initState['opus'] as Record<string, Object> | undefined;
      if (opusState) {
        console.info('[ArticleApi] getOpus 从 opus 字段提取数据');
        const opusKeys: string[] = Object.keys(opusState);
        console.info('[ArticleApi] getOpus opus 子 key: ' + opusKeys.join(', '));
        // opus 字段下可能有 detail、basic 等
        detail = opusState['detail'] as Record<string, Object> | undefined;
        if (!detail) {
          // 直接尝试将 opus 整个作为 detail 解析
          console.warn('[ArticleApi] getOpus opus.detail 也不存在，尝试直接使用 opusState');
          const fallbackOpus: Opus | null = tryParseFlatOpus(id, opusState);
          if (fallbackOpus) return fallbackOpus;
        }
      }
    }

    if (!detail) {
      // 输出所有顶层 key 辅助定位 B 站页面结构调整
      const allKeys: string[] = Object.keys(initState);
      console.error('[ArticleApi] getOpus 未找到 detail/opus.detail，INITIAL_STATE 顶层 key: ' + allKeys.join(', '));
      if (allKeys.indexOf('readerData') >= 0) {
        console.error('[ArticleApi] getOpus 存在 readerData（可能是旧版专栏阅读页）');
        const readerData: Record<string, Object> | undefined = initState['readerData'] as Record<string, Object> | undefined;
        if (readerData) {
          const rdKeys: string[] = Object.keys(readerData);
          console.error('[ArticleApi] getOpus readerData 子 key: ' + rdKeys.join(', '));
          const article: Record<string, Object> | undefined = readerData['article'] as Record<string, Object> | undefined;
          if (article) {
            console.error('[ArticleApi] getOpus readerData.article 存在，尝试转换为 Opus');
            const fallbackOpus: Opus = new Opus();
            fallbackOpus.id = id;
            fallbackOpus.type = OpusType.ARTICLE;
            fallbackOpus.title = (article['title'] as string) ?? '';
            fallbackOpus.upInfo = new UserCard(
              (article['author_name'] as string) ?? '',
              '',
              Number(article['mid'] ?? 0)
            );
            const content: string = (article['content'] as string) ?? '';
            if (content) {
              fallbackOpus.paragraphs = [new ArticleParagraph(ParagraphType.TEXT, 0, stripHtmlTags(content))];
            }
            return fallbackOpus;
          }
        }
      }

      // 尝试从 readInfo 提取（旧版专栏阅读页）
      const readInfo: Record<string, Object> | undefined = initState['readInfo'] as Record<string, Object> | undefined;
      if (readInfo) {
        console.info('[ArticleApi] getOpus 从 readInfo 字段提取数据');
        const readInfoKeys: string[] = Object.keys(readInfo);
        console.info('[ArticleApi] getOpus readInfo 子 key: ' + readInfoKeys.join(', '));
        const article2: Record<string, Object> | undefined = readInfo['article'] as Record<string, Object> | undefined;
        if (article2) {
          const riOpus: Opus = new Opus();
          riOpus.id = id;
          riOpus.type = OpusType.ARTICLE;
          riOpus.title = (article2['title'] as string) ?? '';
          riOpus.pubTime = (article2['publish_time'] as string) ?? '';
          riOpus.upInfo = new UserCard(
            (article2['author_name'] as string) ?? '',
            (article2['author_face'] as string) ?? '',
            Number(article2['mid'] ?? 0)
          );
          const riContent: string = (article2['content'] as string) ?? '';
          if (riContent && /<[a-zA-Z!][^>]*>/.test(riContent)) {
            riOpus.paragraphs = parseHtmlToParagraphs(riContent);
          } else {
            const riContent2: string = (article2['content'] as string) ?? '';
            if (riContent2) {
              riOpus.paragraphs = [new ArticleParagraph(ParagraphType.TEXT, 0, stripHtmlTags(riContent2))];
            }
          }
          // 统计
          const readViewInfo: Record<string, Object> | undefined = initState['readViewInfo'] as Record<string, Object> | undefined;
          if (readViewInfo) {
            const stats2: Record<string, Object> | undefined = readViewInfo['stats'] as Record<string, Object> | undefined;
            if (stats2) {
              riOpus.stats.view = (stats2['view'] as number) ?? 0;
              riOpus.stats.like = (stats2['like'] as number) ?? 0;
              riOpus.stats.coin = (stats2['coin'] as number) ?? 0;
              riOpus.stats.favorite = (stats2['favorite'] as number) ?? 0;
              riOpus.stats.share = (stats2['share'] as number) ?? 0;
              riOpus.stats.reply = (stats2['reply'] as number) ?? 0;
            }
          }
          const articleStats: Record<string, Object> | undefined = initState['articleStats'] as Record<string, Object> | undefined;
          if (articleStats) {
            riOpus.stats.liked = (articleStats['like'] as boolean) ?? false;
            riOpus.stats.favoured = (articleStats['favorite'] as boolean) ?? false;
          }
          console.info('[ArticleApi] getOpus readInfo 路径成功，段落数=' + riOpus.paragraphs.length);
          return riOpus;
        }
      }

      return null;
    }

    return parseOpusDetail(id, detail);
  } catch (e) {
    console.error('[ArticleApi] getOpus 异常:', String(e));
    // 网络错误等异常情况尝试降级到旧版
    return null;
  }
}

/**
 * 直接获取 HTML 页面内容（不解析 JSON）
 */
async function fetchPage(url: string): Promise<string> {
  return new Promise<string>((resolve, reject) => {
    const req: http.HttpRequest = http.createHttp();

    req.request(url, {
      method: http.RequestMethod.GET,
      header: {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 10; HarmonyOS; BiliTerm) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.6261.95 Safari/537.36',
        'Referer': 'https://www.bilibili.com/',
      },
      connectTimeout: 10000,
      readTimeout: 15000
    }, (err: Error, resp: http.HttpResponse) => {
      req.destroy();
      if (err) {
        console.error('[ArticleApi] fetchPage 失败:', err.message);
        reject(new Error('fetchPage: ' + err.message));
        return;
      }
      const body: string = resp.result as string;
      if (!body) {
        console.error('[ArticleApi] fetchPage 响应为空');
        reject(new Error('fetchPage: empty response'));
        return;
      }
      resolve(body);
    });
  });
}

/**
 * 尝试从旧版动态 HTML 中提取 Opus 信息（降级）
 * 当新版 INITIAL_STATE 不可用时调用。
 */
async function tryFallbackOldDynamic(id: number, html: string): Promise<Opus | null> {
  // 尝试在 HTML 中搜索旧版 API 的数据
  try {
    // 某些情况下 HTML 中会嵌入 JSON 格式的 window.__NEXT_DATA__ 或其他变量
    // 此处暂时返回 null，由调用方兜底
    console.warn('[ArticleApi] 尝试降级旧版动态失败: id=' + id);
  } catch (e) {
    // 忽略
  }
  return null;
}

// =================================================================
//  3. 解析 Opus detail 结构
// =================================================================

/**
 * 尝试直接将 opusState 作为平面结构解析为 Opus。
 *
 * 部分 B 站 /opus/{id} 页面可能没有 modules 数组，
 * 而是将标题/内容/UP主直接展平在顶层。
 */
function tryParseFlatOpus(id: number, opusState: Record<string, Object>): Opus | null {
  const opus: Opus = new Opus();
  opus.id = id;
  opus.type = OpusType.ARTICLE;

  // 尝试提取基础信息
  opus.title = (opusState['title'] as string) ?? '';
  opus.cover = (opusState['image'] as string) ?? (opusState['cover'] as string) ?? '';

  // UP 主
  const upCard: UserCard = new UserCard(
    (opusState['author_name'] as string) ?? (opusState['up_name'] as string) ?? '',
    (opusState['author_face'] as string) ?? (opusState['up_face'] as string) ?? '',
    Number(opusState['mid'] ?? opusState['up_mid'] ?? 0)
  );
  opus.upInfo = upCard;
  opus.pubTime = (opusState['pub_time'] as string) ?? (opusState['publish_time'] as string) ?? '';

  // 评论区
  opus.commentId = Number(opusState['comment_id'] ?? 0);
  opus.commentType = (opusState['comment_type'] as number) ?? 0;

  // 正文内容
  const content: string = (opusState['content'] as string) ?? (opusState['body'] as string) ?? '';
  const title: string = opus.title;
  if (content) {
    console.info('[ArticleApi] tryParseFlatOpus 原始 content 长度=' + content.length + ' 前32字符=' + content.substring(0, 32));
    // 判断是 HTML 还是纯文本
    if (/<[a-zA-Z!][^>]*>/.test(content)) {
      opus.paragraphs = parseHtmlToParagraphs(content);
    } else {
      opus.paragraphs = [new ArticleParagraph(ParagraphType.TEXT, 0, stripHtmlTags(content))];
    }
  } else {
    // 也可能有 paragraphs 数组
    const paraArr: Array<Record<string, Object>> | undefined
      = opusState['paragraphs'] as Array<Record<string, Object>> | undefined;
    if (paraArr && paraArr.length > 0) {
      opus.paragraphs = parseParagraphs(paraArr);
    }
  }

  // 统计数据
  const statsRaw: Record<string, Object> | undefined = opusState['stats'] as Record<string, Object> | undefined;
  if (statsRaw) {
    opus.stats.view = (statsRaw['view'] as number) ?? 0;
    opus.stats.like = (statsRaw['like'] as number) ?? 0;
    opus.stats.coin = (statsRaw['coin'] as number) ?? 0;
    opus.stats.favorite = (statsRaw['favorite'] as number) ?? 0;
    opus.stats.share = (statsRaw['share'] as number) ?? 0;
    opus.stats.reply = (statsRaw['reply'] as number) ?? 0;
  }

  return opus;
}

/**
 * 解析 Opus detail JSON → Opus 模型
 *
 * 解析 modules 数组，按 module_type 分派：
 *   MODULE_TYPE_TITLE    → Opus.title
 *   MODULE_TYPE_TOP      → Opus.topImages
 *   MODULE_TYPE_AUTHOR   → Opus.upInfo
 *   MODULE_TYPE_CONTENT  → Opus.paragraphs
 *   MODULE_TYPE_STAT     → Opus.stats
 */
function parseOpusDetail(id: number, detail: Record<string, Object>): Opus {
  const opus: Opus = new Opus();
  opus.id = id;

  // 判断类型：从 basic 或 id 范围判断
  const isOldStyle: boolean = id <= 100000000;
  opus.type = isOldStyle ? OpusType.ARTICLE : OpusType.DYNAMIC;

  // --- basic ---
  const basic: Record<string, Object> | undefined = detail['basic'] as Record<string, Object> | undefined;
  if (basic) {
    opus.commentId = Number(basic['comment_id_str'] ?? basic['comment_id'] ?? 0);
    opus.commentType = (basic['comment_type'] as number) ?? 0;
  }

  // --- modules ---
  const modules: Array<Record<string, Object>> | undefined = detail['modules'] as Array<Record<string, Object>> | undefined;
  if (!modules || modules.length === 0) {
    return opus;
  }

  for (let i: number = 0; i < modules.length; i++) {
    const module: Record<string, Object> = modules[i];
    const moduleType: string = (module['module_type'] as string) ?? '';

    switch (moduleType) {
      case 'MODULE_TYPE_TITLE':
        parseTitleModule(module, opus);
        break;
      case 'MODULE_TYPE_TOP':
        parseTopModule(module, opus);
        break;
      case 'MODULE_TYPE_AUTHOR':
        parseAuthorModule(module, opus);
        break;
      case 'MODULE_TYPE_CONTENT':
        parseContentModule(module, opus);
        break;
      case 'MODULE_TYPE_STAT':
        parseStatModule(module, opus);
        break;
      default:
        break;
    }
  }

  // 保证空安全
  if (!opus.upInfo) opus.upInfo = new UserCard();
  if (!opus.stats) opus.stats = new ArticleStats();

  return opus;
}

/** 解析 MODULE_TYPE_TITLE */
function parseTitleModule(module: Record<string, Object>, opus: Opus): void {
  const titleObj: Record<string, Object> | undefined = module['module_title'] as Record<string, Object> | undefined;
  if (titleObj) {
    opus.title = (titleObj['text'] as string) ?? '';
  }
}

/** 解析 MODULE_TYPE_TOP（顶部图片组） */
function parseTopModule(module: Record<string, Object>, opus: Opus): void {
  const top: Record<string, Object> | undefined = module['module_top'] as Record<string, Object> | undefined;
  if (!top) return;

  const display: Record<string, Object> | undefined = top['display'] as Record<string, Object> | undefined;
  if (!display) return;

  const displayType: number = (display['type'] as number) ?? 0;
  if (displayType !== 1) return; // 1 = 相册类型

  const album: Record<string, Object> | undefined = display['album'] as Record<string, Object> | undefined;
  if (!album) return;

  const pics: Array<Record<string, Object>> | undefined = album['pics'] as Array<Record<string, Object>> | undefined;
  if (!pics) return;

  const topImages: string[] = [];
  for (let i: number = 0; i < pics.length; i++) {
    const url: string = (pics[i]['url'] as string) ?? '';
    if (url) topImages.push(url);
  }
  opus.topImages = topImages;
}

/** 解析 MODULE_TYPE_AUTHOR（UP 主信息） */
function parseAuthorModule(module: Record<string, Object>, opus: Opus): void {
  const author: Record<string, Object> | undefined = module['module_author'] as Record<string, Object> | undefined;
  if (!author) return;

  const card: UserCard = new UserCard(
    (author['name'] as string) ?? '',
    (author['face'] as string) ?? '',
    Number(author['mid'] ?? 0)
  );

  // VIP 信息
  const vip: Record<string, Object> | undefined = author['vip'] as Record<string, Object> | undefined;
  if (vip) {
    const nickColor: string = (vip['nickname_color'] as string) ?? '';
    if (nickColor) {
      // UserCard 没有 nickname_color 字段，可后期扩展或用 isVip 标记
    }
  }

  opus.upInfo = card;
  opus.pubTime = (author['pub_time'] as string) ?? '';
}

/** 解析 MODULE_TYPE_CONTENT（正文段落） */
function parseContentModule(module: Record<string, Object>, opus: Opus): void {
  const content: Record<string, Object> | undefined = module['module_content'] as Record<string, Object> | undefined;
  if (!content) return;

  const paragraphs: Array<Record<string, Object>> | undefined = content['paragraphs'] as Array<Record<string, Object>> | undefined;
  if (!paragraphs) return;

  opus.paragraphs = parseParagraphs(paragraphs);

  // 同时提取 TYPE_TEXT_OPUS 段落中的 emoteMap / memberMap，
  // 使得 UI 在解析 "[doge]" 占位符时能查到图片 URL
  const emoteMap: Map<string, string> = new Map();
  const memberMap: Map<string, UserCard> = new Map();
  for (let pi: number = 0; pi < paragraphs.length; pi++) {
    const para: Record<string, Object> = paragraphs[pi];
    if ((para['para_type'] as number) === ParagraphType.TEXT_OPUS) {
      const data: Array<Record<string, Object>> | undefined = para['data'] as Array<Record<string, Object>> | undefined;
      if (!data) continue;
      for (let ni: number = 0; ni < data.length; ni++) {
        const node: Record<string, Object> = data[ni];
        const nodeType: string = (node['type'] as string) ?? '';
        if (nodeType === 'RICH_TEXT_NODE_TYPE_EMOJI') {
          const emoji: Record<string, Object> | undefined = node['emoji'] as Record<string, Object> | undefined;
          if (emoji) {
            let emojiText: string = (emoji['text'] as string) ?? '';
            // ⚠️ API 返回的 emoji.text 带方括号 "[doge]"，去掉括号便于 UI 按捕获组查找
            if (emojiText.length >= 2 && emojiText.startsWith('[') && emojiText.endsWith(']')) {
              emojiText = emojiText.substring(1, emojiText.length - 1);
            }
            const iconUrl: string = (emoji['icon_url'] as string) ?? '';
            const size: number = (emoji['size'] as number) ?? 1;
            if (emojiText && iconUrl) {
              emoteMap.set(emojiText, iconUrl + '||' + size);
            }
          }
        } else if (nodeType === 'RICH_TEXT_NODE_TYPE_AT') {
          const rid: number = Number(node['rid'] ?? 0);
          let uname: string = (node['text'] as string) ?? '';
          if (uname.startsWith('@')) uname = uname.substring(1);
          uname = uname.trim();
          if (uname && rid > 0) {
            memberMap.set(uname, new UserCard(uname, '', rid));
          }
        }
      }
    }
  }
  opus.emoteMap = emoteMap;
  opus.memberMap = memberMap;
}

/** 解析 MODULE_TYPE_STAT（统计数据） */
function parseStatModule(module: Record<string, Object>, opus: Opus): void {
  const stat: Record<string, Object> | undefined = module['module_stat'] as Record<string, Object> | undefined;
  if (!stat) return;

  const stats: ArticleStats = new ArticleStats();

  // 点赞
  const likeObj: Record<string, Object> | undefined = stat['like'] as Record<string, Object> | undefined;
  if (likeObj) {
    stats.like = (likeObj['count'] as number) ?? 0;
    stats.liked = (likeObj['status'] as boolean) ?? false;
  }

  // 播放/阅读
  const playObj: Record<string, Object> | undefined = stat['play'] as Record<string, Object> | undefined;
  if (playObj) {
    stats.view = (playObj['count'] as number) ?? 0;
  }

  // 评论
  const replyObj: Record<string, Object> | undefined = stat['comment'] as Record<string, Object> | undefined;
  if (replyObj) {
    stats.reply = (replyObj['count'] as number) ?? 0;
  }

  // 转发/收藏/投币（部分模块有）
  const forwardObj: Record<string, Object> | undefined = stat['forward'] as Record<string, Object> | undefined;
  if (forwardObj) {
    stats.share = (forwardObj['count'] as number) ?? 0;
  }

  const favObj: Record<string, Object> | undefined = stat['favorite'] as Record<string, Object> | undefined;
  if (favObj) {
    stats.favorite = (favObj['count'] as number) ?? 0;
  }

  const coinObj: Record<string, Object> | undefined = stat['coin'] as Record<string, Object> | undefined;
  if (coinObj) {
    stats.coin = (coinObj['count'] as number) ?? 0;
  }

  opus.stats = stats;
}

// =================================================================
//  4. 旧版专栏 API（JSON 接口）
// =================================================================

/**
 * 获取专栏详情（旧版 /x/article/view JSON API）
 *
 * GET https://api.bilibili.com/x/article/view
 *
 * @param cvid 专栏 ID（cv 号，不含 "cv" 前缀）
 * @returns 专栏详情，失败返回 null
 */
export async function getArticle(cvid: number): Promise<ArticleInfo | null> {
  let url: string = 'https://api.bilibili.com/x/article/view?'
    + 'id=' + cvid
    + '&gaia_source=main_web'
    + '&web_location=333.976';

  url = await signWBI(url);
  console.info('[ArticleApi] getArticle url=' + url);

  const resp: ApiResponse = await httpGet(url);
  if (resp.code !== 0 || !resp.data) {
    console.error('[ArticleApi] getArticle fail: code=' + resp.code);
    return null;
  }

  return parseArticleResponse(cvid, resp.data as Record<string, Object>);
}

/**
 * 获取专栏统计/交互信息（旧版 /x/article/viewinfo JSON API）
 *
 * GET https://api.bilibili.com/x/article/viewinfo
 *
 * 返回当前用户的交互状态（是否点赞/收藏/投币）。
 *
 * @param cvid 专栏 ID
 * @returns 专栏统计信息
 */
export async function getArticleViewInfo(cvid: number): Promise<ArticleInfo | null> {
  let url: string = 'https://api.bilibili.com/x/article/viewinfo?'
    + 'id=' + cvid
    + '&gaia_source=main_web'
    + '&web_location=333.976'
    + '&mobi_app=pc'
    + '&from=web';

  url = await signWBI(url);
  console.info('[ArticleApi] getArticleViewInfo url=' + url);

  const resp: ApiResponse = await httpGet(url);
  if (resp.code !== 0 || !resp.data) {
    console.error('[ArticleApi] getArticleViewInfo fail: code=' + resp.code);
    return null;
  }

  return parseArticleViewInfoResponse(cvid, resp.data as Record<string, Object>);
}

/**
 * 解析 Quill Delta 格式的正文（{"ops": [...]}）
 *
 * B 站新版专栏 API 返回的 content 可能是 Quill Delta 格式：
 *   {"ops":[
 *     {"insert":"标题"},
 *     {"attributes":{"header":1},"insert":"\n"},
 *     {"insert":"正文内容 ","attributes":{"bold":true}},
 *     {"insert":"\n"},
 *     {"insert":{"image":"https://..."}},
 *     {"insert":"\n"}
 *   ]}
 *
 * 解析为 ArticleParagraph[]：文本 → TEXT/HEADING，图片 → PIC。
 */
function parseQuillDelta(rawContent: string): ArticleParagraph[] {
  const result: ArticleParagraph[] = [];
  let data: Record<string, Object>;
  try {
    data = JSON.parse(rawContent) as Record<string, Object>;
  } catch (e) {
    console.warn('[ArticleApi] parseQuillDelta JSON 解析失败:', String(e));
    return result;
  }

  const ops: Array<Record<string, Object>> | undefined = data['ops'] as Array<Record<string, Object>> | undefined;
  if (!ops || ops.length === 0) {
    console.warn('[ArticleApi] parseQuillDelta: ops 数组为空');
    return result;
  }

  console.info('[ArticleApi] parseQuillDelta: ops 数量=' + ops.length + ' 第一条 type=' + typeof ops[0]['insert']);

  let textBuf: string = '';

  for (let i: number = 0; i < ops.length; i++) {
    const op: Record<string, Object> = ops[i];
    const insert: Object = op['insert'];
    const attrs: Record<string, Object> | undefined = op['attributes'] as Record<string, Object> | undefined;

    if (typeof insert === 'string') {
      const text: string = insert as string;

      if (text === '\n') {
        // \n 是块级分隔符：flush 当前累积的文本
        const header: number = (attrs && attrs['header'] as number) ?? 0;
        if (textBuf) {
          result.push(new ArticleParagraph(
            header > 0 ? ParagraphType.HEADING : ParagraphType.TEXT,
            0, textBuf
          ));
          textBuf = '';
        } else if (header > 0) {
          // 只有 header 属性没有文本（空标题段落）→ 忽略
        }
        // 重置 pendingHeader（\n 的属性只作用于 flush 的文本，不传播）
        continue;
      }

      // 普通文本直接追加到缓冲区
      // Quill Delta 中文本内的 \n 只是行内换行，不是块级分隔
      textBuf += text;
    } else if (typeof insert === 'object') {
      // Flush 当前文本
      if (textBuf) {
        result.push(new ArticleParagraph(ParagraphType.TEXT, 0, textBuf));
        textBuf = '';
      }

      const insertObj: Record<string, Object> = insert as Record<string, Object>;
      const imgUrl: string = (insertObj['image'] as string) ?? '';
      if (imgUrl) {
        const finalUrl: string = imgUrl.startsWith('//') ? 'https:' + imgUrl : imgUrl;
        result.push(new ArticleParagraph(ParagraphType.PIC, 0, [finalUrl]));
      }
    }
  }

  // Flush 剩余文本
  if (textBuf) {
    result.push(new ArticleParagraph(ParagraphType.TEXT, 0, textBuf));
  }

  console.info('[ArticleApi] parseQuillDelta: 解析出 ' + result.length + ' 个段落');
  return result;
}

/** 解析 /x/article/view 响应 */
function parseArticleResponse(cvid: number, data: Record<string, Object>): ArticleInfo {
  const info: ArticleInfo = new ArticleInfo();
  info.id = cvid;
  info.title = (data['title'] as string) ?? '';
  info.summary = (data['summary'] as string) ?? '';
  info.banner = (data['banner_url'] as string) ?? '';
  info.ctime = (data['ctime'] as number) ?? 0;
  info.wordCount = (data['words'] as number) ?? 0;
  info.keywords = (data['keywords'] as string) ?? '';

  // --- UP 主信息 ---
  const author: Record<string, Object> | undefined = data['author'] as Record<string, Object> | undefined;
  if (author) {
    info.upInfo = new UserCard(
      (author['name'] as string) ?? '',
      (author['face'] as string) ?? '',
      Number(author['mid'] ?? 0),
      undefined,
      String((author['level'] as number) ?? ''),
    );
  }

  // --- 统计数据 ---
  const stats: Record<string, Object> | undefined = data['stats'] as Record<string, Object> | undefined;
  if (stats) {
    info.stats.view = (stats['view'] as number) ?? 0;
    info.stats.favorite = (stats['favorite'] as number) ?? 0;
    info.stats.like = (stats['like'] as number) ?? 0;
    info.stats.reply = (stats['reply'] as number) ?? 0;
    info.stats.share = (stats['share'] as number) ?? 0;
    info.stats.coin = (stats['coin'] as number) ?? 0;
  }
  info.stats.liked = (data['is_like'] as boolean) ?? false;

  // --- 正文（B 站 API 可能返回 HTML 或 JSON 两种格式） ---
  const rawContent: string = (data['content'] as string) ?? '';
  info.rawContent = rawContent;

  if (rawContent) {
    const trimmed: string = rawContent.trim();
    const firstCh: string = trimmed.charAt(0);
    console.info('[ArticleApi] parseArticleResponse: 格式检测 firstCh="' + firstCh + '" 前32字符=' + rawContent.substring(0, 32));

    if (firstCh === '[') {
      // Opus 段落 JSON 数组：[{"para_type":1,...},...]
      try {
        const jsonArray: Array<Record<string, Object>> = JSON.parse(trimmed) as Array<Record<string, Object>>;
        info.paragraphs = parseParagraphs(jsonArray);
        console.info('[ArticleApi] parseArticleResponse Opus 段落 JSON 解析出 ' + info.paragraphs.length + ' 个段落');
      } catch (e) {
        console.warn('[ArticleApi] parseArticleResponse content 以 [ 开头但 JSON 解析失败，降级为 HTML:', String(e));
        info.paragraphs = parseHtmlToParagraphs(rawContent);
      }
    } else if (firstCh === '{' && trimmed.indexOf('"ops"') >= 0) {
      // Quill Delta 格式：{"ops":[...]}
      console.info('[ArticleApi] parseArticleResponse: 检测到 Quill Delta 格式');
      info.paragraphs = parseQuillDelta(rawContent);
      if (info.paragraphs.length === 0) {
        console.warn('[ArticleApi] parseArticleResponse Quill Delta 解析结果为空，降级为 HTML 解析');
        info.paragraphs = parseHtmlToParagraphs(rawContent);
      }
    } else if (firstCh === '<' || firstCh === '\n') {
      // HTML 格式
      const contentLen: number = rawContent.length;
      console.info('[ArticleApi] parseArticleResponse HTML 格式: 长度=' + contentLen + ' 前64字符=' + rawContent.substring(0, 64));
      info.paragraphs = parseHtmlToParagraphs(rawContent);
      console.info('[ArticleApi] parseArticleResponse HTML 解析出 ' + info.paragraphs.length + ' 个段落');
    } else {
      // 未知格式，尝试 HTML 解析
      console.warn('[ArticleApi] parseArticleResponse 未知格式（firstCh="' + firstCh + '"），尝试 HTML 解析');
      const contentLen: number = rawContent.length;
      console.info('[ArticleApi] parseArticleResponse rawContent 长度=' + contentLen + ' 前128字符=' + rawContent.substring(0, 128));
      info.paragraphs = parseHtmlToParagraphs(rawContent);
      console.info('[ArticleApi] parseArticleResponse HTML 降级解析出 ' + info.paragraphs.length + ' 个段落');
    }
  } else {
    console.warn('[ArticleApi] parseArticleResponse rawContent 为空');
  }

  return info;
}

/** 解析 /x/article/viewinfo 响应 */
function parseArticleViewInfoResponse(cvid: number, data: Record<string, Object>): ArticleInfo {
  const info: ArticleInfo = new ArticleInfo();
  info.id = cvid;
  info.title = (data['title'] as string) ?? '';
  info.banner = (data['banner_url'] as string) ?? '';

  // --- UP 主信息 ---
  info.upInfo = new UserCard(
    (data['author_name'] as string) ?? '',
    '',
    Number(data['mid'] ?? 0)
  );

  // --- 统计数据 & 交互状态 ---
  const stats: Record<string, Object> | undefined = data['stats'] as Record<string, Object> | undefined;
  if (stats) {
    info.stats.view = (stats['view'] as number) ?? 0;
    info.stats.favorite = (stats['favorite'] as number) ?? 0;
    info.stats.like = (stats['like'] as number) ?? 0;
    info.stats.reply = (stats['reply'] as number) ?? 0;
    info.stats.share = (stats['share'] as number) ?? 0;
    info.stats.coin = (stats['coin'] as number) ?? 0;
  }
  info.stats.liked = ((data['like'] as number) ?? 0) === 1;
  info.stats.favoured = (data['favorite'] as boolean) ?? false;
  // coined 为投币数（非 coin 统计数），从 data 中读取
  info.stats.coined = (data['coin'] as number) ?? 0;

  return info;
}

// =================================================================
//  5. 正文段落解析
// =================================================================

/**
 * 将 /x/article/view 返回的 HTML 正文解析为 ArticleParagraph[]。
 *
 * B 站专栏 HTML 正文格式示例：
 *   <p>普通段落</p>
 *   <p><img src="..." .../></p>
 *   <p><strong>粗体</strong></p>
 *   纯文本+<br/>换行
 */
export function parseHtmlToParagraphs(html: string): ArticleParagraph[] {
  const result: ArticleParagraph[] = [];
  if (!html) return result;

  // 按 <p> 标签分割段落
  const pBlockRe: RegExp = /<p[^>]*>([\s\S]*?)<\/p>/gi;
  let pMatch: RegExpExecArray | null;
  let lastIndex: number = 0;

  while ((pMatch = pBlockRe.exec(html)) !== null) {
    lastIndex = pMatch.index + pMatch[0].length;
    const pContent: string = pMatch[1].trim();
    if (!pContent) {
      result.push(new ArticleParagraph(ParagraphType.TEXT, 0, ''));
      continue;
    }

    // 检测是否包含 <img> 标签
    if (/<img[^>]*>/i.test(pContent)) {
      console.info('[ArticleApi] parseHtmlToParagraphs 发现 img: ' + pContent.substring(0, 120));
      const imgMatch: RegExpExecArray | null = /<img[^>]*src=["']([^"']+)["'][^>]*>/i.exec(pContent);
      if (imgMatch) {
        let imgUrl: string = imgMatch[1];
        if (!imgUrl.startsWith('http')) imgUrl = 'https:' + imgUrl;
        console.info('[ArticleApi] parseHtmlToParagraphs img url=' + imgUrl);
        result.push(new ArticleParagraph(ParagraphType.PIC, 0, [imgUrl]));
      } else {
        // img 标签存在但 srcd没有匹配到，尝试其他属性格式
        console.warn('[ArticleApi] parseHtmlToParagraphs img 标签存在但 src 未匹配到');
        const altImgMatch: RegExpExecArray | null = /<img[^>]*src=([^\s>]+)/i.exec(pContent);
        if (altImgMatch) {
          let imgUrl: string = altImgMatch[1].replace(/['"]/g, '');
          if (!imgUrl.startsWith('http')) imgUrl = 'https:' + imgUrl;
          console.info('[ArticleApi] parseHtmlToParagraphs alt img url=' + imgUrl);
          result.push(new ArticleParagraph(ParagraphType.PIC, 0, [imgUrl]));
        }
      }
      // 还有文本内容的话追加为文本段落
      const textOnly: string = pContent.replace(/<[^>]+>/g, '').trim();
      if (textOnly) {
        result.push(new ArticleParagraph(ParagraphType.TEXT, 0, decodeHTML(textOnly)));
      }
    } else {
      // 纯文本段落
      let cleanText: string = stripHtmlTags(pContent);
      if (cleanText) {
        result.push(new ArticleParagraph(ParagraphType.TEXT, 0, cleanText));
      }
    }
  }

  // 处理 <p> 标签外的剩余内容（如有）
  if (lastIndex > 0 && lastIndex < html.length) {
    const remaining: string = html.substring(lastIndex).trim();
    if (remaining && !/^<\/?[a-z]+>/.test(remaining)) {
      const clean: string = stripHtmlTags(remaining);
      if (clean) {
        result.push(new ArticleParagraph(ParagraphType.TEXT, 0, clean));
      }
    }
  }

  // ── 无条件扫描 <figure> 包裹的图片（可能有图在 <figure> 内而非 <p>） ──
  const seenUrls: Set<string> = new Set();
  // 收集已添加的图片 URL 用于去重
  for (let si: number = 0; si < result.length; si++) {
    if (result[si].isImage()) {
      const urls: string[] = result[si].getPictures();
      for (let uj: number = 0; uj < urls.length; uj++) {
        if (urls[uj]) seenUrls.add(urls[uj]);
      }
    }
  }

  const figRe: RegExp = /<figure[^>]*>([\s\S]*?)<\/figure>/gi;
  let figMatch: RegExpExecArray | null;
  while ((figMatch = figRe.exec(html)) !== null) {
    const figContent: string = figMatch[1];
    const imgInFig: RegExpExecArray | null = /<img[^>]*src=["']?([^"'\s>]+)["']?[^>]*>/i.exec(figContent);
    if (imgInFig) {
      let imgUrl: string = imgInFig[1];
      if (!imgUrl.startsWith('http')) imgUrl = 'https:' + imgUrl;
      if (!seenUrls.has(imgUrl)) {
        seenUrls.add(imgUrl);
        console.info('[ArticleApi] parseHtmlToParagraphs figure img url=' + imgUrl);
        result.push(new ArticleParagraph(ParagraphType.PIC, 0, [imgUrl]));
      }
    }
  }

  // ── 无条件全局扫描所有 <img src=…> 标签（去重） ──
  const globalImgRe: RegExp = /<img[^>]*src=["']?([^"'\s>]+)["']?[^>]*>/gi;
  let globalImg: RegExpExecArray | null;
  while ((globalImg = globalImgRe.exec(html)) !== null) {
    let imgUrl: string = globalImg[1];
    if (!imgUrl.startsWith('http')) imgUrl = 'https:' + imgUrl;
    // 在 ArkTS 中 Set.has 需要 explicit check
    const alreadyHas: boolean = seenUrls.has(imgUrl);
    if (!alreadyHas) {
      seenUrls.add(imgUrl);
      console.info('[ArticleApi] parseHtmlToParagraphs 全局扫描 img url=' + imgUrl);
      result.push(new ArticleParagraph(ParagraphType.PIC, 0, [imgUrl]));
      // 安全限制：最多 50 张图
      let imgCount: number = 0;
      for (let ci: number = 0; ci < result.length; ci++) {
        if (result[ci].isImage()) imgCount++;
      }
      if (imgCount > 50) break;
    }
  }

  // 仍无结果，按 <br> 分割
  if (result.length === 0) {
    const lines: string[] = html.split(/<br\s*\/?>/i);
    for (let i: number = 0; i < lines.length; i++) {
      const clean: string = stripHtmlTags(lines[i]);
      if (clean) {
        result.push(new ArticleParagraph(ParagraphType.TEXT, 0, clean));
      }
    }
  }

  // 最后的兜底
  if (result.length === 0) {
    const clean: string = stripHtmlTags(html);
    if (clean) {
      result.push(new ArticleParagraph(ParagraphType.TEXT, 0, clean));
    }
  }

  return result;
}

/**
 * 解析段落数组 JSON → ArticleParagraph[]
 *
 * 处理 Opus API 的 paragraphs JSON 数组中的各种 para_type。
 */
export function parseParagraphs(
  paragraphsJson: Array<Record<string, Object>>
): ArticleParagraph[] {
  const result: ArticleParagraph[] = [];

  for (let i: number = 0; i < paragraphsJson.length; i++) {
    const para: ArticleParagraph = parseSingleParagraph(paragraphsJson[i]);
    result.push(para);
  }

  return result;
}

/** 解析单个段落 JSON → ArticleParagraph */
function parseSingleParagraph(json: Record<string, Object>): ArticleParagraph {
  const paraType: number = (json['para_type'] as number) ?? ParagraphType.TEXT;
  const align: number = (json['align'] as number) ?? 0;
  const para: ArticleParagraph = new ArticleParagraph(paraType, align);

  switch (paraType) {
    case ParagraphType.TEXT:
      para.content = parseTextContent(json['text'] as Record<string, Object> | undefined);
      break;
    case ParagraphType.HEADING:
      para.content = parseTextContent(json['heading'] as Record<string, Object> | undefined);
      break;
    case ParagraphType.TEXT_BLOCKQUOTE:
      para.content = parseBlockquoteContent(json['blockquote'] as Record<string, Object> | undefined);
      break;
    case ParagraphType.LIST:
      para.content = parseListContent(json['list'] as Record<string, Object> | undefined);
      break;
    case ParagraphType.PIC:
      para.content = parsePictureContent(json['pic'] as Record<string, Object> | undefined);
      break;
    case ParagraphType.DIVIDER:
      para.content = parseDividerContent(json['line'] as Record<string, Object> | undefined);
      break;
    case ParagraphType.TEXT_OPUS:
      para.content = parseOpusRichText(json['data'] as Array<Record<string, Object>> | undefined);
      break;
    case ParagraphType.VIDEO:
      para.content = parseVideoCard(json['archive'] as Record<string, Object> | undefined);
      break;
    case ParagraphType.ARTICLE:
      para.content = parseArticleCard(json['article'] as Record<string, Object> | undefined);
      break;
    default:
      para.content = '[无法识别段落类型: ' + paraType + ']';
      break;
  }

  return para;
}

/** 解析普通文本段落节点 */
function parseTextContent(textObj: Record<string, Object> | undefined): string {
  if (!textObj) return '';
  const nodes: Array<Record<string, Object>> | undefined = textObj['nodes'] as Array<Record<string, Object>> | undefined;
  if (!nodes) return '';

  let text: string = '';
  for (let i: number = 0; i < nodes.length; i++) {
    const node: Record<string, Object> = nodes[i];
    const nodeType: string = (node['type'] as string) ?? 'TEXT_NODE_TYPE_WORD';

    switch (nodeType) {
      case 'TEXT_NODE_TYPE_WORD': {
        const word: Record<string, Object> | undefined = node['word'] as Record<string, Object> | undefined;
        if (word) {
          text += (word['words'] as string) ?? '';
        }
        break;
      }
      case 'TEXT_NODE_TYPE_RICH': {
        const rich: Record<string, Object> | undefined = node['rich'] as Record<string, Object> | undefined;
        if (rich) {
          text += (rich['text'] as string) ?? '';
        }
        break;
      }
      default:
        text += '[' + nodeType + ']';
        break;
    }
  }

  return decodeHTML(text);
}

/** 解析引用块节点 */
function parseBlockquoteContent(blockquote: Record<string, Object> | undefined): string {
  if (!blockquote) return '';

  const children: Array<Record<string, Object>> | undefined
    = blockquote['children'] as Array<Record<string, Object>> | undefined;
  if (!children) return '';

  let text: string = '';
  for (let i: number = 0; i < children.length; i++) {
    const child: Record<string, Object> = children[i];
    const childText: Record<string, Object> | undefined
      = child['text'] as Record<string, Object> | undefined;
    if (childText) {
      text += parseTextContent(childText);
    }
  }

  return text;
}

/** 解析列表节点 */
function parseListContent(listObj: Record<string, Object> | undefined): string {
  if (!listObj) return '';

  const listStyle: number = (listObj['style'] as number) ?? ListStyle.DOT;
  let text: string = '';

  // items 子项（简化列表）
  const items: Array<Record<string, Object>> | undefined
    = listObj['items'] as Array<Record<string, Object>> | undefined;
  if (items) {
    for (let i: number = 0; i < items.length; i++) {
      if (i > 0) text += '\n';
      if (listStyle === ListStyle.NUMBER) {
        text += String((items[i]['order'] as number) ?? (i + 1)) + '. ';
      } else {
        text += '· ';
      }
      text += parseTextContent(items[i]);
    }
  }

  // children 子项（复杂列表，带嵌套文本节点）
  const children: Array<Record<string, Object>> | undefined
    = listObj['children'] as Array<Record<string, Object>> | undefined;
  if (children) {
    for (let i: number = 0; i < children.length; i++) {
      if (text.length > 0) text += '\n';
      if (listStyle === ListStyle.NUMBER) {
        text += String((children[i]['order'] as number) ?? (i + 1)) + '. ';
      } else {
        text += '· ';
      }

      const subChildren: Array<Record<string, Object>> | undefined
        = children[i]['children'] as Array<Record<string, Object>> | undefined;
      if (subChildren) {
        for (let j: number = 0; j < subChildren.length; j++) {
          const subText: Record<string, Object> | undefined
            = subChildren[j]['text'] as Record<string, Object> | undefined;
          if (subText) {
            text += parseTextContent(subText);
          }
        }
      }
    }
  }

  return text;
}

/** 解析图片段落 */
function parsePictureContent(picObj: Record<string, Object> | undefined): string[] {
  if (!picObj) return [];

  const pics: Array<Record<string, Object>> | undefined
    = picObj['pics'] as Array<Record<string, Object>> | undefined;
  if (!pics) return [];

  const urls: string[] = [];
  for (let i: number = 0; i < pics.length; i++) {
    let url: string = (pics[i]['url'] as string) ?? '';
    if (url && !url.startsWith('http')) {
      url = 'https:' + url;
    }
    if (url) urls.push(url);
  }
  return urls;
}

/** 解析分割线段落 */
function parseDividerContent(lineObj: Record<string, Object> | undefined): string[] {
  if (!lineObj) return [];
  const pic: Record<string, Object> | undefined = lineObj['pic'] as Record<string, Object> | undefined;
  if (!pic) return [];

  let url: string = (pic['url'] as string) ?? '';
  if (url && !url.startsWith('http')) {
    url = 'https:' + url;
  }
  return url ? [url] : [];
}

/** 解析 Opus 富文本节点（@提及 / 表情 / 话题） */
function parseOpusRichText(nodes: Array<Record<string, Object>> | undefined): string {
  if (!nodes) return '';

  let text: string = '';
  for (let i: number = 0; i < nodes.length; i++) {
    const node: Record<string, Object> = nodes[i];
    const nodeType: string = (node['type'] as string) ?? '';

    switch (nodeType) {
      case 'RICH_TEXT_NODE_TYPE_AT':
      case 'RICH_TEXT_NODE_TYPE_TOPIC':
        text += (node['text'] as string) ?? '';
        break;
      case 'RICH_TEXT_NODE_TYPE_EMOJI':
        text += (node['text'] as string) ?? '';
        break;
      case 'RICH_TEXT_NODE_TYPE_TEXT':
      default:
        text += (node['orig_text'] as string) ?? '';
        break;
    }
  }

  return decodeHTML(text);
}

/** 从 archive JSON 解析视频卡片 */
function parseVideoCard(archive: Record<string, Object> | undefined): VideoCard | string {
  if (!archive) return '[视频卡片]';
  const vc: VideoCard = new VideoCard(
    (archive['title'] as string) ?? '',
    (archive['owner_name'] as string) ?? (archive['author_name'] as string) ?? '',
    '',  // view 稍后填充
    (archive['cover'] as string) ?? (archive['pic'] as string) ?? '',
    Number(archive['aid'] ?? 0),
    (archive['bvid'] as string) ?? ''
  );
  const stat: Record<string, Object> | undefined = archive['stat'] as Record<string, Object> | undefined;
  if (stat) {
    vc.formatedView = formatCount((stat['view'] as number) ?? 0) + '播放';
  }
  console.info('[ArticleApi] parseVideoCard: title=' + vc.title + ' aid=' + vc.aid);
  return vc;
}

/** 从 article JSON 解析关联专栏卡片 */
function parseArticleCard(article: Record<string, Object> | undefined): ArticleCard | string {
  if (!article) return '[关联专栏]';
  const covers: string[] = [];
  const cover: string = (article['cover'] as string) ?? (article['banner_url'] as string) ?? '';
  if (cover) covers.push(cover);
  const ac: ArticleCard = new ArticleCard(
    (article['title'] as string) ?? '',
    (article['author_name'] as string) ?? (article['up_name'] as string) ?? '',
    '',
    covers,
    Number(article['id'] ?? article['cvid'] ?? 0)
  );
  console.info('[ArticleApi] parseArticleCard: title=' + ac.title + ' cvid=' + ac.cvid);
  return ac;
}

// =================================================================
//  6. 交互操作接口
// =================================================================

/**
 * 从 cookie 中提取 CSRF token
 */
function getCsrf(): string {
  return cookieMap['bili_jct'] || AppStorage.get<string>('csrf') || '';
}

/**
 * 点赞 / 取消赞 专栏
 *
 * POST https://api.bilibili.com/x/article/like
 *
 * @param cvid 专栏 ID
 * @param like true=点赞，false=取消赞
 * @returns 是否操作成功
 */
export async function likeArticle(cvid: number, like: boolean): Promise<boolean> {
  const csrf: string = getCsrf();
  if (!csrf) {
    console.warn('[ArticleApi] likeArticle: csrf 为空');
    return false;
  }

  const formData: string = 'id=' + cvid
    + '&type=' + (like ? 1 : 2)
    + '&csrf=' + encodeURIComponent(csrf);

  console.info('[ArticleApi] likeArticle: cvid=' + cvid + ' like=' + like);

  try {
    const resp: ApiResponse = await httpPostForm(
      'https://api.bilibili.com/x/article/like',
      formData
    );
    console.info('[ArticleApi] likeArticle 响应 code=' + resp.code);
    return resp.code === 0;
  } catch (e) {
    console.error('[ArticleApi] likeArticle 异常:', String(e));
    return false;
  }
}

/**
 * 给专栏投币
 *
 * POST https://api.bilibili.com/x/web-interface/coin/add
 *
 * @param cvid     专栏 ID
 * @param upid     UP 主 UID
 * @param multiply 投币数量（1 或 2）
 * @returns 是否操作成功
 */
export async function addCoin(cvid: number, upid: number, multiply: number): Promise<number> {
  const csrf: string = getCsrf();
  if (!csrf) {
    console.warn('[ArticleApi] addCoin: csrf 为空');
    return -1;
  }

  const formData: string = 'aid=' + cvid
    + '&upid=' + upid
    + '&avtype=2'
    + '&multiply=' + multiply
    + '&csrf=' + encodeURIComponent(csrf);

  console.info('[ArticleApi] addCoin: cvid=' + cvid + ' upid=' + upid + ' multiply=' + multiply);

  try {
    const resp: ApiResponse = await httpPostForm(
      'https://api.bilibili.com/x/web-interface/coin/add',
      formData
    );
    console.info('[ArticleApi] addCoin 响应 code=' + resp.code);
    return resp.code;
  } catch (e) {
    console.error('[ArticleApi] addCoin 异常:', String(e));
    return -1;
  }
}

/**
 * 收藏专栏
 *
 * POST https://api.bilibili.com/x/article/favorites/add
 *
 * @param cvid 专栏 ID
 * @returns 是否操作成功
 */
export async function favoriteArticle(cvid: number): Promise<boolean> {
  const csrf: string = getCsrf();
  if (!csrf) {
    console.warn('[ArticleApi] favoriteArticle: csrf 为空');
    return false;
  }

  const formData: string = 'id=' + cvid
    + '&csrf=' + encodeURIComponent(csrf);

  console.info('[ArticleApi] favoriteArticle: cvid=' + cvid);

  try {
    const resp: ApiResponse = await httpPostForm(
      'https://api.bilibili.com/x/article/favorites/add',
      formData
    );
    console.info('[ArticleApi] favoriteArticle 响应 code=' + resp.code);
    return resp.code === 0;
  } catch (e) {
    console.error('[ArticleApi] favoriteArticle 异常:', String(e));
    return false;
  }
}

/**
 * 取消收藏专栏
 *
 * POST https://api.bilibili.com/x/article/favorites/del
 *
 * @param cvid 专栏 ID
 * @returns 是否操作成功
 */
export async function delFavoriteArticle(cvid: number): Promise<boolean> {
  const csrf: string = getCsrf();
  if (!csrf) {
    console.warn('[ArticleApi] delFavoriteArticle: csrf 为空');
    return false;
  }

  const formData: string = 'id=' + cvid
    + '&csrf=' + encodeURIComponent(csrf);

  console.info('[ArticleApi] delFavoriteArticle: cvid=' + cvid);

  try {
    const resp: ApiResponse = await httpPostForm(
      'https://api.bilibili.com/x/article/favorites/del',
      formData
    );
    console.info('[ArticleApi] delFavoriteArticle 响应 code=' + resp.code);
    return resp.code === 0;
  } catch (e) {
    console.error('[ArticleApi] delFavoriteArticle 异常:', String(e));
    return false;
  }
}

// =================================================================
//  7. Opus ID 转 cvID（用于动态 → 专栏跳转）
// =================================================================

/**
 * Opus ID 到 cvID 的转换结果
 */
export class OpusIdMapping {
  /** 目标类型：1=动态(ITEM), 2=文章(FALLBACK) */
  type: number = 0;
  /** 目标 cvID */
  id: number = 0;

  constructor(type?: number, id?: number) {
    if (type !== undefined) this.type = type;
    if (id !== undefined) this.id = id;
  }
}

/**
 * 通过 Opus ID 获取对应的 cvID（专栏 ID）。
 *
 * GET https://api.bilibili.com/x/polymer/web-dynamic/v1/opus/detail
 *
 * Opus ID 是动态系统里的统一作品 ID，不同于 cv 号。
 * 当从动态卡片点击 Opus 类型动态时，需要用此接口将 Opus ID 转为 cvID。
 *
 * @param opusId Opus 作品 ID
 * @returns OpusIdMapping 或 null
 */
export async function opusId2cvid(opusId: number): Promise<OpusIdMapping | null> {
  const url: string = 'https://api.bilibili.com/x/polymer/web-dynamic/v1/opus/detail?'
    + 'id=' + opusId
    + '&time_zone_offset=-480';

  console.info('[ArticleApi] opusId2cvid url=' + url);

  try {
    const resp: ApiResponse = await httpGet(url);
    if (resp.code !== 0 || !resp.data) {
      console.error('[ArticleApi] opusId2cvid fail: code=' + resp.code);
      return null;
    }

    const data: Record<string, Object> = resp.data as Record<string, Object>;
    const item: Record<string, Object> | undefined = data['item'] as Record<string, Object> | undefined;
    const fallback: Record<string, Object> | undefined = data['fallback'] as Record<string, Object> | undefined;

    if (item) {
      const basic: Record<string, Object> | undefined = item['basic'] as Record<string, Object> | undefined;
      if (basic) {
        const ridStr: string = (basic['rid_str'] as string) ?? '';
        if (ridStr) {
          return new OpusIdMapping(1, Number(ridStr));
        }
      }
    }

    if (fallback) {
      const fallbackId: string = (fallback['id'] as string) ?? '';
      if (fallbackId) {
        return new OpusIdMapping(2, Number(fallbackId));
      }
    }

    return null;
  } catch (e) {
    console.error('[ArticleApi] opusId2cvid 异常:', String(e));
    return null;
  }
}

