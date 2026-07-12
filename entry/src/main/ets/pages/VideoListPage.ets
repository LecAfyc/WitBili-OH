/**
 * 视频列表页面（复用：收藏夹 / 历史记录 / 稍后再看）
 *
 * 路由参数：
 *   sourceType: 'collection' | 'history' | 'watchLater'
 *   mlid?:      收藏夹 mlid（sourceType='collection' 时必填）
 *   title?:     页面标题
 *
 * 行为差异：
 *   - collection：页码翻页，不可删除
 *   - history：   游标翻页，不可删除
 *   - watchLater：一次性加载，长按可删除
 */

import { promptAction } from '@kit.ArkUI';
import { VideoCard } from '../model/ContentCard';
import { VideoCardComponent } from '../components/VideoCardComponent';
import { LengthMetrics } from '@kit.ArkUI';
import { getFavResourceList } from '../api/UserApi';
import { getHistoryList, getToViewList, deleteToView } from '../api/HistoryApi';


/** 视频列表页面路由参数 */
export class VideoListPageParams {
  sourceType: string = '';
  mlid: number = 0;
  title: string = '';

  constructor(sourceType: string, title: string, mlid?: number) {
    this.sourceType = sourceType;
    this.title = title;
    if (mlid !== undefined && mlid > 0) {
      this.mlid = mlid;
    }
  }
}


@Component
export struct VideoListPage {
  @Consume('pageStack') pageStack: NavPathStack;
  // ===== 视图状态 =====
  @State videoList: VideoCard[] = [];
  @State isLoading: boolean = false;
  @State isRefreshing: boolean = false;
  @State pageTitle: string = '';
  @State hasMore: boolean = true;
  @State errorMessage: string = '';
  @State firstLoad: boolean = true;
  // ===== 来源配置（onReady 时设置） =====
  private sourceType: string = '';
  // === collection 翻页状态 ===
  private mlid: number = 0;
  private currentPage: number = 1;
  // === history 游标翻页状态 ===
  private historyCursorMax: number = 0;
  private historyCursorViewAt: number = 0;

  build() {
    NavDestination() {
      Stack() {
        Column() {
          // ---- 主内容区 ----
          this.MainContent()
        }
        .width('100%')
        .height('100%')
        .padding({
          left: 16,
          right: 16,
          top: 8,
          bottom: 16
        })
      }
      .width('100%')
      .height('100%')
    }
    .height('100%')
    .width('100%')
    .hideBackButton(true)
    .hideTitleBar(true)
    .backgroundImage($r('app.media.oobe'))
    .onReady((context: NavDestinationContext) => {
      let params: VideoListPageParams = context.pathInfo.param as VideoListPageParams;
      this.sourceType = params.sourceType;
      this.mlid = params.mlid;
      this.pageTitle = params.title;
      console.info('[VideoListPage] onReady: sourceType=' + this.sourceType +
        ' mlid=' + this.mlid + ' title=' + this.pageTitle);
      this.loadInitial();
    })
  }

