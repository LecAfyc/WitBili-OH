import { VideoCard } from '../model/ContentCard';
import { getRecommend, resetRecommendCursor } from '../api/RecommendApi';
import { VideoCardComponent } from '../components/VideoCardComponent';
import { LengthMetrics } from '@kit.ArkUI';

@Component
export struct RcmdPage {
  @Consume('pageStack') pageStack: NavPathStack;
  // ===== 状态 =====
  @State videoList: VideoCard[] = [];
  @State isLoading: boolean = false;
  @State isRefreshing: boolean = false;
  @State errorMessage: string = '';
  @State firstLoad: boolean = true;
  @State hasMore: boolean = true;

  aboutToAppear(): void {
    this.loadRecommend(false);
  }

  build() {
    NavDestination() {
      Stack() {
        Column() {
          this.HeaderBar()
          this.MainContent()
        }
        .width('100%').height('100%')
        .padding({
          left: 16,
          right: 16,
          top: 8,
          bottom: 16
        })
      }
      .width('100%').height('100%')
    }
    .height('100%')
    .width('100%')
    .hideBackButton(true)
    .hideTitleBar(true)
    .backgroundImage($r("app.media.oobe"))
  }

  // ==========================
  @Builder
  HeaderBar() {
    Row() {
      Row() {
        Circle().width(8).height(8).fill('#FB7299')
        Text('推荐').fontSize(16).fontColor('#EEEEEE')
          .fontWeight(FontWeight.Medium).margin({ left: 4 })
      }
      .onClick(() => {
        this.showNavMenu();
      })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding({ top: 8, bottom: 4 })
    .justifyContent(FlexAlign.Center)
  }

  // ==========================
  @Builder
  MainContent() {
    if (this.firstLoad && this.isLoading && this.videoList.length === 0) {
      Column() {
        LoadingProgress().width(40).height(40).color('#FB7299')
        Text('加载中...').fontSize(15).fontColor('#666666').margin({ top: 12 })
      }
      .width('100%').height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    } else if (this.videoList.length === 0) {
      Column() {
        Text('󰁕 TRACK LOST').fontSize(40)
        Text(this.errorMessage)
          .fontSize(14)
          .fontColor('#888888')
          .textAlign(TextAlign.Center)
          .margin({ top: 8 })
          .lineHeight(20)
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
        List({ space: 8 }) {
          ForEach(this.videoList, (item: VideoCard, index?: number) => {
            ListItem() {
              VideoCardComponent({ card: item })
            }
          })
          ListItem() {
            Row() {
              if (this.isLoading) {
                LoadingProgress().width(18).height(18).color('#FB7299')
                Text('加载更多...').fontSize(13).fontColor('#777777').margin({ left: 6 })
              } else if (!this.hasMore) {
                Text('— 没有更多了 —').fontSize(13).fontColor('#555555')
              }
            }
            .width('100%').justifyContent(FlexAlign.Center)
            .padding({ top: 8, bottom: 16 })
          }
        }
        .width('100%')
        .height('100%')
        .onReachEnd(() => {
          this.handleLoadMore();
        })
        .edgeEffect(EdgeEffect.Spring)
        .fadingEdge(true, { fadingEdgeLength: LengthMetrics.vp(20) })
        .focusable(true)
        .focusOnTouch(true)
        .defaultFocus(true)
      }
      .onRefreshing(() => {
        this.handleRefresh();
      })
      .refreshOffset(60)
      .width('100%').height('100%')
    }
  }

  // ===== 数据方法 =====
  private async loadRecommend(isRefresh: boolean): Promise<void> {
    if (this.isLoading) {
      return;
    }
    this.isLoading = true;
    this.errorMessage = '';

    if (isRefresh) {
      resetRecommendCursor();
      this.firstLoad = true;
      this.videoList = [];
    }

    try {
      let result = await getRecommend();
      if (this.firstLoad) {
        this.videoList = result.items;
        this.firstLoad = false;
      } else {
        this.videoList = this.videoList.concat(result.items);
      }
      this.hasMore = result.items.length > 0;
      if (this.videoList.length === 0) {
        this.errorMessage = '暂无推荐内容';
      }
    } catch (e) {
      console.error('[Index] 加载失败:', JSON.stringify(e));
      this.errorMessage = '网络开小差了\n下拉重试';
    } finally {
      this.isLoading = false;
      this.isRefreshing = false;
    }
  }

  private handleRefresh(): void {
    this.isRefreshing = true;
    this.hasMore = true;
    this.errorMessage = '';
    this.loadRecommend(true);
  }

  // ==========================
  //          顶栏

  private handleLoadMore(): void {
    if (!this.isLoading && this.hasMore) {
      this.loadRecommend(false);
    }
  }

  // ==========================
  //        主内容区

  private showNavMenu(): void {
    this.pageStack.pushPath({ name: 'Menu' });
  }
}
