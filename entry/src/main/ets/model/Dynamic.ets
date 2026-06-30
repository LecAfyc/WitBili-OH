/**
 * 动态数据模型
 *
 * 对应 B站 /x/polymer/web-dynamic/v1/ 系列接口返回的动态。
 * 富文本处理仿 CommentCard 的 emoteMap + memberMap 模式：
 *   - message 存文本原文，表情用 "[表情名]" 占位
 *   - emoteMap 存表情名 -> 图片URL 的映射
 *   - memberMap 存 @用户名 -> UserCard 的映射
 *
 * 附加内容（major_object）为多态，通过 major_type 字符串运行时识别，
 * 可以是 VideoCard / ArticleCard / string[]（图片列表) 等。
 */

import { UserCard } from "./UserCard";
import { VideoCard, ArticleCard } from "./ContentCard";

// ===== 动态统计 =====
export class DynamicStats {
  like: number = 0;        // 点赞数
  liked: boolean = false;  // 当前用户是否已点赞
  reply: number = 0;       // 评论数
  forward: number = 0;     // 转发数

  constructor(like?: number, liked?: boolean, reply?: number, forward?: number) {
    if (like !== undefined) this.like = like;
    if (liked !== undefined) this.liked = liked;
    if (reply !== undefined) this.reply = reply;
    if (forward !== undefined) this.forward = forward;
  }
}

// ===== 动态主类 =====
export class Dynamic {
  // --- 基础信息 ---
  /** 动态唯一 ID */
  dynamicId: number = 0;
  /** 动态类型字符串，如 "DYNAMIC_TYPE_NONE"、新格式 "DYNAMIC_TYPE_DRAW"、"DYNAMIC_TYPE_VIDEO" 等 */
  type: string = '';
  /** 关联的评论区 ID */
  comment_id: number = 0;
  /** 评论区类型（评论 API 需要此值） */
  comment_type: number = 0;

  // --- 发布者 ---
  /** 发布者用户信息 */
  userInfo: UserCard = new UserCard();

  // --- 时间 ---
  /** 后端返回的已格式化发布时间 */
  pubTime: string = '';

  // --- 富文本内容（仿 CommentCard 风格） ---
  /**
   * 动态文本内容。
   * 表情以 "[表情名]" 占位，UI 渲染时配合 emoteMap 替换为图片。
   * @提及内容保留原文 "@用户名 "，配合 memberMap 实现点击跳转。
   */
  message: string = '';
  /** 表情名 -> 图片 URL 的映射 */
  emoteMap: Map<string, string> = new Map();
  /** @用户名 -> UserCard 的映射 */
  memberMap: Map<string, UserCard> = new Map();

  // --- Opus 类动态的标题 ---
  /** Opus 图文类动态的标题（非所有动态都有此字段） */
  title: string = '';

  // --- 附加内容（多态主内容） ---
  /**
   * 附加内容类型标识，取值举例：
   *   "MAJOR_TYPE_ARCHIVE"    → VideoCard（视频）
   *   "MAJOR_TYPE_UGC_SEASON" → VideoCard（合集）
   *   "MAJOR_TYPE_PGC"        → VideoCard（番剧/影视）
   *   "MAJOR_TYPE_ARTICLE"    → ArticleCard（专栏）
   *   "MAJOR_TYPE_DRAW"       → string[]（多图，URL 列表）
   *   "MAJOR_TYPE_OPUS"       → Opus（图文混合，pictures + message + title）
   *   "MAJOR_TYPE_COMMON"     → 普通活动（仅文本）
   */
  major_type: string = '';

  /**
   * 附加内容实体。
   * 运行时通过 major_type 判断实际类型后强制转换使用。
   */
  major_object: Object | null = null;

  // --- 图片列表（MAJOR_TYPE_DRAW / OPUS 的图片） ---
  /** 图片 URL 列表 */
  pictures: string[] = [];

  // --- 统计数据 ---
  /** 点赞/评论/转发统计 */
  stats: DynamicStats = new DynamicStats();

  // --- 转发链 ---
  /** 被转发的原动态（递归结构，可能嵌套多层） */
  dynamic_forward: Dynamic | null = null;

  // --- 权限 ---
  /** 当前用户是否有权删除此动态 */
  canDelete: boolean = false;

  // --- 额外标记 ---
  /** 该 UP 主是否有新动态（仅用于最近更新列表） */
  has_update: boolean = false;

  constructor(
    dynamicId?: number,
    type?: string,
    userInfo?: UserCard,
    pubTime?: string,
    message?: string,
    emoteMap?: Map<string, string>,
    memberMap?: Map<string, UserCard>,
    major_type?: string,
    major_object?: Object | null,
    pictures?: string[],
    title?: string,
    stats?: DynamicStats,
    dynamic_forward?: Dynamic | null,
    canDelete?: boolean,
    comment_id?: number,
    comment_type?: number
  ) {
    if (dynamicId !== undefined) this.dynamicId = dynamicId;
    if (type !== undefined) this.type = type;
    if (userInfo !== undefined) this.userInfo = userInfo;
    if (pubTime !== undefined) this.pubTime = pubTime;
    if (message !== undefined) this.message = message;
    if (emoteMap !== undefined) this.emoteMap = emoteMap;
    if (memberMap !== undefined) this.memberMap = memberMap;
    if (major_type !== undefined) this.major_type = major_type;
    if (major_object !== undefined) this.major_object = major_object;
    if (pictures !== undefined) this.pictures = pictures;
    if (title !== undefined) this.title = title;
    if (stats !== undefined) this.stats = stats;
    if (dynamic_forward !== undefined) this.dynamic_forward = dynamic_forward;
    if (canDelete !== undefined) this.canDelete = canDelete;
    if (comment_id !== undefined) this.comment_id = comment_id;
    if (comment_type !== undefined) this.comment_type = comment_type;
  }
}