  // ==========================
  @Builder
  MainContent() {
    if (this.firstLoad && this.isLoading && this.videoList.length === 0) {
      // ---- 首次加载中 ----
      Column() {
        LoadingProgress()
          .width(40)
          .height(40)
          .color('#FB7299')
        Text('加载中...')
          .fontSize(15)
          .fontColor('#666666')
          .margin({ top: 12 })
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    } else if (this.videoList.length === 0) {
      // ---- 空状态 ----
      Column() {
        Text('X TRACK LOST')
          .fontSize(40)
        Text(this.errorMessage)
          .fontSize(14)
          .fontColor('#888888')
          .textAlign(TextAlign.Center)
          .margin({ top: 8 })
          .lineHeight(20)
        Text('点击刷新')
          .fontSize(13)
          .fontColor('#FB7299')
          .margin({ top: 16 })
          .onClick(() => {
            this.handleRefresh();
          })
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    } else {
      // ---- 视频列表 ----
      Refresh({ refreshing: this.isRefreshing }) {
        List({ space: 8 }) {
          ListItem() {
            Column().height('14%')
          }

          ForEach(this.videoList, (item: VideoCard, index?: number) => {
            ListItem() {
              VideoCardComponent({ card: item })
            }
            .gesture(
              LongPressGesture()
                .onAction(() => {
                  if (index !== undefined) {
                    this.showDeleteDialog(item, index);
                  }
                })
            )
          })

          // 底部加载状态指示
          if (this.isWatchLater()) {
            // 稍后再看不显示"加载更多"
          } else {
            ListItem() {
              Row() {
                if (this.isLoading) {
                  LoadingProgress()
                    .width(18)
                    .height(18)
                    .color('#FB7299')
                  Text('加载更多...')
                    .fontSize(13)
                    .fontColor('#777777')
                    .margin({ left: 6 })
                } else if (!this.hasMore) {
                  Text('— 没有更多了 —')
                    .fontSize(13)
                    .fontColor('#555555')
                }
              }
              .width('100%')
              .justifyContent(FlexAlign.Center)
              .padding({ top: 8, bottom: 16 })
            }
          }

          ListItem() {
            Column().height('14%')
          }
        }
        .width('100%')
        .height('100%')
        .onReachEnd(() => {
          if (!this.isWatchLater()) {
            this.loadMore();
          }
        })
        .onReachStart(() => {
          if (this.sourceType === 'collection' && this.videoList.length >= 50) {
            this.loadInitial();
          }
        })
        .edgeEffect(EdgeEffect.Spring)
        .focusable(true)
        .focusOnTouch(true)
        .defaultFocus(true)
      }
      .onRefreshing(() => {
        this.handleRefresh();
      })
      .refreshOffset(60)
      .width('100%')
      .height('100%')
    }
  }

  // ===== 计算属性（非 State，不影响渲染） =====
  private isWatchLater(): boolean {
    return this.sourceType === 'watchLater';
  }

  // ==========================
  //        数据加载
  // ==========================

  private isCollection(): boolean {
    return this.sourceType === 'collection';
  }

  private isHistory(): boolean {
    return this.sourceType === 'history';
  }

  private async loadInitial(): Promise<void> {
    this.isLoading = true;
    this.errorMessage = '';
    this.firstLoad = true;
    this.currentPage = 1;
    this.historyCursorMax = 0;
    this.historyCursorViewAt = 0;

    try {
      if (this.isCollection() && this.mlid > 0) {
        let result = await getFavResourceList(this.mlid, 1, 20);
        this.videoList = result.videos;
        if (this.videoList.length > 50) {
          this.videoList = this.videoList.slice(this.videoList.length - 50);
        }
        this.hasMore = result.hasMore;
        if (this.videoList.length === 0) {
          this.errorMessage = '收藏夹空空如也';
        }
      } else if (this.isHistory()) {
        let result = await getHistoryList(0, 0, 20);
        this.videoList = result.items;
        if (this.videoList.length > 50) {
          this.videoList = this.videoList.slice(this.videoList.length - 50);
        }
        this.hasMore = result.hasMore;
        this.historyCursorMax = result.cursor.max;
        this.historyCursorViewAt = result.cursor.viewAt;
        if (this.videoList.length === 0) {
          this.errorMessage = '还没有观看记录';
        }
      } else if (this.isWatchLater()) {
        let result = await getToViewList();
        this.videoList = result.items;
        this.hasMore = false;
        if (this.videoList.length === 0) {
          this.errorMessage = '稍后再看列表为空';
        }
      } else {
        this.errorMessage = '未知列表类型';
      }
    } catch (e) {
      console.error('[VideoListPage] 加载失败:', JSON.stringify(e));
      this.errorMessage = '网络开小差了\n下拉重试';
    } finally {
      this.isLoading = false;
      this.firstLoad = false;
    }
  }

  // ==========================
  //       删除操作（仅稍后再看）
  // ==========================

  private async loadMore(): Promise<void> {
    if (this.isLoading || !this.hasMore || this.isWatchLater()) {
      return;
    }
    this.isLoading = true;

    try {
      if (this.isCollection() && this.mlid > 0) {
        let nextPage: number = this.currentPage + 1;
        let result = await getFavResourceList(this.mlid, nextPage, 20);
        this.videoList = this.videoList.concat(result.videos);
        if (this.videoList.length > 50) {
          this.videoList = this.videoList.slice(this.videoList.length - 50);
        }
        this.hasMore = result.hasMore;
        this.currentPage = nextPage;
      } else if (this.isHistory()) {
        let result = await getHistoryList(
          this.historyCursorMax,
          this.historyCursorViewAt,
          20
        );
        this.videoList = this.videoList.concat(result.items);
        if (this.videoList.length > 50) {
          this.videoList = this.videoList.slice(this.videoList.length - 50);
        }
        this.hasMore = result.hasMore;
        this.historyCursorMax = result.cursor.max;
        this.historyCursorViewAt = result.cursor.viewAt;
      }
    } catch (e) {
      console.error('[VideoListPage] 加载更多失败:', JSON.stringify(e));
    } finally {
      this.isLoading = false;
    }
  }

  private handleRefresh(): void {
    if (this.isRefreshing) {
      return;
    }
    this.isRefreshing = true;
    this.hasMore = true;
    this.errorMessage = '';

    this.loadInitial().finally(() => {
      this.isRefreshing = false;
    });
  }

  // ==========================
  //        视图构建
  // ==========================

  private showDeleteDialog(item: VideoCard, index: number): void {
    if (!this.isWatchLater()) {
      return;
    }

    promptAction.showDialog({
      message: '删除「' + item.title + '」？',
      buttons: [
        { text: '取消', color: '#999999' },
        { text: '删除', color: '#FF0000' },
      ]
    }).then((result) => {
      if (result.index === 1) {
        this.deleteVideo(item, index);
      }
    }).catch(() => {
      // 用户取消对话框，不做任何处理
    });
  }

  // ==========================
  //        主内容区

  private async deleteVideo(item: VideoCard, index: number): Promise<void> {
    try {
      let result = await deleteToView(item.aid);
      if (result.success) {
        this.videoList.splice(index, 1);
        this.getUIContext().getPromptAction().showToast({ message: '已删除' });
        if (this.videoList.length === 0) {
          this.errorMessage = '稍后再看列表为空';
        }
      } else {
        this.getUIContext().getPromptAction().showToast({ message: '删除失败' });
      }
    } catch (e) {
      console.error('[VideoListPage] 删除异常:', JSON.stringify(e));
      this.getUIContext().getPromptAction().showToast({ message: '删除失败' });
    }
  }
}
