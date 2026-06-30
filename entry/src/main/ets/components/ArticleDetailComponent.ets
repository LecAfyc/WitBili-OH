/**
 * 专栏详情组件
 *
 * 传入 ArticleCard（含 cvid），组件内部调用 API 拉取完整数据后渲染。
 *
 * 最纯粹的shit山之一
 * 这可能是除了视频播放页面以外的最石的代码
 *
 */

import { ArticleCard, VideoCard } from '../model/ContentCard';
import { ArticleInfo, ArticleStats } from '../model/ArticleInfo';
import { ArticleParagraph, ParagraphType } from '../model/ArticleParagraph';
import { Opus } from '../model/Opus';
import { UserCard } from '../model/UserCard';
import { UserCardComponent } from './UserCardComponent';
import { VideoCardComponent } from './VideoCardComponent';
import { ArticleCardComponent } from './ArticleCardComponent';
import { getOpus, getArticle, likeArticle, addCoin, favoriteArticle, delFavoriteArticle } from '../api/ArticleApi';
import { formatCount } from '../api/CommonApi';

// ===== 富文本段落中的段类型 =====
enum RichSegKind { TEXT, EMOJI, MENTION, LINK }

interface RichSeg {
  kind: RichSegKind;
  text: string;
  emojiUrl?: string;
  emojiSize?: number;
  userId?: number;
}

@Component
export struct ArticleDetailComponent {
  @Consume('pageStack') pageStack: NavPathStack;

  // ===== 对外属性 =====
  @Prop card: ArticleCard = new ArticleCard();

  // ===== 内部状态 =====
  @State article: ArticleInfo | null = null;
  @State opus: Opus | null = null;
  @State isLoading: boolean = true;
  @State loadError: string = '';

  // 交互状态
  @State isLiked: boolean = false;
  @State likeCount: number = 0;
  @State coinCount: number = 0;
  @State coinsGiven: number = 0;
  @State isFavoured: boolean = false;
  @State favCount: number = 0;

  private readonly fs: number = 14;
  private readonly lh: number = 22;

  // ===== 生命周期：加载数据 =====
  aboutToAppear(): void {
    this.loadArticle();
  }

  toThumb(url: string): string {
    if (url.indexOf('@') === -1) {
      return url + '@100w';
    }
    return url;
  }

  private async loadArticle(): Promise<void> {
    const cvid: number = this.card.cvid;
    if (!cvid || cvid <= 0) {
      this.loadError = '专栏 ID 无效';
      this.isLoading = false;
      return;
    }
    this.isLoading = true;
    this.loadError = '';
    try {
      const opusResult: Opus | null = await getOpus(cvid);
      if (opusResult && opusResult.paragraphs && opusResult.paragraphs.length > 0) {
        this.opus = opusResult;
        this.syncStats(opusResult.stats);
        // 日志：段落和图片统计
        let imgParaCount2: number = 0;
        for (let pi2: number = 0; pi2 < opusResult.paragraphs.length; pi2++) {
          const pp: ArticleParagraph = opusResult.paragraphs[pi2];
          if (pp.isImage()) {
            const pics: string[] = pp.getPictures();
            console.info('[ArticleDetail] 段落[' + pi2 + '] 图片=' + (pics.length > 0 ? pics[0].substring(0, 60) : '空') + ' 共' + pics.length + '张');
            imgParaCount2++;
          }
        }
        console.info('[ArticleDetail] Opus 总段数=' + opusResult.paragraphs.length + ' 图片段落=' + imgParaCount2);
        this.isLoading = false;
        return;
      }
      const articleResult: ArticleInfo | null = await getArticle(cvid);
      if (articleResult) {
        this.article = articleResult;
        this.syncStats(articleResult.stats);
        this.isLoading = false;
        return;
      }
      this.loadError = '无法加载专栏内容';
      this.isLoading = false;
    } catch (e) {
      console.error('[ArticleDetail] 加载失败:', String(e));
      this.loadError = '加载失败: ' + String(e);
      this.isLoading = false;
    }
  }

