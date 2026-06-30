/**
 * 专栏详情数据模型
 *
 * 对应 B 站 /x/article/view 接口返回的专栏完整详情。
 * 也兼容 Opus API 返回的图文/专栏内容字段。
 *
 * 使用场景：
 *   1. 专栏详情页展示：标题、摘要、头图、正文段落、UP主信息
 *   2. 交互操作数据源：点赞、投币、收藏状态
 *   3. 统计数据：阅读量、点赞数、投币数、收藏数、分享数、评论数
 */

import { UserCard } from './UserCard';
import { ArticleParagraph } from './ArticleParagraph';

/**
 * 专栏统计
 *
 * 包含专栏的互动数据和当前用户的交互状态。
 */
export class ArticleStats {
  /** 阅读量 */
  view: number = 0;
  /** 点赞数 */
  like: number = 0;
  /** 投币数 */
  coin: number = 0;
  /** 收藏数 */
  favorite: number = 0;
  /** 分享数 */
  share: number = 0;
  /** 评论数 */
  reply: number = 0;
  /** 当前用户是否已点赞 */
  liked: boolean = false;
  /** 当前用户是否已收藏 */
  favoured: boolean = false;
  /** 当前用户已投币数量（通常为 0/1/2） */
  coined: number = 0;
  /** 投币上限（通常为 2） */
  coin_limit: number = 2;

  constructor(
    view?: number,
    like?: number,
    coin?: number,
    favorite?: number,
    share?: number,
    reply?: number,
    liked?: boolean,
    favoured?: boolean,
    coined?: number,
    coin_limit?: number
  ) {
    if (view !== undefined) this.view = view;
    if (like !== undefined) this.like = like;
    if (coin !== undefined) this.coin = coin;
    if (favorite !== undefined) this.favorite = favorite;
    if (share !== undefined) this.share = share;
    if (reply !== undefined) this.reply = reply;
    if (liked !== undefined) this.liked = liked;
    if (favoured !== undefined) this.favoured = favoured;
    if (coined !== undefined) this.coined = coined;
    if (coin_limit !== undefined) this.coin_limit = coin_limit;
  }
}

/**
 * 专栏详情
 *
 * 对应 B 站 /x/article/view 接口返回的核心数据，
 * 也作为 Opus 图文类内容的详情容器。
 */
export class ArticleInfo {
  /** 专栏 ID（cv号，不含"cv"前缀） */
  id: number = 0;
  /** 标题 */
  title: string = '';
  /** 摘要 */
  summary: string = '';
  /** 头图 URL（banner_url） */
  banner: string = '';
  /** 发布者信息 */
  upInfo: UserCard = new UserCard();
  /** 发布时间（Unix 时间戳，秒） */
  ctime: number = 0;
  /** 统计数据 */
  stats: ArticleStats = new ArticleStats();
  /** 字数 */
  wordCount: number = 0;
  /** 关键词 */
  keywords: string = '';

  // ===== 正文内容 =====

  /**
   * 正文段落数组。
   * 由 API 层解析 HTML/JSON 后填充。
   * 旧版 /x/article/view API 会反回 HTML 格式的 content，
   * 由 API 层解析为 ArticleParagraph[] 后填入此字段。
   * Opus API 直接返回结构化的 paragraphs JSON，
   * 由 API 层直接转换填充。
   */
  paragraphs: ArticleParagraph[] = [];

  /**
   * 原始 HTML 正文（仅旧版 /x/article/view 接口存在）。
   * 新版 Opus API 返回结构化的 paragraphs 数据，此时此字段为空。
   * 可通过 ArticleApi.parseContentHtml() 将其解析为 paragraphs。
   */
  rawContent: string = '';

  /**
   * 顶部图片列表（Opus API 的 MODULE_TYPE_TOP）。
   * Opus 图文类动态的封面图组（与 banner 不同）。
   */
  topImages: string[] = [];

  // ===== 评论区信息 =====

  /** 关联的评论区 ID */
  commentId: number = 0;
  /** 评论区类型（评论 API 需要此值） */
  commentType: number = 0;

  constructor(
    id?: number,
    title?: string,
    summary?: string,
    banner?: string,
    upInfo?: UserCard,
    ctime?: number,
    stats?: ArticleStats,
    wordCount?: number,
    keywords?: string
  ) {
    if (id !== undefined) this.id = id;
    if (title !== undefined) this.title = title;
    if (summary !== undefined) this.summary = summary;
    if (banner !== undefined) this.banner = banner;
    if (upInfo !== undefined) this.upInfo = upInfo;
    if (ctime !== undefined) this.ctime = ctime;
    if (stats !== undefined) this.stats = stats;
    if (wordCount !== undefined) this.wordCount = wordCount;
    if (keywords !== undefined) this.keywords = keywords;
  }
}
