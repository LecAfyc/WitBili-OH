import { VideoCard } from '../model/ContentCard';
import { getRecommend, resetRecommendCursor } from '../api/RecommendApi';
import { VideoCardComponent } from '../components/VideoCardComponent';
import { LengthMetrics } from '@kit.ArkUI';
import { BasicDataSource } from '../utils/BasicDataSource';
import {
  fetchUpdateCheck,
  getCurrentVersionCode,
  isVersionIgnored,
  setVersionIgnored,
  isBroadcastShown,
  markBroadcastShown,
  nowSeconds,
  LatestVersionInfo,
  CanaryVersionInfo,
  BroadcastInfo,
  UpdateCheckResult
} from '../api/UpdateApi';

const RELEASE_URL: string = 'https://github.com/LecAfyc/WitBili-OH/releases';

let updateCheckedThisLaunch: boolean = false;

@Component
export struct RcmdPage {
  @Consume('pageStack') pageStack: NavPathStack;
  // ===== 状态 =====
  @State videoListCount: number = 0;
  private videoDS: BasicDataSource<VideoCard> = new BasicDataSource<VideoCard>();
  @State isLoading: boolean = false;
  @State isRefreshing: boolean = false;
  @State errorMessage: string = '';
  @State firstLoad: boolean = true;
  @State hasMore: boolean = true;
  @State isUpdateSheetShow: boolean = false;
  @State isAnnouncementSheetShow: boolean = false;
  @State latestInfo: LatestVersionInfo | null = null;
  @State currentBroadcast: BroadcastInfo | null = null;
  private pendingResult: UpdateCheckResult | null = null;