  private syncStats(stats: ArticleStats): void {
    this.likeCount = stats.like;
    this.coinCount = stats.coin;
    this.coinsGiven = stats.coined;
    this.isLiked = stats.liked;
    this.isFavoured = stats.favoured;
    this.favCount = stats.favorite;
  }

  // ===== 数据 getter =====
  private getTitle(): string {
    if (this.opus) return this.opus.title;
    if (this.article) return this.article.title;
    return this.card.title;
  }

  private getCover(): string {
    if (this.opus && this.opus.topImages && this.opus.topImages.length > 0) return this.opus.topImages[0];
    if (this.opus && this.opus.cover) return this.opus.cover;
    if (this.article && this.article.banner) return this.article.banner;
    if (this.card.covers && this.card.covers.length > 0) return this.card.covers[0];
    return '';
  }

  private getUpInfo(): UserCard {
    if (this.opus && this.opus.upInfo) return this.opus.upInfo;
    if (this.article && this.article.upInfo) return this.article.upInfo;
    return new UserCard(this.card.upName, '', 0);
  }

  private getPubTime(): string {
    if (this.opus && this.opus.pubTime) return this.opus.pubTime;
    if (this.article && this.article.ctime > 0) {
      const d: Date = new Date(this.article.ctime * 1000);
      const y: number = d.getFullYear();
      const mo: string = String(d.getMonth() + 1).padStart(2, '0');
      const dd: string = String(d.getDate()).padStart(2, '0');
      const h: string = String(d.getHours()).padStart(2, '0');
      const mi: string = String(d.getMinutes()).padStart(2, '0');
      return `${y}/${mo}/${dd} ${h}:${mi}`;
    }
    return '';
  }

  private getParagraphs(): ArticleParagraph[] {
    if (this.opus && this.opus.paragraphs) return this.opus.paragraphs;
    if (this.article && this.article.paragraphs) return this.article.paragraphs;
    return [];
  }

  private getOpusEmoteMap(): Map<string, string> {
    return this.opus ? this.opus.emoteMap : new Map();
  }

  private getOpusMemberMap(): Map<string, UserCard> {
    return this.opus ? this.opus.memberMap : new Map();
  }

  private rawContent(): string {
    return this.article ? this.article.rawContent : '';
  }

  private wordCount(): number {
    return this.article ? this.article.wordCount : 0;
  }

  private hasSummary(): boolean {
    return !!(this.article && this.article.summary);
  }

  private getSummary(): string {
    return this.article ? this.article.summary : '';
  }

  // ===== 富文本解析（用于 TYPE_TEXT_OPUS 段落） =====

