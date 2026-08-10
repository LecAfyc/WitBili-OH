import { SingleComment } from "../model/CommentCard";
import { CommentCardComponent } from "../components/CommentCardComponent";
import { getCommentReplies } from "../api/CommentApi";
import { LengthMetrics } from "@kit.ArkUI";
import { BasicDataSource } from "../utils/BasicDataSource";

@Component
export struct CommentPage {
  @Consume('pageStack') pageStack: NavPathStack;
  pageParam: SingleComment = new SingleComment(); //由父页面传入
  @State replyCount: number = 0;
  private replyDS: BasicDataSource<SingleComment> = new BasicDataSource<SingleComment>();
  @State isLoading: boolean = false;

  onPageShow(): void {
    this.loadReplies();
  }

  build() {
    NavDestination() {
      List({ space: 0 }) {
        ListItem() {
          Column().height('14%')
        }

        // 根评论
        ListItem() {
          CommentCardComponent({ comment: this.pageParam, isExpand: true, showReplies: false })
        }

        // 回复标题
        if (this.replyCount > 0) {
          ListItem() {
            Text("回复 " + this.replyCount + " 条")
              .fontSize(13)
              .fontColor("#888888")
              .padding({ left: 12, top: 8, bottom: 4 })
          }
        }

        // 加载中
        if (this.isLoading) {
          ListItem() {
            Row() {
              LoadingProgress().width(18).height(18).color("#FB7299")
              Text("加载中...").fontSize(12).fontColor("#777777").margin({ left: 6 })
            }
            .width("100%").justifyContent(FlexAlign.Center)
            .padding({ top: 16, bottom: 16 })
          }
        }

        // 回复列表
        LazyForEach(this.replyDS, (item: SingleComment) => {
          ListItem() {
            CommentCardComponent({ comment: item, isExpand: true, showReplies: false })
          }
        }, (item: SingleComment) => item.rpid.toString())

        // 暂无回复
        if (!this.isLoading && this.replyCount === 0 && this.pageParam.rpid !== '') {
          ListItem() {
            Text("暂无回复")
              .fontSize(13)
              .fontColor("#555555")
              .width("100%")
              .textAlign(TextAlign.Center)
              .padding({ top: 32, bottom: 32 })
          }
        }

        ListItem() {
          Column().height('14%')
        }
      }
      .width("100%")
      .height("110%")
      .edgeEffect(EdgeEffect.Spring)
      .fadingEdge(true, { fadingEdgeLength: LengthMetrics.vp(20) })
      .padding({ left: 14, right: 14 })
      .focusable(true)
      .focusOnTouch(true)
      .defaultFocus(true)
    }
    .height("100%")
    .width("100%")
    .backgroundImage($r("app.media.oobe"))
    .hideBackButton(true)
    .hideTitleBar(true)
    .onReady((context: NavDestinationContext) => {
      let incoming = context.pathInfo.param as SingleComment;
      if (incoming) {
        this.pageParam = incoming;
        this.loadReplies();
        console.info("[CommentPage] param: rpid=" + incoming.rpid + " oid=" + incoming.oid);
      }
    })
  }

  private async loadReplies(): Promise<void> {
    if (this.isLoading || this.pageParam.rpid === '' || this.pageParam.oid === '') {
      return;
    }
    this.isLoading = true;

    try {
      let result = await getCommentReplies(1, this.pageParam.oid, this.pageParam.rpid, 1, 20);
      this.replyDS.resetData(result.list);
      this.replyCount = this.replyDS.totalCount();
      console.info("[CommentPage] replies loaded: " + result.list.length + " total=" + result.total);
    } catch (e) {
      console.error("[CommentPage] load fail:", JSON.stringify(e));
    } finally {
      this.isLoading = false;
    }
  }
}
