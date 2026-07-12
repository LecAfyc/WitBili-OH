import { ArcSwiper } from '@kit.ArkUI';
import { searchVideos, searchUsers, searchArticles } from '../api/SearchApi';
import { VideoCardComponent } from '../components/VideoCardComponent';
import { UserCardComponent } from '../components/UserCardComponent';
import { ArticleCardComponent } from '../components/ArticleCardComponent';
import { VideoCard, ArticleCard } from '../model/ContentCard';
import { UserCard } from '../model/UserCard';


@Component
export struct SearchResultPage {
  @Consume('pageStack') pageStack: NavPathStack;
  @State keyword: string = "";
  @State videoResults: VideoCard[] = [];
  @State userResults: UserCard[] = [];
  @State videoLoading: boolean = false;
  @State userLoading: boolean = false;
  @State articleResults: ArticleCard[] = [];
  @State videoHasMore: boolean = true;
  @State articleHasMore: boolean = true;
  @State userHasMore: boolean = true;
  @State currentVideoPage: number = 1;
  @State currentArticlePage: number = 1;
  @State currentUserPage: number = 1;
  @State articleLoading: boolean = false;

  async loadVideoResults(): Promise<void> {
    if (this.videoLoading || !this.videoHasMore || this.keyword === "") {
      return;
    }
    this.videoLoading = true;
    let newResults: VideoCard[] = await searchVideos(this.keyword, this.currentVideoPage);
    if (newResults.length > 0) {
      this.videoResults = this.videoResults.concat(newResults);
      if (this.videoResults.length > 50) {
        this.videoResults = this.videoResults.slice(this.videoResults.length - 50);
      }
      this.currentVideoPage++;
      if (newResults.length < 20) {
        this.videoHasMore = false;
      }
    } else {
      this.videoHasMore = false;
    }
    this.videoLoading = false;
  }

  async loadArticleResults(): Promise<void> {
    if (this.articleLoading || !this.articleHasMore || this.keyword === '') {
      return;
    }
    this.articleLoading = true;
    let newResults: ArticleCard[] = await searchArticles(this.keyword, this.currentArticlePage);
    if (newResults.length > 0) {
      this.articleResults = this.articleResults.concat(newResults);
      if (this.articleResults.length > 50) {
        this.articleResults = this.articleResults.slice(this.articleResults.length - 50);
      }
      this.currentArticlePage++;
      if (newResults.length < 20) {
        this.articleHasMore = false;
      }
    } else {
      this.articleHasMore = false;
    }
    this.articleLoading = false;
  }

  async loadUserResults(): Promise<void> {
    if (this.userLoading || !this.userHasMore || this.keyword === "") {
      return;
    }
    this.userLoading = true;
    let newResults: UserCard[] = await searchUsers(this.keyword, this.currentUserPage);
    if (newResults.length > 0) {
      this.userResults = this.userResults.concat(newResults);
      if (this.userResults.length > 50) {
        this.userResults = this.userResults.slice(this.userResults.length - 50);
      }
      this.currentUserPage++;
      if (newResults.length < 20) {
        this.userHasMore = false;
      }
    } else {
      this.userHasMore = false;
    }
    this.userLoading = false;
  }

  build() {
    NavDestination() {
      ArcSwiper() {
        //视频搜索页
        Column() {
          List({ space: 8 }) {
            ListItem() {
              Column().height('14%')
            }

            ForEach(this.videoResults, (item: VideoCard) => {
              ListItem() {
                VideoCardComponent({ card: item })
              }
              .padding({ left: 14, right: 14 })
            })
            ListItem() {
              Row() {
                if (this.videoLoading) {
                  LoadingProgress().width(18).height(18).color('#FB7299')
                  Text('加载中...').fontSize(13).fontColor('#777777').margin({ left: 6 })
                } else if (!this.videoHasMore) {
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
            this.loadVideoResults();
          })
          .focusable(true)
          .focusOnTouch(true)
          .defaultFocus(true)
        }

        //专栏搜索页
        Column() {
          List({ space: 8 }) {
            ListItem() {
              Column().height('14%')
            }

            ForEach(this.articleResults, (item: ArticleCard) => {
              ListItem() {
                ArticleCardComponent({ card: item })
              }
              .padding({ left: 14, right: 14 })
            })
            ListItem() {
              Row() {
                if (this.articleLoading) {
                  LoadingProgress().width(18).height(18).color('#FB7299')
                  Text('加载中...').fontSize(13).fontColor('#777777').margin({ left: 6 })
                } else if (!this.articleHasMore) {
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
            this.loadArticleResults();
          })
          .focusable(true)
          .focusOnTouch(true)
          .defaultFocus(true)
        }

        //用户搜索页
        Column() {
          List({ space: 8 }) {
            ListItem() {
              Column().height('14%')
            }

            ForEach(this.userResults, (item: UserCard) => {
              ListItem() {
                UserCardComponent({ card: item, baseFontSize: 14, extraInfo: item.desc })
              }
              .padding({ left: 14, right: 14 })
            })
            ListItem() {
              Row() {
                if (this.userLoading) {
                  LoadingProgress().width(18).height(18).color('#FB7299')
                  Text('加载更多...').fontSize(13).fontColor('#777777').margin({ left: 6 })
                } else if (!this.userHasMore) {
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
            this.loadUserResults();
          })
          .focusable(true)
          .focusOnTouch(true)
          .defaultFocus(true)
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
      this.keyword = context.pathInfo.param as string;
      this.loadVideoResults();
      this.loadArticleResults();
      this.loadUserResults();
    })
  }
}
