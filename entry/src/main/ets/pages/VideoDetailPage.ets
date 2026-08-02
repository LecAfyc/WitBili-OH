import { ArcSwiper } from '@kit.ArkUI';
import { VideoCard } from '../model/ContentCard';
import { VideoDetailArc } from '../components/VideoDetail';
import { VideoRelatedRecommend } from '../components/VideoRelatedRecommend';
import { CommentSection } from '../components/CommentSection';
import { bv2av } from '../api/CommonApi';

@Component
export struct VideoDetailPage {
  @Consume('pageStack') pageStack: NavPathStack;
  // ==== 资源定义 ====
  @State pageParam: VideoCard = new VideoCard();

  build() {
    NavDestination() {
      ArcSwiper() {
        //视频详情页
        Column() {
          VideoDetailArc({ pageParam: this.pageParam })
        }

        //评论区页
        Column() {
          CommentSection({ aid: this.pageParam.aid, type: [1, 5] })
        }

        //视频推荐页
        Column() {
          VideoRelatedRecommend({ aid: this.pageParam.aid, bvid: this.pageParam.bvid })
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
        if (incoming.aid <= 0 && incoming.bvid) {
          incoming.aid = bv2av(incoming.bvid);
        }
        this.pageParam = incoming;
      }
    })
  }
}
