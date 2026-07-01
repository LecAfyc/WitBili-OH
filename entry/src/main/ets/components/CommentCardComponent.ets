/**
 * 单条评论卡片组件
 *
 * 传入 SingleComment + isExpand 布尔值。
 * isExpand=false 时折叠：正文最多5行、显示精选回复；
 * isExpand=true  时展开：正文完整显示、不显示回复。
 */

import { SingleComment } from '../model/CommentCard';
import { UserCardComponent } from './UserCardComponent';
import { likeComment, hateComment } from '../api/CommentApi';
import { formatCount } from '../api/CommonApi';
import { UserCard } from '../model/UserCard';


// ===== 段类型 =====
enum SegKind { TEXT, EMOJI, MENTION }

interface Seg {
  kind: SegKind;
  text: string;        // 段原文（text 时为纯文字，emoji/mention 时为 [xxx] / @xxx）
  emojiUrl?: string;   // SegKind.EMOJI 时有效
  emojiSize?: number;  // SegKind.EMOJI 时有效：18=小 25=大
  userId?: number;     // SegKind.MENTION 时有效
}

// ===== 组件 =====
@Component
export struct CommentCardComponent {
  @Consume('pageStack') pageStack: NavPathStack;

  @Prop comment: SingleComment = new SingleComment();
  @Prop isExpand: boolean = false;
  @Prop showReplies: boolean = true;
  fs = 12;
  lh = 18;
  emojiSize = 18;
  bigEmojiSize = 25;
  picSize = 55;
  maxLines = 5;
  // ----------------------------  解析  ----------------------------

  parseMessage(): Seg[] {
    const text = this.comment.message;
    const emojiMap = this.comment.emoteMap;
    const memberMap = this.comment.memberMap;

    const segs: Seg[] = [];
    let idx = 0;

    // 同时匹配 [表情名] 和 @用户名（只匹配合法用户名中的字符，避免吞掉中文标点）
    const re = /\[([^\]]+)\]|@([\u4e00-\u9fa5a-zA-Z0-9_-]+)/g;
    let m: RegExpExecArray | null;

    while ((m = re.exec(text)) !== null) {
      // 匹配前的纯文本
      if (m.index > idx) {
        segs.push({ kind: SegKind.TEXT, text: text.slice(idx, m.index) });
      }

      if (m[1] !== undefined) {
        // [表情名]
        const val = emojiMap.get(m[1]);  // url||size
        console.info('[CommentCard] emoji lookup: name="' + m[1] + '" found=' + (val ? 'yes' : 'no'));
        if (val) {
          const sep = val.indexOf('||');
          const url = sep !== -1 ? val.substring(0, sep) : val;
          const size = sep !== -1 ? Number(val.substring(sep + 2)) || 1 : 1;
          segs.push({
            kind: SegKind.EMOJI, text: m[0],
            emojiUrl: url,
            emojiSize: size === 2 ? 35 : 18
          });
        } else {
          segs.push({ kind: SegKind.TEXT, text: m[0] });
        }   // 未定义 → 当文本
      } else {
        // @用户名
        const user = memberMap.get(m[2]);
        segs.push(user
          ? { kind: SegKind.MENTION, text: m[0], userId: user.mid }
          : { kind: SegKind.TEXT, text: m[0] });   // 不在列表 → 当文本
      }

      idx = m.index + m[0].length;
    }

    // 尾部剩余文本
    if (idx < text.length) {
      segs.push({ kind: SegKind.TEXT, text: text.slice(idx) });
    }