  private parseRichText(text: string): RichSeg[] {
    if (!text) return [];
    const emoteMap: Map<string, string> = this.getOpusEmoteMap();
    const memberMap: Map<string, UserCard> = this.getOpusMemberMap();
    const segs: RichSeg[] = [];
    let idx: number = 0;
    const re: RegExp = /\[([^\]]+)\]|@([\u4e00-\u9fa5a-zA-Z0-9_-]+)/g;
    let m: RegExpExecArray | null;
    while ((m = re.exec(text)) !== null) {
      if (m.index > idx) {
        segs.push({ kind: RichSegKind.TEXT, text: text.slice(idx, m.index) });
      }
      if (m[1] !== undefined) {
        const val: string | undefined = emoteMap.get(m[1]);
        if (val) {
          const sep: number = val.indexOf('||');
          const url: string = sep !== -1 ? val.substring(0, sep) : val;
          const size: number = sep !== -1 ? Number(val.substring(sep + 2)) || 1 : 1;
          segs.push({ kind: RichSegKind.EMOJI, text: m[0], emojiUrl: url, emojiSize: size === 2 ? 28 : 18 });
        } else {
          segs.push({ kind: RichSegKind.TEXT, text: m[0] });
        }
      } else {
        const userName: string = m[2];
        const user: UserCard | undefined = memberMap.get(userName);
        segs.push({ kind: RichSegKind.MENTION, text: m[0], userId: user ? user.mid : 0 });
      }
      idx = m.index + m[0].length;
    }
    if (idx < text.length) {
      segs.push({ kind: RichSegKind.TEXT, text: text.slice(idx) });
    }
    return this.mergeRichText(segs);
  }

  private mergeRichText(segs: RichSeg[]): RichSeg[] {
    const out: RichSeg[] = [];
    let buf: string = '';
    for (const s of segs) {
      if (s.kind === RichSegKind.TEXT) {
        buf += s.text;
      } else {
        if (buf) { out.push({ kind: RichSegKind.TEXT, text: buf }); buf = ''; }
        out.push(s);
      }
    }
    if (buf) { out.push({ kind: RichSegKind.TEXT, text: buf }); }
    return out;
  }

  // ===== Toast =====
  private toast(msg: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: msg, duration: 1500 });
    } catch (e) {
      console.warn('[ArticleDetail] Toast 异常:', String(e));
    }
  }

  // ===== 交互操作（乐观更新） =====
  private async onLikeClick(): Promise<void> {
    const cvid: number = this.card.cvid;
    if (!cvid || cvid <= 0) return;
    const prevLiked: boolean = this.isLiked;
    const prevLike: number = this.likeCount;
    this.isLiked = !prevLiked;
    this.likeCount = this.isLiked ? prevLike + 1 : prevLike - 1;
    const result: boolean = await likeArticle(cvid, this.isLiked);
    if (!result) { this.isLiked = prevLiked; this.likeCount = prevLike; this.toast('操作失败'); }
    else { this.toast(this.isLiked ? '已点赞' : '已取消赞'); }
  }

  private async onCoinClick(): Promise<void> {
    const cvid: number = this.card.cvid;
    if (!cvid || cvid <= 0) return;
    if (this.coinsGiven >= 2) { this.toast('投币数量到达上限'); return; }
    const upid: number = this.getUpInfo().mid;
    if (!upid || upid <= 0) { this.toast('UP 主信息不完整'); return; }
    const prevCoin: number = this.coinsGiven;
    const prevCoinTotal: number = this.coinCount;
    this.coinsGiven++;
    this.coinCount++;
    const result: number = await addCoin(cvid, upid, 1);
    if (result === 0) { this.toast('投币成功！'); }
    else {
      this.coinsGiven = prevCoin;
      this.coinCount = prevCoinTotal;
      if (result === 34002) this.toast('不能给自己投币哦！');
      else this.toast('投币失败：' + result);
    }
  }

  private async onFavClick(): Promise<void> {
    const cvid: number = this.card.cvid;
    if (!cvid || cvid <= 0) return;
    const prevFavoured: boolean = this.isFavoured;
    const prevFavCount: number = this.favCount;
    this.isFavoured = !prevFavoured;
    this.favCount = this.isFavoured ? prevFavCount + 1 : prevFavCount - 1;
    let result: boolean;
    if (this.isFavoured) result = await favoriteArticle(cvid);
    else result = await delFavoriteArticle(cvid);
    if (result) { this.toast('操作成功~'); }
    else { this.isFavoured = prevFavoured; this.favCount = prevFavCount; this.toast('操作失败'); }
  }

  // ===== cover 多图角标 =====
  private topImageCount(): number {
    return this.opus && this.opus.topImages ? this.opus.topImages.length : 0;
  }

  // =================================================================
  //  @Builder 方法（ArkTS：build() 内只能放组件，条件逻辑必须拆到 @Builder）
  // =================================================================

  /** 加载中 */
  @Builder
  loadingView() {
    ListItem() {
      Column() {
        LoadingProgress().width(36).height(36)
        Text('加载中...').fontSize(13).fontColor('#888888').margin({ top: 8 })
      }
      .width('92%').alignItems(HorizontalAlign.Center).justifyContent(FlexAlign.Center)
      .padding({ top: 60, bottom: 60 })
    }
  }

  /** 加载失败 */
  @Builder
  errorView() {
    ListItem() {
      Column() {
        Text('󰈬').fontSize(40).fontColor('#888888')
        Text(this.loadError).fontSize(13).fontColor('#888888').margin({ top: 8 })
        Text('点击重试').fontSize(12).fontColor('#FB7299').margin({ top: 12 })
          .onClick(() => { this.loadArticle(); })
      }
      .width('92%').alignItems(HorizontalAlign.Center).justifyContent(FlexAlign.Center)
      .padding({ top: 60, bottom: 60 })
    }
  }

  /** 封面大图 */
  @Builder
  coverImage() {
    if (this.getCover()) {
      ListItem() {
        Column() {
          Image(this.getCover() + "@561w_321h")
            .width('100%').aspectRatio(16 / 9).borderRadius(12)
            .objectFit(ImageFit.Cover).alt($r('app.media.article_placeholder'))
            .onClick(() => { this.pageStack.pushPath({ name: 'ImageViewer', param: this.getCover() }); })
          if (this.topImageCount() > 1) {
            Row() {
              Text('󰋪').fontSize(10).fontColor('#FFFFFF')
              Text('共' + this.topImageCount() + '张图片').fontSize(10).fontColor('#FFFFFF').margin({ left: 3 })
            }
            .backgroundColor('#B0000000').padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .borderRadius(4).position({ bottom: 8, right: 8 })
          }
        }
        .width('92%').align(Alignment.TopStart)
      }
    }
  }

  /** 标题 */
  @Builder
  titleText() {
    ListItem() {
      Text(this.getTitle())
        .fontSize(18).fontColor('#FFFFFF').fontWeight(FontWeight.Bold)
        .lineHeight(26).width('92%').textAlign(TextAlign.Start)
    }
  }

  /** 摘要 */
  @Builder
  summaryText() {
    if (this.hasSummary()) {
      ListItem() {
        Text(this.getSummary())
          .fontSize(13).fontColor('#999999').lineHeight(18)
          .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('92%').textAlign(TextAlign.Start)
      }
    }
  }

  /** UP 主卡片 */
  @Builder
  upInfoCard() {
    ListItem() {
      UserCardComponent({ card: this.getUpInfo(), extraInfo: this.getPubTime(), baseFontSize: 14 }).width('92%')
    }
  }

  /** 分割线 */
  @Builder
  sectionDivider() {
    ListItem() {
      Divider().width('92%').height(0.5).color('#333333')
    }
  }

  /** 富文本段落（TYPE_TEXT_OPUS） */
  @Builder
  richTextParagraph(text: string) {
    Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Start }) {
      ForEach(this.parseRichText(text), (s: RichSeg) => {
        if (s.kind === RichSegKind.TEXT) {
          Text(s.text).fontSize(this.fs).fontColor('#CCCCCC').lineHeight(this.lh).textAlign(TextAlign.Start)
        } else if (s.kind === RichSegKind.EMOJI) {
          Image(s.emojiUrl!).width(s.emojiSize ?? 18).height(s.emojiSize ?? 18)
            .objectFit(ImageFit.Contain).margin({ left: 1, right: 1 })
        } else if (s.kind === RichSegKind.MENTION) {
          Text(s.text).fontSize(this.fs).fontColor('#FB7299').lineHeight(this.lh).textAlign(TextAlign.Start)
            .onClick(() => {
              if (s.userId && s.userId > 0) {
                this.pageStack.pushPath({ name: 'UserDetailPage', param: new UserCard('Loading...', '', s.userId) });
              }
            })
        }
      })
    }
    .width('100%')
  }

  /** 普通文本段落（TEXT / HEADING / BLOCKQUOTE / LIST） */
  @Builder
  textParagraph(para: ArticleParagraph) {
    Text(para.getText())
      .fontSize(para.type === ParagraphType.HEADING ? 17 : this.fs)
      .fontColor(para.type === ParagraphType.HEADING ? '#FFFFFF'
        : (para.type === ParagraphType.TEXT_BLOCKQUOTE ? '#AAAAAA' : '#CCCCCC'))
      .fontWeight(para.type === ParagraphType.HEADING ? FontWeight.Bold : FontWeight.Normal)
      .lineHeight(para.type === ParagraphType.HEADING ? 26 : this.lh)
      .textAlign(TextAlign.Start).width('100%')
       //我也不知道哪来的bug，反正直接让textParagraph不渲染下面的图片也跟着就没了，最后只能把maxHeight设为0来实现不渲染的效果
      .visibility(para.getText() ? Visibility.Visible : Visibility.None)
      .constraintSize({maxHeight: para.getText() ? 9999 : 0})
  }

  /** 图片段落（PIC / DIVIDER） */
  @Builder
  imageParagraph(para: ArticleParagraph) {
    Column() {
      Image(para.getPictures()[0] + "@374w_214h")
        .width('100%').aspectRatio(16 / 9).borderRadius(8)
        .objectFit(ImageFit.Auto).alt($r('app.media.placeholder'))
        .onClick(() => {
          const pics: string[] = para.getPictures();
          if (pics.length === 1) { this.pageStack.pushPath({ name: 'ImageViewer', param: pics[0] }); }
          else { this.pageStack.pushPath({ name: 'ImageViewer', param: pics }); }
        })
      if (para.getPictures().length > 1) {
        Row() {
          Text('󱇯').fontSize(10).fontColor('#FFFFFF')
          Text('共' + para.getPictures().length + '张图片').fontSize(10).fontColor('#FFFFFF').margin({ left: 3 })
        }
        .backgroundColor('#B0000000').padding({ left: 6, right: 6, top: 2, bottom: 2 })
        .borderRadius(4).position({ bottom: 8, right: 8 })
      }
    }
    .width('92%').align(Alignment.TopStart)
  }

  /** 单段落分派 */
  @Builder
  paragraphItem(para: ArticleParagraph, specialContent?: Record<string, Object>) {
    ListItem() {
      if (para.isTextual()) {
        if (para.type === ParagraphType.TEXT_OPUS) {
          this.richTextParagraph(para.getText())
        } else {
          this.textParagraph(para)
        }
      } else if (para.isImage()) {
        this.imageParagraph(para)
      } else if (para.type === ParagraphType.VIDEO) {
        // 视频卡片：content 为 VideoCard 对象
        if (para.content instanceof VideoCard) {
          VideoCardComponent({ card: para.content as VideoCard }).width('92%')
        } else if (typeof para.content === 'object' && specialContent) {
          // 兜底：尝试将 object 转为 VideoCard
          VideoCardComponent({
            card: new VideoCard(
              (specialContent['title'] as string) ?? '',
              (specialContent['upName'] as string) ?? (specialContent['owner_name'] as string) ?? '',
              '',
              (specialContent['cover'] as string) ?? (specialContent['pic'] as string) ?? '',
              Number(specialContent['aid'] ?? 0),
              (specialContent['bvid'] as string) ?? ''
            )
          }).width('92%')
        } else {
          Text('[视频卡片]').fontSize(13).fontColor('#FB7299').width('100%').textAlign(TextAlign.Center)
        }
      } else if (para.type === ParagraphType.ARTICLE) {
        // 关联专栏卡片：content 为 ArticleCard 对象
        if (para.content instanceof ArticleCard) {
          ArticleCardComponent({ card: para.content as ArticleCard }).width('92%')
        } else if (typeof para.content === 'object' && specialContent) {
          ArticleCardComponent({
            card: new ArticleCard(
              (specialContent['title'] as string) ?? '',
              (specialContent['upName'] as string) ?? '',
              '',
              (specialContent['covers'] as string[]) ?? [],
              Number(specialContent['cvid'] ?? specialContent['id'] ?? 0)
            )
          }).width('92%')
        } else {
          Text('[关联专栏]').fontSize(13).fontColor('#FB7299').width('100%').textAlign(TextAlign.Center)
        }
      }
    }
  }

  /** 正文段落列表 */
  @Builder
  paragraphList() {
    if (this.getParagraphs().length > 0) {
      ForEach(this.getParagraphs(), (para: ArticleParagraph, index: number) => {
        this.paragraphItem(para, para.content as Record<string, object>)
      }, (para: ArticleParagraph, index: number) => String(index))
    } else if (this.rawContent()) {
      ListItem() {
        Text(this.stripHtml(this.rawContent()))
          .fontSize(this.fs).fontColor('#CCCCCC').lineHeight(this.lh)
          .textAlign(TextAlign.Start).width('92%')
      }
    }
  }

  /** 交互栏 */
  @Builder
  actionBar() {
    ListItem() {
      Column() {
        Divider().width('100%').height(0.5).color('#333333').margin({ bottom: 12 })
        Row() {
          Column() {
            SymbolGlyph($r("sys.symbol.hand_thumbsup_fill"))
              .fontSize(28)
              .fontColor([this.isLiked ? '#FB7299' : '#BBBBBB'])
            Text(formatCount(this.likeCount)).fontSize(11)
              .fontColor(this.isLiked ? '#FB7299' : '#999999').margin({ top: 3 })
          }
          .layoutWeight(1).alignItems(HorizontalAlign.Center)
          .onClick(() => { this.onLikeClick(); })

          Column() {
            SymbolGlyph($r("sys.symbol.smallcircle_filled_circle"))
              .fontSize(28)
              .fontColor([this.coinsGiven > 0 ? '#FB7299' : '#BBBBBB'])
            Text(formatCount(this.coinCount)).fontSize(11)
              .fontColor(this.coinsGiven > 0 ? '#FB7299' : '#999999').margin({ top: 3 })
            Row() {
              Circle().width(5).height(5).fill(this.coinsGiven >= 1 ? '#FB7299' : '#555555').margin({ right: 3 })
              Circle().width(5).height(5).fill(this.coinsGiven >= 2 ? '#FB7299' : '#555555')
            }.margin({ top: 2 }).justifyContent(FlexAlign.Center)
          }
          .layoutWeight(1).alignItems(HorizontalAlign.Center)
          .onClick(() => { this.onCoinClick(); })

          Column() {
            SymbolGlyph($r("sys.symbol.star"))
              .fontSize(28)
              .fontColor([this.isFavoured ? '#FB7299' : '#BBBBBB'])
            Text(formatCount(this.favCount)).fontSize(11)
              .fontColor(this.isFavoured ? '#FB7299' : '#999999').margin({ top: 3 })
          }
          .layoutWeight(1).alignItems(HorizontalAlign.Center)
          .onClick(() => { this.onFavClick(); })
        }
        .width('100%').padding({ top: 8, bottom: 12 })
        .backgroundColor('rgba(22,22,22,0.5)').borderRadius(12)
      }
      .width('92%')
    }
  }

  /** 剥除 HTML 标签（安全兜底） */
  private stripHtml(html: string): string {
    if (!html) return '';
    return html
      .replace(/<br\s*\/?>/gi, '\n')
      .replace(/<\/?p[^>]*>/gi, '\n')
      .replace(/<\/?div[^>]*>/gi, '\n')
      .replace(/<\/?li[^>]*>/gi, '\n')
      .replace(/<[^>]+>/g, '')
      .replace(/&nbsp;/g, ' ')
      .replace(/&amp;/g, '&')
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>')
      .replace(/&quot;/g, '"')
      .replace(/&#39;/g, "'")
      .replace(/\n{3,}/g, '\n\n')
      .trim();
  }

  private getStatsView(): number {
    if (this.opus && this.opus.stats) return this.opus.stats.view;
    if (this.article && this.article.stats) return this.article.stats.view;
    return 0;
  }

  // ===== 构建 =====
  build() {
    List({ space: 14 }) {
      // 顶部留白
      ListItem() { Column().height('12%') }

      if (this.isLoading) {
        this.loadingView()
      } else if (this.loadError) {
        this.errorView()
      } else {
        ListItem(){
          Column().height("14%")
        }
        this.coverImage()
        this.titleText()
        this.summaryText()
        this.upInfoCard()
        this.sectionDivider()
        this.paragraphList()
        this.actionBar()

        // 底部留白
        ListItem() { Column().height('14%') }
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: 14, right: 4 })
    .focusable(true)
    .focusOnTouch(true)
    .defaultFocus(true)
  }
}
