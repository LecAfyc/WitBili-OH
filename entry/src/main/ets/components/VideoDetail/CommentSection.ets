/**
 * 评论区页面组件
 *
 */

import { SingleComment } from '../../model/CommentCard';
import { CommentCardComponent } from '../CommentCardComponent';
import { getCommentList, getCommentCount } from '../../api/CommentApi';
import { formatCount } from '../../api/CommonApi';
import { LengthMetrics } from '@kit.ArkUI';

@Component
export struct CommentSection {
  @Consume('pageStack') pageStack: NavPathStack;
  @Prop @Watch('onAidChanged') aid: number = 0;
  @Prop type: number[] = [1];
  @State commentList: SingleComment[] = [];
  @State totalCount: number = 0;
  @State isLoading: boolean = false;
  @State isRefreshing: boolean = false;
  @State hasMore: boolean = true;
  @State firstLoad: boolean = true;
  @State errorMessage: string = '';
  @State currentSort: number = 1; // 1=按热度(赞)  0=按时间
  @State currentPage: number = 1;

  // sort 值：API 中 0=时间 1=赞 2=回复
  // UI 按热度 → API sort=1；UI 按时间 → API sort=0

  aboutToAppear(): void {
    if (this.type === undefined || this.type === null) {
      this.type = [1];
    }
    console.info('[CommentSection] aboutToAppear, aid=' + this.aid);
    if (this.aid > 0) {
      this.loadComments(true);
    }
  }

  onAidChanged(): void {
    console.info('[CommentSection] onAidChanged, aid=' + this.aid + ', firstLoad=' + this.firstLoad);
    if (this.aid > 0 && this.firstLoad) {
      this.loadComments(true);
    }
  }

  // ===== 数据加载 =====

  build() {
    Column() {
      this.MainContent()
    }
    .width('100%').height('100%')
  }

  // ==========================
  @Builder
  MainContent() {
    if (this.firstLoad && this.isLoading && this.commentList.length === 0) {
      // 首次加载中
      Column() {
        LoadingProgress().width(40).height(40).color('#FB7299')
        Text('加载中...').fontSize(15).fontColor('#666666').margin({ top: 12 })
      }
      .width('100%').height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    } else if (this.commentList.length === 0) {
      // 没有评论
      Column() {
        Text('暂无评论').fontSize(14).fontColor('#888888')
          .textAlign(TextAlign.Center).lineHeight(20)
        Text('点击刷新').fontSize(13).fontColor('#FB7299').margin({ top: 16 })
          .onClick(() => {
            this.handleRefresh();
          })
      }
      .width('100%').height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    } else {
      Refresh({ refreshing: this.isRefreshing }) {
        List({ space: 0 }) {
          ListItem() {
            Column().height('14%')
          }

          // ─── 顶部：评论数 + 排序（垂直摆放，放在 List 第一项） ───
          ListItem() {
            Column() {
              Text('评论'
                + (this.totalCount > 0 ? ' ' + formatCount(this.totalCount) : ''))
                .fontSize(15)
                .fontColor('#EEEEEE')

              Row({ space: 10 }) {
                Text('按热度')
                  .fontSize(12)
                  .fontColor(this.currentSort === 1 ? '#FB7299' : '#777777')
                  .fontWeight(this.currentSort === 1 ? FontWeight.Medium : FontWeight.Regular)
                  .onClick(() => {
                    this.toggleSort(1);
                  })

                Text('按时间')
                  .fontSize(12)
                  .fontColor(this.currentSort === 0 ? '#FB7299' : '#777777')
                  .fontWeight(this.currentSort === 0 ? FontWeight.Medium : FontWeight.Regular)
                  .onClick(() => {
                    this.toggleSort(0);
                  })
              }
              .margin({ top: 6 })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Center)
            .padding({ top: 8, bottom: 8 })
          }

          // ─── 评论卡片（紧凑模式） ───
          ForEach(this.commentList, (item: SingleComment) => {
            ListItem() {
              CommentCardComponent({ comment: item, isExpand: false })
            }
            .onClick(() => {
              this.onCommentTap(item);
            })
          })

          // ─── 底部加载更多指示 ───
          ListItem() {
            Row() {
              if (this.isLoading) {
                LoadingProgress().width(18).height(18).color('#FB7299')
                Text('加载更多...').fontSize(12).fontColor('#777777').margin({ left: 6 })
              } else if (!this.hasMore && this.commentList.length > 0) {
                Text('— 没有更多了 —').fontSize(12).fontColor('#555555')
              }
            }
            .width('100%').justifyContent(FlexAlign.Center)
            .padding({ top: 8, bottom: 16 })
          }

          ListItem() {
            Column().height('14%')
          }
        }
        .width('100%')
        .height('110%')
        .onReachEnd(() => {
          this.handleLoadMore();
        })
        .edgeEffect(EdgeEffect.Spring)
        .fadingEdge(true, { fadingEdgeLength: LengthMetrics.vp(20) })
        .padding({ left: 14, right: 14 })
      }
      .onRefreshing(() => {
        this.handleRefresh();
      })
      .refreshOffset(60)
      .width('100%').height('100%')
    }
  }

  private async loadComments(isRefresh: boolean): Promise<void> {
    if (this.isLoading || this.aid <= 0) {
      return;
    }
    this.isLoading = true;
    this.errorMessage = '';

    if (isRefresh) {
      this.currentPage = 1;
      this.commentList = [];
      this.hasMore = true;
    }

    try {
      // 首次加载时获取总数
      if (isRefresh) {
        this.totalCount = await getCommentCount(this.aid, this.type);
      }

      const result = await getCommentList(this.aid, this.currentPage, 10, this.currentSort, this.type);

      if (isRefresh) {
        this.commentList = result.list;
      } else {
        this.commentList = this.commentList.concat(result.list);
        if (this.commentList.length > 50) {
          this.commentList = this.commentList.slice(this.commentList.length - 50);
        }
      }

      this.hasMore = result.list.length >= 10;
      this.currentPage++;
      this.firstLoad = false;
    } catch (e) {
      console.error('[Comment] 加载失败:', JSON.stringify(e));
      this.errorMessage = '评论加载失败';
    } finally {
      this.isLoading = false;
      this.isRefreshing = false;
    }
  }

  private handleRefresh(): void {
    this.isRefreshing = true;
    this.hasMore = true;
    this.errorMessage = '';
    this.loadComments(true);
  }

  private handleLoadMore(): void {
    if (!this.isLoading && this.hasMore) {
      this.loadComments(false);
    }
  }

  // ===== 构建 =====

  private toggleSort(sort: number): void {
    if (this.currentSort === sort) {
      return;
    }
    this.currentSort = sort;
    this.loadComments(true);
  }

  // ==========================
  //        主内容区

  private onCommentTap(comment: SingleComment): void {
    this.pageStack.pushPath({ name: 'CommentPage', param: comment });
    console.info('[Comment] tap rpid=' + comment.rpid);
  }
}
