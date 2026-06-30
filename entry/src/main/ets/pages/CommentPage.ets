import { SingleComment } from "../model/CommentCard";
import { CommentCardComponent } from "../components/CommentCardComponent";
import { getCommentReplies } from "../api/CommentApi";
import { LengthMetrics } from "@kit.ArkUI";

@Component
export struct CommentPage{
  @Consume('pageStack') pageStack: NavPathStack;

  pageParam: SingleComment = new SingleComment();    //由父页面传入

  @State replies: SingleComment[] = [];
  @State isLoading: boolean = false;

  onPageShow(): void {
    this.loadReplies();
  }

  private async loadReplies(): Promise<void> {
    if (this.isLoading || this.pageParam.rpid <= 0 || this.pageParam.oid <= 0) return;
    this.isLoading = true;

    try {
      let result = await getCommentReplies(1, this.pageParam.oid, this.pageParam.rpid, 1, 20);
      this.replies = result.list;
      console.info("[CommentPage] replies loaded: " + result.list.length + " total=" + result.total);
    } catch (e) {
      console.error("[CommentPage] load fail:", JSON.stringify(e));
    } finally {
      this.isLoading = false;
    }
  }

  build() {
    NavDestination() {
      List({ space: 0 }) {
        ListItem(){
          Column().height('14%')
        }

        // 根评论
        ListItem() {
          CommentCardComponent({ comment: this.pageParam, isExpand: true, showReplies: false })
        }

        // 回复标题
        if (this.replies.length > 0) {
          ListItem() {
            Text("回复 " + this.replies.length + " 条")
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
        ForEach(this.replies, (item: SingleComment) => {
          ListItem() {
            CommentCardComponent({ comment: item, isExpand: true, showReplies: false })
          }
        })

        // 暂无回复
        if (!this.isLoading && this.replies.length === 0 && this.pageParam.rpid > 0) {
          ListItem() {
            Text("暂无回复")
              .fontSize(13).fontColor("#555555")
              .width("100%").textAlign(TextAlign.Center)
              .padding({ top: 32, bottom: 32 })
          }
        }

        ListItem(){
          Column().height('14%')
        }
      }
      .width("100%").height("110%")
      .edgeEffect(EdgeEffect.Spring)
      .fadingEdge(true, { fadingEdgeLength: LengthMetrics.vp(20) })
      .padding({left: 14, right: 14})
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
}
