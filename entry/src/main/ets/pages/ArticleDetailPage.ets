import { ArcSwiper } from '@kit.ArkUI';
import { ArticleDetailComponent } from '../components/ArticleDetailComponent';
import { CommentSection } from '../components/VideoDetail/CommentSection';
import { ArticleCard } from '../model/ContentCard';


@Component
export struct ArticleDetailPage{
  @Consume('pageStack') pageStack: NavPathStack;

  // ==== 资源定义 ====
  @State pageParam: ArticleCard = new ArticleCard();

  build() {
    NavDestination(){
      ArcSwiper(){
        //视频详情页
        Column(){
          ArticleDetailComponent({card: this.pageParam})
        }
        //评论区页
        Column(){
          CommentSection({aid: this.pageParam.cvid, type: [12]})
        }
      }
      .indicator(false)
      .height('100%')
      .width('100%')
      Row() {
        Text('󰃚').fontSize(18).fontColor('#FB7299').width(24).textAlign(TextAlign.Center)
        Text('返回').fontSize(15).fontColor('#EEEEEE').margin({ left: 4 })
      }
      .width('30%')
      .position({ x: 80, y: 8 })
      .padding({ left: 2, top: 8, bottom: 8 })
      .borderRadius(10)
      .backgroundColor('rgba(22,22,22,0.6)')
      .onClick(() => { if (this.pageStack) this.pageStack.pop(); })
    }
    .height('100%')
    .width('100%')
    .backgroundImage($r("app.media.oobe"))
    .hideBackButton(true)
    .hideTitleBar(true)
    .onReady((context: NavDestinationContext) => {
      let incoming: ArticleCard = context.pathInfo.param as ArticleCard;
      if (incoming && (incoming.cvid > 0)) {
        this.pageParam = incoming;
      }
    })
  }
}
