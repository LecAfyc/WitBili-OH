/**
 * 单条动态卡片组件
 *
 * 传入 Dynamic + isExpand 布尔值。
 * isExpand=false 时折叠：文字最多4行；
 * isExpand=true  时展开：完整显示。
 *
 * 布局结构：
 *   ┌──────────────────────────────┐
 *   │  UserCardComponent (作者+时间) │
 *   │  ──────────────────────────── │
 *   │  文本内容（含表情/@，可折叠）   │
 *   │  附加内容（视频/专栏/图片等）   │
 *   │  ──────────────────────────── │
 *   │  [转发动态]（如有）           │
 *   │  ──────────────────────────── │
 *   │  点赞  ·  转发  ·  评论       │
 *   └──────────────────────────────┘
 *
 * 点赞状态用独立 @State isLiked / likeCount 而非嵌套 prop，
 * 确保 ArkTS 能正确触发 UI 刷新。
 */

import { Dynamic, DynamicStats } from '../model/Dynamic';
import { UserCard } from '../model/UserCard';
import { VideoCard, ArticleCard } from '../model/ContentCard';
import { UserCardComponent } from './UserCardComponent';
import { VideoCardComponent } from './VideoCardComponent';
import { ArticleCardComponent } from './ArticleCardComponent';
import { likeDynamic } from '../api/DynamicApi';
import { formatCount } from '../api/CommonApi';

// ===== 段类型 =====
enum SegKind { TEXT, EMOJI, MENTION }

interface Seg {
  kind: SegKind;
  text: string;
  emojiUrl?: string;
  emojiSize?: number;
  userId?: number;
}

// ===== 组件 =====
@Component
export struct DynamicCardComponent {
  @Consume('pageStack') pageStack: NavPathStack;

  @Prop dynamic: Dynamic = new Dynamic();
  @Prop isExpand: boolean = false;
  @Prop isForwarded: boolean = false;
  /** 点赞状态（独立 @State 以触发 UI 刷新） */
  @State isLiked: boolean = false;
  @State likeCount: number = 0;

  private readonly fs: number = 13;
  private readonly lh: number = 20;
  private readonly maxLines: number = 4;

  // ----------------------------  富文本解析  ----------------------------

  parseMessage(): Seg[] {
    const text = this.dynamic.message;
    const emojiMap = this.dynamic.emoteMap;
    const memberMap = this.dynamic.memberMap;

    const segs: Seg[] = [];
    let idx: number = 0;

    const re: RegExp = /\[([^\]]+)\]|@([\u4e00-\u9fa5a-zA-Z0-9_-]+)/g;
    let m: RegExpExecArray | null;

    while ((m = re.exec(text)) !== null) {
      if (m.index > idx) {
        segs.push({ kind: SegKind.TEXT, text: text.slice(idx, m.index) });
      }

      if (m[1] !== undefined) {
        // [表情名]
        const val: string | undefined = emojiMap.get(m[1]);  // url||size
        if (val) {
          const sep: number = val.indexOf('||');
          const url: string = sep !== -1 ? val.substring(0, sep) : val;
          const size: number = sep !== -1 ? Number(val.substring(sep + 2)) || 1 : 1;
          segs.push({
            kind: SegKind.EMOJI, text: m[0],
            emojiUrl: url,
            emojiSize: size === 2 ? 28 : 18
          });
        } else {
          segs.push({ kind: SegKind.TEXT, text: m[0] });
        }
      } else {
        // @用户名
        const user: UserCard | undefined = memberMap.get(m[2]);
        if (user) {
          segs.push({ kind: SegKind.MENTION, text: m[0], userId: user.mid });
        } else {
          segs.push({ kind: SegKind.TEXT, text: m[0] });
        }
      }

      idx = m.index + m[0].length;
    }

    if (idx < text.length) {
      segs.push({ kind: SegKind.TEXT, text: text.slice(idx) });
    }

