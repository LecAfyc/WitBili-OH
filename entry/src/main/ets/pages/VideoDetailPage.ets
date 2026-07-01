import { ArcSwiper } from '@kit.ArkUI';
import { UserCard } from '../model/UserCard';
import { VideoCard } from '../model/ContentCard';
import { VideoPage } from '../model/VideoPage';
import { VideoDetailArc } from '../components/VideoDetail/VideoDetail';
import { VideoRelatedRecommend } from '../components/VideoDetail/VideoRelatedRecommend';
import { CommentSection } from '../components/VideoDetail/CommentSection';
import { getFullVideoDetail } from '../api/VideoDetailApi';
import { checkHasLiked, checkCoinCount, checkHasFavoured } from '../api/VideoActionApi';
import { getRelatedVideos } from '../api/RecommendApi';
import { av2bv } from '../api/CommonApi';

@Component
export struct VideoDetailPage {
  @Consume('pageStack') pageStack: NavPathStack;
  // ==== 资源定义 ====
  @State pageParam: VideoCard = new VideoCard();
  @State up: UserCard = new UserCard();
  @State staff: Array<UserCard> = [];
  @State staffRoles: Array<string> = [];
  @State danmakus: number = 1145;
  @State time: number = 1145;
  @State duration: number = 1145;
  @State tags: Array<string> = ["a", "w", "m", "c"];
  @State desc: string = "空にヒビWhat follows the tall tale?\n" +
    "ここでまた無敵に成れそうな\n" +
    "終わりない魔法でとかしていく\n" +
    "誰かが焼いたお菓子を\n" +
    "静寂のリズム刻むタクト\n" +
    "黒塗りの楽譜を詠むヴィオラ\n" +
    "歯抜けのメロディが繋がって\n" +
    "幕を下ろそうパレードへ！\n";
  // 点赞/投币/收藏——让子组件通过 @Link 双向绑定修改，用 $ 传入
  @State like: number = 1145;
  @State coin: number = 1145;
  @State favorite: number = 1145;
  @State share: number = 1145;
  @State pages: Array<VideoPage> = [];
  // 当前用户的行为状态
  @State isLiked: boolean = false;
  @State isFavoured: boolean = false;
  @State coinsGiven: number = 0;
  // 相关推荐视频
  @State relatedVideos: VideoCard[] = [];
  @State bv: string = "";

  build() {
    NavDestination() {
      ArcSwiper() {
        //视频详情页
        Column() {
          VideoDetailArc({
            pageParam: this.pageParam,
            up: this.up,
            staff: this.staff,
            staffRoles: this.staffRoles,
            danmakus: this.danmakus,
            time: this.time,
            duration: this.duration,
            tags: this.tags,
            desc: this.desc,
            like: $like, // @Link：双向绑定
            coin: $coin, // @Link
            favorite: this.favorite,
            share: this.share,
            pages: this.pages,
            isLiked: $isLiked, // @Link
            isFavoured: $isFavoured, // @Link
            coinsGiven: $coinsGiven, // @Link
            bv: this.bv
          })
        }

        //评论区页
        Column() {
          CommentSection({ aid: this.pageParam.aid, type: [1, 5] })
        }

        //视频推荐页
        Column() {
          VideoRelatedRecommend({ relatedVideos: this.relatedVideos })
        }
      }
      .indicator(false)
      .height('100%')
      .width('100%')

      Row() {
        Text('<').fontSize(18).fontColor('#FB7299').width(24).textAlign(TextAlign.Center)
        Text('返回').fontSize(15).fontColor('#EEEEEE').margin({ left: 4 })
      }
      .width('30%')
      .position({ x: 80, y: 8 })
      .padding({ left: 2, top: 8, bottom: 8 })
      .borderRadius(10)
      .backgroundColor('rgba(22,22,22,0.6)')
      .onClick(() => {
        if (this.pageStack) {
          this.pageStack.pop();
        }
      })
    }
    .height('100%')
    .width('100%')
    .backgroundImage($r("app.media.oobe"))
    .hideBackButton(true)
    .hideTitleBar(true)
    .onReady((context: NavDestinationContext) => {
      let incoming: VideoCard = context.pathInfo.param as VideoCard;
      if (incoming && (incoming.bvid || incoming.aid > 0)) {
        this.pageParam = incoming;
        this.loadVideoDetail(incoming.bvid, incoming.aid);
        this.loadRelatedVideos(incoming.aid, incoming.bvid);
      }
    })
  }

  private async loadRelatedVideos(aid: number, bvid?: string): Promise<void> {
    try {
      let list = await getRelatedVideos(aid > 0 ? aid : undefined, bvid);
      this.relatedVideos = list;
      console.info('[VideoDetail] 相关推荐加载完成: ' + list.length.toString() + ' 条');
    } catch (e) {
      console.error('[VideoDetail] 相关推荐加载失败:', String(e));
    }
  }

  private async loadVideoDetail(bvid: string, aid: number): Promise<void> {
    try {
      let result = await getFullVideoDetail(bvid, aid > 0 ? aid : undefined);
      // pages 先赋值，保持与子组件 @Watch('onPagesChanged') 的数据流向一致
      this.pages = result.pages;
      this.up = result.up;
      this.staff = result.staff;
      this.staffRoles = result.staffRoles;
      this.danmakus = result.danmakus;
      this.time = result.time;
      this.duration = result.duration;
      this.tags = result.tags;
      this.desc = result.desc;
      this.like = result.like;
      this.coin = result.coin;
      this.favorite = result.favorite;
      this.share = result.share;
      this.pageParam = result.pageParam;
      console.info('[VideoDetail] 详情加载成功: ' + result.pageParam.title);

      // 异步查询点赞/投币状态
      let aidNum: number = result.pageParam.aid || aid;
      if (aidNum > 0) {
        this.loadActionStatus(aidNum);
      }
      this.bv = result.pageParam.bvid !== "" ? result.pageParam.bvid : av2bv(aidNum)
    } catch (e) {
      console.error('[VideoDetail] 详情加载失败:', String(e));
    }
  }

  private async loadActionStatus(aid: number): Promise<void> {
    try {
      let GeneratedDestructArray_1 = await Promise.all([
        checkHasLiked(aid),
        checkCoinCount(aid),
        checkHasFavoured(aid)
      ]);
      let liked = GeneratedDestructArray_1[0];
      let coins = GeneratedDestructArray_1[1];
      let favoured = GeneratedDestructArray_1[2];
      this.isLiked = liked;
      this.isFavoured = favoured;
      this.coinsGiven = coins;
      console.info('[VideoDetail] 点赞状态:', liked, '投币数:', coins, '收藏状态:', favoured);
    } catch (e) {
      console.warn('[VideoDetail] 状态查询失败:', String(e));
    }
  }
}
