/**
 * 专栏正文段落数据模型
 *
 * 对应 B 站专栏/Opus 的正文段落。
 * 每个 paragraph 包含段落类型和具体内容：
 *   — TYPE_TEXT            (1):  纯文本段落，content 为 string
 *   — TYPE_PIC             (2):  图片段落，content 为 string[]（图片 URL 列表）
 *   — TYPE_DIVIDER         (3):  分割线段落，content 为 string[]（分割线图片 URL）
 *   — TYPE_TEXT_BLOCKQUOTE (4):  引用块段落，content 为 string（带引用样式）
 *   — TYPE_LIST            (5):  列表段落，content 为 string（带序号/圆点）
 *   — TYPE_HEADING         (8):  标题段落，content 为 string
 *   — TYPE_TEXT_OPUS       (99): Opus 富文本段落，content 为 string（含 @/表情/话题）
 *   — TYPE_VIDEO           (100): 视频卡片段落，content 为 ArticleCard | VideoCard
 *   — TYPE_ARTICLE         (102): 关联文章卡片段落，content 为 ArticleCard
 *
 * UI 渲染时根据 type 选取对应的布局和样式。content 泛型统一用 Object，
 * 运行时根据 type 转换。
 */

import { ArticleCard, VideoCard } from './ContentCard';

/**
 * 段落类型常量
 */
export class ParagraphType {
  /** 纯文本段落 */
  static readonly TEXT: number = 1;
  /** 图片段落（可多张） */
  static readonly PIC: number = 2;
  /** 分割线 */
  static readonly DIVIDER: number = 3;
  /** 引用块 */
  static readonly TEXT_BLOCKQUOTE: number = 4;
  /** 列表（有序/无序） */
  static readonly LIST: number = 5;
  /** 标题 */
  static readonly HEADING: number = 8;
  /** Opus 富文本（含 @/表情/话题链接） */
  static readonly TEXT_OPUS: number = 99;
  /** 视频卡片 */
  static readonly VIDEO: number = 100;
  /** 关联文章卡片 */
  static readonly ARTICLE: number = 102;
}

/**
 * 列表样式常量
 */
export class ListStyle {
  /** 有序列表（1. / 2. / 3.） */
  static readonly NUMBER: number = 1;
  /** 无序列表（·） */
  static readonly DOT: number = 2;
}

/**
 * 正文段落
 *
 * content 为 Object 类型，使用时根据 type 转换：
 *   type=1/4/5/8/99 → content 为 string（文本/富文本）
 *   type=2/3        → content 为 string[]（图片 URL 列表）
 *   type=100        → content 为 VideoCard
 *   type=102        → content 为 ArticleCard
 */
export class ArticleParagraph {
  /** 段落类型（见 ParagraphType 常量） */
  type: number = ParagraphType.TEXT;
  /** 段落对齐方式（0=默认左对齐，1=居中，2=右对齐） */
  align: number = 0;
  /**
   * 段落内容。
   * - 文本类段落为 string（纯文本或简单 HTML 格式标记）
   * - 图片类段落为 string[]（图片 URL）
   * - 卡片类段落为 VideoCard / ArticleCard
   */
  content: Object = '';

  constructor(type?: number, align?: number, content?: Object) {
    if (type !== undefined) this.type = type;
    if (align !== undefined) this.align = align;
    if (content !== undefined) this.content = content;
  }

  /** 获取文本内容（适用于文本类段落） */
  getText(): string {
    if (typeof this.content === 'string') {
      return this.content as string;
    }
    return '';
  }

  /** 获取图片 URL 列表（适用于图片/分割线段落） */
  getPictures(): string[] {
    if (Array.isArray(this.content)) {
      return this.content as string[];
    }
    return [];
  }

  /** 判断是否为文本类段落 */
  isTextual(): boolean {
    return this.type === ParagraphType.TEXT
      || this.type === ParagraphType.TEXT_BLOCKQUOTE
      || this.type === ParagraphType.LIST
      || this.type === ParagraphType.HEADING
      || this.type === ParagraphType.TEXT_OPUS;
  }

  /** 判断是否为图片段落 */
  isImage(): boolean {
    return this.type === ParagraphType.PIC || this.type === ParagraphType.DIVIDER;
  }
}