  aboutToAppear(): void {
    this.loadRecommend(false);
    if (!updateCheckedThisLaunch) {
      updateCheckedThisLaunch = true;
      this.checkUpdateAndBroadcast();
    }
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
      .bindSheet($$this.isUpdateSheetShow, this.UpdateSheetBuilder(), {
        height: 340,
        dragBar: true,
        backgroundColor: 'rgba(28,28,30,0.45)',
        blurStyle: BlurStyle.BACKGROUND_THIN,
        onDisappear: () => {
          this.isUpdateSheetShow = false;
        }
      })
      .bindSheet($$this.isAnnouncementSheetShow, this.AnnouncementSheetBuilder(), {
        height: 340,
        dragBar: true,
        backgroundColor: 'rgba(28,28,30,0.45)',
        blurStyle: BlurStyle.BACKGROUND_THIN,
        onDisappear: () => {
          this.isAnnouncementSheetShow = false;
        }
      })
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
    if (this.firstLoad && this.isLoading && this.videoListCount === 0) {
      Column() {
        LoadingProgress().width(40).height(40).color('#FB7299')
        Text('加载中...').fontSize(15).fontColor('#666666').margin({ top: 12 })
      }
      .width('100%').height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    } else if (this.videoListCount === 0) {
      Column() {
        Text('TRACK LOST').fontSize(40)
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
          LazyForEach(this.videoDS, (item: VideoCard) => {
            ListItem() {
              VideoCardComponent({ card: item })
            }
          }, (item: VideoCard) => item.bvid || item.aid.toString())
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
        .cachedCount(1)
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
      this.videoDS.resetData([]);
      this.videoListCount = 0;
    }

    try {
      let result = await getRecommend();
      if (this.firstLoad) {
        this.videoDS.resetData(result.items);
        this.videoListCount = this.videoDS.totalCount();
        this.firstLoad = false;
      } else {
        this.videoDS.appendData(result.items);
        this.videoDS.trimTo(50);
        this.videoListCount = this.videoDS.totalCount();
      }
      this.hasMore = result.items.length > 0;
      if (this.videoListCount === 0) {
        this.errorMessage = '暂无推荐内容';
      }
    } catch (e) {
      console.error('[Index] 加载失败:', JSON.stringify(e));
      this.errorMessage = '网络错误';
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

  // ==========================
  //      更新检查与公告
  // ==========================

  private async checkUpdateAndBroadcast(): Promise<void> {
    let result: UpdateCheckResult | null = await fetchUpdateCheck();
    if (result === null) {
      try {
        this.getUIContext().getPromptAction().showToast({
          message: '获取更新与公告失败',
          duration: 2000
        });
      } catch (e) {
        console.warn('[RcmdPage] canary Toast 失败');
      }
      return;
    }
    this.pendingResult = result;

    let current: number = getCurrentVersionCode();
    console.log("[RCMD] VersionCode = " + current)
    let latest: LatestVersionInfo | null = result.latest;

    if (latest !== null && latest.versionCode > current) {
      console.log("[RCMD] latestVersionCode = " + latest.versionCode)
      let ignored: boolean = isVersionIgnored(latest.versionCode);
      if (!ignored) {
        this.latestInfo = latest;
        this.isUpdateSheetShow = true;
        return;
      }
    }

    let mainIsLatest: boolean = latest === null || latest.versionCode <= current;
    let canary: CanaryVersionInfo | null = result.canary;
    if (mainIsLatest && canary !== null && canary.versionCode > current) {
      console.log("[RCMD] canaryVersionCode = " + canary.versionCode)
      this.showCanaryToast();
    }

    this.showBroadcastIfAvailable();
  }

  private showCanaryToast(): void {
    try {
      this.getUIContext().getPromptAction().showToast({
        message: '有新预览版，若想体验，请前往 Github 自行编译',
        duration: 4000
      });
    } catch (e) {
      console.warn('[RcmdPage] canary Toast 失败');
    }
  }

  private showBroadcastIfAvailable(): void {
    let result: UpdateCheckResult | null = this.pendingResult;
    if (result === null) {
      return;
    }
    let b: BroadcastInfo | null = result.broadcast;
    if (b !== null && !isBroadcastShown(b.releaseTimeStamp) && b.expiredTimeStamp >= nowSeconds()) {
      this.currentBroadcast = b;
      this.isAnnouncementSheetShow = true;
    }
  }

  private onGoRelease(): void {
    this.isUpdateSheetShow = false;
    this.pageStack.pushPath({ name: 'QrCode', param: RELEASE_URL });
  }

  private onSkipVersion(): void {
    if (this.latestInfo !== null) {
      setVersionIgnored(this.latestInfo.versionCode);
    }
    this.isUpdateSheetShow = false;
    this.showBroadcastIfAvailable();
  }

  private onBroadcastDismiss(): void {
    if (this.currentBroadcast !== null) {
      markBroadcastShown(this.currentBroadcast.releaseTimeStamp);
    }
    this.isAnnouncementSheetShow = false;
  }

  private latestVersionName(): string {
    return this.latestInfo !== null ? this.latestInfo.versionName : '';
  }

  private latestReleaseTime(): string {
    return this.latestInfo !== null ? this.latestInfo.releaseTimeName : '';
  }

  private latestDescriptionLines(): string[] {
    return this.latestInfo !== null ? this.latestInfo.descriptionLines : [];
  }

  private broadcastContentLines(): string[] {
    return this.currentBroadcast !== null ? this.currentBroadcast.contentLines : [];
  }

  // ==========================
  //        更新/公告半模态窗
  // ==========================

  @Builder
  UpdateSheetBuilder() {
    Column() {
      Text('发现新版本 ' + this.latestVersionName())
        .fontSize(16)
        .fontColor('#EEEEEE')
        .fontWeight(FontWeight.Bold)
        .margin({ top: 16, bottom: 4 })

      Text(this.latestReleaseTime())
        .fontSize(12)
        .fontColor('#888888')
        .margin({ bottom: 8 })

      List({ space: 4 }) {
        ForEach(this.latestDescriptionLines(), (line: string, index: number) => {
          ListItem() {
            Text(line)
              .fontSize(13)
              .fontColor('#DDDDDD')
              .width('100%')
          }
        }, (line: string, index: number) => index.toString())
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .focusable(true)
      .focusOnTouch(true)
      .defaultFocus(true)

      Row({ space: 12 }) {
        Button('前往 Github Release 页')
          .fontSize(13)
          .fontColor('#FFFFFF')
          .backgroundColor('#FB7299')
          .borderRadius(20)
          .height(36)
          .layoutWeight(1)
          .onClick(() => {
            this.onGoRelease();
          })

        Button('此版本不再提示')
          .fontSize(13)
          .fontColor('#FB7299')
          .backgroundColor(Color.Transparent)
          .border({ width: 1, color: '#FB7299' })
          .borderRadius(20)
          .height(36)
          .layoutWeight(1)
          .onClick(() => {
            this.onSkipVersion();
          })
      }
      .width('100%')
      .margin({ top: 12, bottom: 20 })
    }
    .width('100%')
    .height('100%')
    .padding({ left: 20, right: 20 })
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  AnnouncementSheetBuilder() {
    Column() {
      Text('公告')
        .fontSize(16)
        .fontColor('#EEEEEE')
        .fontWeight(FontWeight.Bold)
        .margin({ top: 16, bottom: 12 })

      List({ space: 6 }) {
        ForEach(this.broadcastContentLines(), (line: string, index: number) => {
          ListItem() {
            Text(line)
              .fontSize(13)
              .fontColor('#DDDDDD')
              .width('100%')
          }
        }, (line: string, index: number) => index.toString())
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .focusable(true)
      .focusOnTouch(true)
      .defaultFocus(true)

      Button('知道了')
        .fontSize(14)
        .fontColor('#FFFFFF')
        .backgroundColor('#FB7299')
        .borderRadius(20)
        .height(36)
        .width('65%')
        .margin({ top: 12, bottom: 20 })
        .onClick(() => {
          this.onBroadcastDismiss();
        })
    }
    .width('100%')
    .height('100%')
    .padding({ left: 20, right: 20 })
    .alignItems(HorizontalAlign.Center)
  }
}
