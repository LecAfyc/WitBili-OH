/**
 * Opus 统一作品数据模型
 *
 * 对应 B 站新版 /opus/{id} 页面内嵌 JSON 的 detail 结构。
 * 动态（DYNAMIC）和专栏（ARTICLE）在新版架构下被统一为 "Opus"，
 * 详情页统一通过此模型渲染。
 *
 * 数据来源：OpusApi.getOpus(id) 从 HTML 中提取 INITIAL_STATE.detail
 *
 * 与 Dynamic 的关系：
 *   - Dynamic 用于动态瀑布流列表（卡片摘要 + 交互）
 *   - Opus    用于详情页完整展示（正文段落 + 完整数据）
 *
 * 类型判断：
 *   TYPE_DYNAMIC         = 1  → Opus 图文动态（富文本 + 图片）
 *   TYPE_ARTICLE         = 2  → 老专栏 cv 号（正文段落）
 *   TYPE_DYNAMIC_OLD_STYLE = 3 → 旧版动态（降级到旧版详情页）
 */

import { UserCard } from './UserCard';
import { ArticleParagraph } from './ArticleParagraph';
import { ArticleStats } from './ArticleInfo';

/**
 * Opus 类型常量
 */
export class OpusType {
  /** Opus 图文动态 */
  static readonly DYNAMIC: number = 1;
  /** 老专栏（cv号） */
  static readonly ARTICLE: number = 2;
  /** 旧版动态（需降级到旧版详情页） */
  static readonly DYNAMIC_OLD_STYLE: number = 3;
}

/**
 * 统一作品模型
 */
export class Opus {
  /** 作品 ID */
  id: number = 0;
  /** 作品类型（见 OpusType） */
  type: number = OpusType.DYNAMIC;
  // ===== 基础信息 =====
  /** 标题 */
  title: string = '';
  /** 封面图 URL */
  cover: string = '';
  /** 原始内容文本（降级用） */
  content: string = '';
  /** 后端返回的已格式化发布时间 */
  pubTime: string = '';
  /** 发布时间（Unix 时间戳，秒） */
  ctime: number = 0;
  // ===== 发布者 =====
  /** UP 主信息 */
  upInfo: UserCard = new UserCard();
  // ===== 统计数据 =====
  /** 点赞/投币/收藏等统计 */
  stats: ArticleStats = new ArticleStats();
  // ===== 正文内容 =====
  /** 顶部图片列表（封面组图） */
  topImages: string[] = [];
  /** 正文段落数组 */
  paragraphs: ArticleParagraph[] = [];
  // ===== 富文本（Opus 图文动态的尾部描述） =====
  /**
   * Opus 图文类动态的富文本描述。
   * 表情以 "[表情名]" 占位，配合 emoteMap 渲染。
   * @提及保留原文 "@用户名 "，配合 memberMap 实现跳转。
   */
  message: string = '';
  /** 表情名 → 图片 URL 的映射 */
  emoteMap: Map<string, string> = new Map();
  /** @用户名 → UserCard 的映射 */
  memberMap: Map<string, UserCard> = new Map();
  // ===== 评论区信息 =====
  /** 关联的评论区 ID */
  commentId: number = 0;
  /** 评论区类型（评论 API 需要此值） */
  commentType: number = 0;

  constructor(
    id?: number,
    type?: number,
    title?: string,
    cover?: string,
    upInfo?: UserCard,
    stats?: ArticleStats,
    pubTime?: string
  ) {
    if (id !== undefined) {
      this.id = id;
    }
    if (type !== undefined) {
      this.type = type;
    }
    if (title !== undefined) {
      this.title = title;
    }
    if (cover !== undefined) {
      this.cover = cover;
    }
    if (upInfo !== undefined) {
      this.upInfo = upInfo;
    }
    if (stats !== undefined) {
      this.stats = stats;
    }
    if (pubTime !== undefined) {
      this.pubTime = pubTime;
    }
  }
}