    return this.mergeText(segs);
  }

  /** 合并相邻文本段，避免 Flex 把一个句子拆成多个原子块 */
  mergeText(segs: Seg[]): Seg[] {
    const out: Seg[] = [];
    let buf = '';
    for (const s of segs) {
      if (s.kind === SegKind.TEXT) {
        buf += s.text;
      } else {
        if (buf) { out.push({ kind: SegKind.TEXT, text: buf }); buf = ''; }
        out.push(s);
      }
    }
    if (buf) out.push({ kind: SegKind.TEXT, text: buf });
    return out;
  }

  // ===== 点赞/点踩乐观更新 =====
  private async onLikeClick(): Promise<void> {
    if (this.comment.oid <= 0 || this.comment.rpid <= 0) {
      this.toast('评论信息不完整');
      return;
    }

    let prevAction: number = this.comment.action;
    let prevLikes: number = this.comment.likes;

    // 乐观更新
    if (this.comment.action === 1) {
      // 已点赞 → 取消赞
      this.comment.action = 0;
      this.comment.likes -= 1;
    } else {
      // 未点赞 → 点赞（同时消去点踩）
      if (this.comment.action === 2) {
        this.comment.action = 0;  // 先清零，后面设为点赞
      }
      this.comment.action = 1;
      this.comment.likes += 1;
    }

    let apiAction: number = this.comment.action === 1 ? 1 : 0;
    let result = await likeComment(1, this.comment.oid, this.comment.rpid, apiAction);
    if (result.success) {
      this.toast(result.message);
    } else {
      // 回滚
      this.comment.action = prevAction;
      this.comment.likes = prevLikes;
      this.toast(result.message);
    }
  }

  private async onHateClick(): Promise<void> {
    if (this.comment.oid <= 0 || this.comment.rpid <= 0) {
      this.toast('评论信息不完整');
      return;
    }

    let prevAction: number = this.comment.action;
    let prevLikes: number = this.comment.likes;

    // 乐观更新
    if (this.comment.action === 2) {
      // 已点踩 → 取消踩
      this.comment.action = 0;
    } else {
      // 未点踩 → 点踩（同时消去点赞）
      if (this.comment.action === 1) {
        this.comment.action = 0;
        this.comment.likes -= 1;
      }
      this.comment.action = 2;
    }

    let apiAction: number = this.comment.action === 2 ? 1 : 0;
    let result = await hateComment(1, this.comment.oid, this.comment.rpid, apiAction);
    if (result.success) {
      this.toast(result.message);
    } else {
      // 回滚
      this.comment.action = prevAction;
      this.comment.likes = prevLikes;
      this.toast(result.message);
    }
  }

  private toast(msg: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: msg, duration: 1500 });
    } catch (e) {
      console.warn('[CommentCard] Toast 失败:', String(e));
    }
  }

  // ----------------------------  数字格式化  ----------------------------

  /** BFS 图片 URL 追加 @100w 获取缩略图 */
  toThumb(url: string): string {
    if (url.indexOf('@') === -1) {
      return url + '@100w';
    }
    return url;
  }

  // ----------------------------  构建  ----------------------------

  build() {
    Column() {
      // ── 发送者信息 ──
      UserCardComponent({
        card: this.comment.sender,
        extraInfo: this.comment.time_desc + ' ' + this.comment.ip_desc,
        baseFontSize:  11
      })

      // ── 置顶标识 ──
      if (this.comment.isOnTop) {
        Text('置顶')
          .fontSize(10)
          .fontColor('#FB7299')
          .backgroundColor('#332211')
          .borderRadius(4)
          .padding({ left: 5, right: 5, top: 1, bottom: 1 })
          .margin({ left: 12, top: 4 })
      }

      // ── 正文段（含表情/@）──
      // 用 Column + constraintSize + clip 实现 5 行截断
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
                  .width(s.emojiSize || this.emojiSize)
                  .height(s.emojiSize || this.emojiSize)
                  .objectFit(ImageFit.Contain)
                  .margin({ left: 1, right: 1 })

              } else if (s.kind === SegKind.MENTION) {
                Text(s.text)
                  .fontSize(this.fs)
                  .fontColor('#FB7299')
                  .lineHeight(this.lh)
                  .textAlign(TextAlign.Start)
                  .onClick(() => {
                    console.info('[CommentCard] mention tap: mid=' + s.userId);
                    this.pageStack.pushPath({name: "UserDetailPage", param: new UserCard("Loading...","",s.userId)})
                  })
              }
            })
          }
          .width('100%')
          .padding({ left: 12, right: 12 })
        }
        .width('100%')
        .constraintSize({
          maxHeight: this.isExpand ? 9999 : this.maxLines * this.lh
        })
        .clip(true)

        // 折叠时右下角加省略号
        if (!this.isExpand) {
          Text('...')
            .fontSize(this.fs)
            .fontColor('#AAAAAA')
            .position({ bottom: 0, right: 14 })
        }
      }
      .width('100%')

      // ── 评论区图片（横向滚动） ──
      if (this.comment.pictures.length > 0) {
        Scroll() {
          Row() {
            ForEach(this.comment.pictures, (origUrl: string) => {
              // 显示用缩略图，点击用原图
              Image(this.toThumb(origUrl))
                .width(this.picSize)
                .height(this.picSize)
                .borderRadius(8)
                .margin({ right: 6 })
                .objectFit(ImageFit.Cover)
                .onClick(() => {
                  this.pageStack.pushPath({name: 'ImageViewer', param: origUrl});
                })
            })
          }
        }
        .scrollable(ScrollDirection.Horizontal)
        .clip(true)
        .padding({ left: 12, right: 12, top: 8 })
        .focusable(true)
        .focusOnTouch(true)
        .defaultFocus(true)
      }

      // ── 点赞 / 点踩 ──
      Row() {
        // 点赞
        Column() {
          SymbolGlyph($r("sys.symbol.hand_thumbsup_fill"))
            .fontSize(14)
            .fontColor([this.comment.action === 1 ? '#FB7299' : '#888888'])
          if (this.comment.likes > 0) {
            Text(formatCount(this.comment.likes))
              .fontSize(10)
              .fontColor(this.comment.action === 1 ? '#FB7299' : '#888888')
              .lineHeight(12)
          }
        }
        .onClick(() => { this.onLikeClick(); })
        .padding(4)

        Blank()

        // 点踩（后端不返回点踩数，只保留按钮）
        SymbolGlyph($r("sys.symbol.xmark_circle"))
          .fontSize(14)
          .fontColor([this.comment.action === 2 ? '#FB7299' : '#888888'])
          .onClick(() => { this.onHateClick(); })
          .padding(4)
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 6, bottom: 2 })

      // ── 精选回复（仅折叠态，且 showReplies 为 true）──
      if (!this.isExpand && this.showReplies && this.comment.hotReply.length > 0) {
        Column() {
          // 每条精选回复最多 1 行
          ForEach(this.comment.hotReply, (replyText: string) => {
            Text(replyText)
              .fontSize(11)
              .lineHeight(16)
              .fontColor('#AAAAAA')
              .maxLines(1)
              .margin({ top: 4 })
          })

          // 回复数
          if (this.comment.replys > 0) {
            Text(formatCount(this.comment.replys) + '条回复 ›')
              .fontSize(11)
              .fontColor('#FB7299')
              .margin({ top: 4 })
          }
        }
        .padding({ left: 12, right: 12, top: 4 })
        .margin({ bottom: 6 })
      }
    }
    .width('100%')
    .backgroundColor('#1A1A1A')
    .borderRadius(12)
    .margin({ bottom: 8 })
  }
}