    return this.mergeText(segs);
  }

  /** 合并相邻文本段 */
  mergeText(segs: Seg[]): Seg[] {
    const out: Seg[] = [];
    let buf: string = '';
    for (const s of segs) {
      if (s.kind === SegKind.TEXT) {
        buf += s.text;
      } else {
        if (buf) {
          out.push({ kind: SegKind.TEXT, text: buf });
          buf = '';
        }
        out.push(s);
      }
    }
    if (buf) {
      out.push({ kind: SegKind.TEXT, text: buf });
    }
    return out;
  }

  // ----------------------------  图片缩略图  ----------------------------

  toThumb(url: string): string {
    if (url.indexOf('@') === -1) {
      return url + '@200w';
    }
    return url;
  }

  // ----------------------------  点赞  ----------------------------

  aboutToAppear(): void {
    // 从 @Prop 同步到 @State，确保 UI 能响应变化
    this.isLiked = this.dynamic.stats.liked;
    this.likeCount = this.dynamic.stats.like;
  }

  private async onLikeClick(): Promise<void> {
    if (this.dynamic.dynamicId <= 0) return;

    const prevLiked: boolean = this.isLiked;
    const prevLike: number = this.likeCount;
    const newLiked: boolean = !prevLiked;

    // 先乐观更新 UI（@State 变化触发重绘）
    this.isLiked = newLiked;
    this.likeCount = newLiked ? prevLike + 1 : prevLike - 1;
    this.dynamic.stats.liked = newLiked;
    this.dynamic.stats.like = newLiked ? prevLike + 1 : prevLike - 1;

    // 再调 API
    const result: boolean = await likeDynamic(this.dynamic.dynamicId, newLiked);
    if (!result) {
      // API 失败 -> 撤回
      this.isLiked = prevLiked;
      this.likeCount = prevLike;
      this.toast('操作失败');
    }else this.toast(newLiked ? '已点赞' : '已取消赞');
  }

  private toast(msg: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: msg, duration: 1500 });
    } catch (e) {
      console.warn('[DynamicCard] Toast 异常:', String(e));
    }
  }

  // ----------------------------  构建  ----------------------------

  build() {
    Column() {
      // ===== 转发动态用内嵌标题 =====
      if (this.isForwarded) {
        Text('转发动态')
          .fontSize(11)
          .fontColor('#888888')
          .padding({ left: 12, top: 6, bottom: 0 })
          .alignSelf(ItemAlign.Start)
      }

      // ===== 作者信息 =====
      if (!this.isForwarded) {
        UserCardComponent({
          card: this.dynamic.userInfo,
          extraInfo: this.dynamic.pubTime,
          baseFontSize: 13
        })
      }

      // ===== 标题（Opus 动态） =====
      if (this.dynamic.title) {
        Text(this.dynamic.title)
          .fontSize(15)
          .fontColor('#FFFFFF')
          .fontWeight(FontWeight.Bold)
          .lineHeight(22)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .padding({ left: 12, right: 12, top: 6 })
          .alignSelf(ItemAlign.Start)
      }

      // ===== 正文段（含表情/@，可折叠） =====
      if (this.dynamic.message) {
        Stack() {
          Column() {
            Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Start }) {
              ForEach(this.parseMessage(), (s: Seg) => {
                if (s.kind === SegKind.TEXT) {
                  Text(s.text)
                    .fontSize(this.fs)
                    .lineHeight(this.lh)
                    .textAlign(TextAlign.Start)
                } else if (s.kind === SegKind.EMOJI) {
                  Image(s.emojiUrl!)
                    .width(s.emojiSize ?? 18)
                    .height(s.emojiSize ?? 18)
                    .objectFit(ImageFit.Contain)
                    .margin({ left: 1, right: 1 })
                } else if (s.kind === SegKind.MENTION) {
                  Text(s.text)
                    .fontSize(this.fs)
                    .fontColor('#FB7299')
                    .lineHeight(this.lh)
                    .textAlign(TextAlign.Start)
                    .onClick(() => {
                      console.info('[DynamicCard] mention tap: mid=' + s.userId);
                      this.pageStack.pushPath({
                        name: 'UserDetailPage',
                        param: new UserCard('Loading...', '', s.userId)
                      })
                    })
                }
              })
            }
            .width('100%')
            .padding({ left: 12, right: 12 })
          }
          .width('100%')
          .constraintSize({ maxHeight: this.isExpand ? 9999 : this.maxLines * this.lh })
          .clip(true)

          // 折叠时右下角省略号
          if (!this.isExpand) {
            Text('...')
              .fontSize(this.fs)
              .fontColor('#AAAAAA')
              .position({ bottom: 0, right: 14 })
          }
        }
        .width('100%')
        .padding({ top: 4 })
      }

      // ===== 附加内容（视频/专栏/图片等） =====
      if (this.dynamic.major_type === 'MAJOR_TYPE_ARCHIVE'
        || this.dynamic.major_type === 'MAJOR_TYPE_UGC_SEASON'
        || this.dynamic.major_type === 'MAJOR_TYPE_PGC') {
        // 视频 / 合集 / 番剧
        VideoCardComponent({ card: this.dynamic.major_object as VideoCard })
          .padding({ left: 12, right: 12, top: 6 })
      } else if (this.dynamic.major_type === 'MAJOR_TYPE_ARTICLE') {
        // 专栏
        ArticleCardComponent({ card: this.dynamic.major_object as ArticleCard })
          .padding({ left: 12, right: 12, top: 6 })
      } else if (this.dynamic.major_type === 'MAJOR_TYPE_DRAW'
        || this.dynamic.major_type === 'MAJOR_TYPE_OPUS') {
        // 横向滚动图片（手表屏幕小，Grid 效果差，仿 CommentCard 用 Scroll+Row）
        if (this.dynamic.pictures.length > 0) {
          Scroll() {
            Row() {
              ForEach(this.dynamic.pictures, (url: string) => {
                Image(this.toThumb(url))
                  .width(80)
                  .height(80)
                  .borderRadius(8)
                  .margin({ right: 6 })
                  .objectFit(ImageFit.Cover)
                  .onClick(() => {
                    this.pageStack.pushPath({ name: 'ImageViewer', param: url });
                  })
              })
            }
          }
          .scrollable(ScrollDirection.Horizontal)
          .clip(true)
          .padding({ left: 12, right: 12, top: 6 })
          .focusable(true)
          .focusOnTouch(true)
          .defaultFocus(true)
        }
      }

      // ===== 转发的原动态 =====
      if (this.dynamic.dynamic_forward) {
        DynamicCardComponent({
          dynamic: this.dynamic.dynamic_forward!,
          isExpand: false,
          isForwarded: true
        })
          .padding({ left: 12, right: 12, top: 8 })
          .backgroundColor('#222222')
          .borderRadius(8)
          .margin({ left: 12, right: 12, top: 6 })
          .onClick(() => {
            this.pageStack.pushPath({name: 'DynamicDetailPage', param: this.dynamic.dynamic_forward!})
          })
      }

      // ===== 底部：点赞/统计栏 =====
      Row() {
        // 点赞（使用 @State isLiked / likeCount 以正确触发 UI 刷新）
        Row() {
          SymbolGlyph($r("sys.symbol.hand_thumbsup_fill"))
            .fontSize(16)
            .fontColor([this.isLiked ? '#FB7299' : '#888888'])
            .height(18)
          if (this.likeCount > 0) {
            Text(formatCount(this.likeCount))
              .fontSize(11)
              .fontColor(this.isLiked ? '#FB7299' : '#888888')
              .lineHeight(14)
              .margin({ left: 3 })
          }
        }
        .onClick(() => { this.onLikeClick() })
        .padding({ top: 6, bottom: 6, right: 16 })

        Blank()


        // 评论
        Row() {
          SymbolGlyph($r("sys.symbol.ellipsis_message"))
            .fontSize(14)
            .fontColor(['#888888'])
            .height(18)
          if (this.dynamic.stats.reply > 0) {
            Text(formatCount(this.dynamic.stats.reply))
              .fontSize(11)
              .fontColor('#888888')
              .lineHeight(14)
              .margin({ left: 3 })
          }
        }
        .padding({ top: 6, bottom: 6 })
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 4, bottom: 2 })
    }
    .width('100%')
    .backgroundColor(this.isForwarded ? '#222222' : '#1A1A1A')
    .borderRadius(12)
    .margin({ bottom: this.isForwarded ? 0 : 8 })
  }
}
