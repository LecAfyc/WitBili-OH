import { ArcSwiper, LengthMetrics } from '@kit.ArkUI';
import { UserCard, UserDetailCard } from '../model/UserCard';
import { VideoCard, ArticleCard } from '../model/ContentCard';
import {
  getUserDetail,
  getUserVideos,
  getUserArticles,
  getUserFollowings,
  getUserFans,
  getUserCreatedFavFolders,
  fillFavFolderDetail,
  followUser,
  unfollowUser,
  ModifyRelationResult
} from '../api/UserApi';
import { VideoCardComponent } from '../components/VideoCardComponent';
import { ArticleCardComponent } from '../components/ArticleCardComponent';
import { FavFolder } from '../model/FavFolder';
import { FolderCardComponent } from '../components/FolderCardComponent';
import { VideoListPageParams } from './VideoListPage';
import { UserCardComponent } from '../components/UserCardComponent';
import { formatCount } from '../api/CommonApi';
import { DynamicSection } from '../components/DynamicSection';

@Component
export struct UserDetailPage {
  @Consume('pageStack') pageStack: NavPathStack;
  // ==== 资源状态 ====
  @State pageParam: UserCard = new UserCard();
  @State isMyself: boolean = false;
  @State userDetail: UserDetailCard = new UserDetailCard(
    this.pageParam.name,
    this.pageParam.headImage,
    this.pageParam.mid,
    this.pageParam.isVip ?? false,
    this.pageParam.level ?? '',
    this.pageParam.desc ?? '',
    '', // sex
    false, // silence
    false, // is_followed
    0, // followings
    0, // followers
    0, // favourites
    0, // video
    0// opus
  ); //默认构造
  // 投递列表状态 + 翻页状态
  @State videoList: VideoCard[] = [];
  @State articleList: ArticleCard[] = [];
  // 独立半模态窗口状态
  @State isSheetOpen: boolean = false;
  @State isSheetLoading: boolean = true;
  @State sheetMode: string = 'following'; // 'following' | 'fans' | 'folders'
  @State sheetTitle: string = '';
  @State sheetContents: Array<FavFolder | UserCard> = [];
  // Sheet 翻页状态（仅关注/粉丝有翻页，收藏夹无）
  private sheetPage: number = 1;
  private sheetHasMore: boolean = true;
  private videoPage: number = 1;
  private articlePage: number = 1;
  private videoHasMore: boolean = true;
  private articleHasMore: boolean = true;
  private videoLoading: boolean = false;
  private articleLoading: boolean = false;
  private videoTotal: number = 0;
  private articleTotal: number = 0;
  private dataLoaded: boolean = false;

  //加载数据的函数
  async loadUserData() {
    // 获取该用户详情
    let detail: UserDetailCard = await getUserDetail(this.pageParam);
    this.userDetail = detail;
    console.info('[UserDetailPage] 用户数据加载完成: name=' + detail.name + ' mid=' + detail.mid);

    // 再加载视频和专栏第一页
    await Promise.all([
      this.loadMoreVideos(),
      this.loadMoreArticles()
    ]);
    this.dataLoaded = true;
  }

  /** 加载下一页视频投稿 */
  async loadMoreVideos() {
    if (this.videoLoading || !this.videoHasMore) {
      return;
    }
    this.videoLoading = true;
    try {
      let result = await getUserVideos(this.pageParam.mid, this.videoPage, 30);
      if (result.videos.length > 0) {
        this.videoList = this.videoList.concat(result.videos);
        if (this.videoList.length > 50) {
          this.videoList = this.videoList.slice(this.videoList.length - 50);
        }
        this.videoTotal = result.total;
        this.videoPage++;
        // 已加载数 >= 总数说明没有更多了
        this.videoHasMore = this.videoList.length < result.total;
        console.info('[UserDetailPage] 视频翻页 ' + (this.videoPage - 1) +
          ' 已加载=' + this.videoList.length + '/' + result.total);
      } else {
        this.videoHasMore = false;
      }
    } catch (e) {
      console.error('[UserDetailPage] 视频翻页异常: ' + String(e));
    }
    this.videoLoading = false;
  }

  /** 加载下一页专栏投稿 */
  async loadMoreArticles() {
    if (this.articleLoading || !this.articleHasMore) {
      return;
    }
    this.articleLoading = true;
    try {
      let result = await getUserArticles(this.pageParam.mid, this.articlePage, 30);
      if (result.articles.length > 0) {
        this.articleList = this.articleList.concat(result.articles);
        if (this.articleList.length > 50) {
          this.articleList = this.articleList.slice(this.articleList.length - 50);
        }
        this.articleTotal = result.total;
        this.articlePage++;
        this.articleHasMore = this.articleList.length < result.total;
        console.info('[UserDetailPage] 专栏翻页 ' + (this.articlePage - 1) +
          ' 已加载=' + this.articleList.length + '/' + result.total);
      } else {
        this.articleHasMore = false;
      }
    } catch (e) {
      console.error('[UserDetailPage] 专栏翻页异常: ' + String(e));
    }
    this.articleLoading = false;
  }

  /** 处理关注/取关按钮 */
  async handleFollowToggle() {
    if (this.isMyself) {
      return;
    }

    let fid: number = this.pageParam.mid;
    let currentlyFollowed: boolean = this.userDetail.is_followed;
    let prompt = this.getUIContext().getPromptAction();

    console.info('[UserDetailPage] handleFollowToggle: mid=' + fid + ' currentlyFollowed=' + currentlyFollowed);

    try {
      let result: ModifyRelationResult;
      if (currentlyFollowed) {
        result = await unfollowUser(fid);
      } else {
        result = await followUser(fid);
      }

      if (result.success) {
        // 切换成功，同步状态
        this.userDetail.is_followed = !currentlyFollowed;
        if (currentlyFollowed) {
          this.userDetail.followers = Math.max(0, this.userDetail.followers - 1);
        } else {
          this.userDetail.followers = this.userDetail.followers + 1;
        }
        console.info('[UserDetailPage] ' + (currentlyFollowed ? '取关' : '关注') + '成功: ' + fid);
      } else {
        // 失败则弹Toast
        prompt.showToast({
          message: result.message || (currentlyFollowed ? '取消失败' : '关注失败'),
          duration: 2000
        });
        console.warn(
          '[UserDetailPage] ' + (currentlyFollowed ? '取关' : '关注') + '失败: code=' + result.code + ' msg=' +
            result.message);
      }
    } catch (e) {
      console.error('[UserDetailPage] handleFollowToggle 异常: ' + String(e));
      prompt.showToast({
        message: '操作失败：' + String(e),
        duration: 2000
      });
    }
  }

  // ========== 关注 / 取关 ==========

  /** 点击关注/粉丝/收藏按钮时统一入口 */
  async handleStatClick(mode: string) {
    this.sheetMode = mode;
    this.sheetContents = [];
    this.sheetPage = 1;
    this.sheetHasMore = true;
    this.isSheetLoading = true;
    this.isSheetOpen = true;

    console.info('[UserDetailPage] 打开Sheet: mode=' + mode);

    try {
      if (mode === 'following') {
        this.sheetTitle = '关注';
        let result = await getUserFollowings(this.pageParam.mid, 1, 50);
        if (result.invisible) {
          this.isSheetOpen = false;
          this.getUIContext().getPromptAction().showToast({
            message: '该用户已设置隐私，关注列表不可见',
            duration: 2000
          });
          return;
        }
        this.sheetContents = result.users;
        this.sheetHasMore = this.sheetContents.length < result.total;
        this.sheetPage = 2;
      } else if (mode === 'fans') {
        this.sheetTitle = '粉丝';
        let result = await getUserFans(this.pageParam.mid, 1, 50);
        if (result.invisible) {
          this.isSheetOpen = false;
          this.getUIContext().getPromptAction().showToast({
            message: '该用户已设置隐私，粉丝列表不可见',
            duration: 2000
          });
          return;
        }
        this.sheetContents = result.users;
        this.sheetHasMore = this.sheetContents.length < result.total;
        this.sheetPage = 2;
      } else if (mode === 'folders') {
        this.sheetTitle = '收藏夹';
        let result = await getUserCreatedFavFolders(this.pageParam.mid);
        // 收藏夹需要补全详细信息 (cover, ctime, media_count)
        for (let f of result.folders) {
          await fillFavFolderDetail(f);
        }
        this.sheetContents = result.folders;
        this.sheetHasMore = false; // 收藏夹没有翻页机制
      }
    } catch (e) {
      console.error('[UserDetailPage] handleStatClick 异常: ' + String(e));
    }

    this.isSheetLoading = false;
  }

  // ========== Sheet 数据加载 ==========

  /** Sheet 内翻页加载更多（仅关注/粉丝有效） */
  async loadMoreSheetData() {
    if (this.isSheetLoading || !this.sheetHasMore || this.sheetMode === 'folders') {
      return;
    }
    this.isSheetLoading = true;
    try {
      if (this.sheetMode === 'following') {
        let result = await getUserFollowings(this.pageParam.mid, this.sheetPage, 50);
        let userList = result.users;
        this.sheetContents = this.sheetContents.concat(userList);
        if (this.sheetContents.length > 50) {
          this.sheetContents = this.sheetContents.slice(this.sheetContents.length - 50);
        }
        this.sheetHasMore = this.sheetContents.length < result.total;
        this.sheetPage++;
        console.info('[UserDetailPage] 关注翻页 ' + (this.sheetPage - 1) +
          ' 已加载=' + this.sheetContents.length + '/' + result.total);
      } else if (this.sheetMode === 'fans') {
        let result = await getUserFans(this.pageParam.mid, this.sheetPage, 50);
        let userList = result.users;
        this.sheetContents = this.sheetContents.concat(userList);
        if (this.sheetContents.length > 50) {
          this.sheetContents = this.sheetContents.slice(this.sheetContents.length - 50);
        }
        this.sheetHasMore = this.sheetContents.length < result.total;
        this.sheetPage++;
        console.info('[UserDetailPage] 粉丝翻页 ' + (this.sheetPage - 1) +
          ' 已加载=' + this.sheetContents.length + '/' + result.total);
      }
    } catch (e) {
      console.error('[UserDetailPage] loadMoreSheetData 异常: ' + String(e));
    }
    this.isSheetLoading = false;
  }

  // 展示用的半模态窗口
  @Builder
  DetailSheetBuilder() {
    Column() {
      // 标题栏
      Text(this.sheetTitle)
        .fontSize(16)
        .fontColor('#EEEEEE')
        .fontWeight(FontWeight.Bold)
        .margin({ top: 16, bottom: 8 })

      if (this.sheetContents.length === 0) {
        Text('暂无内容')
          .fontSize(13)
          .fontColor('#999999')
          .margin({ top: 20 })
          .textAlign(TextAlign.Center)
          .width('80%')
      } else {
        List({ space: 6 }) {
          ForEach(this.sheetContents, (content: (FavFolder | UserCard)) => {
            ListItem() {
              Row() {
                if (content instanceof FavFolder) {
                  FolderCardComponent({ card: content, color: 'rgba(66,66,66,0.4)' })
                } else {
                  UserCardComponent({ card: content, baseFontSize: 14, color: 'rgba(66,66,66,0.4)' })
                }
              }
              .width('100%')
              .borderRadius(8)
              .backgroundColor('rgba(66,66,66,0.4)')
            }
          })

          // 底部加载状态（仅关注/粉丝展示）
          if (this.sheetMode !== 'folders') {
            ListItem() {
              if (this.isSheetLoading) {
                Row() {
                  LoadingProgress()
                    .width(18).height(18).color('#FB7299')
                  Text('  加载中...')
                    .fontSize(12).fontColor('#999999')
                    .margin({ left: 6 })
                }
                .justifyContent(FlexAlign.Center)
                .padding(12)
                .width('100%')
              } else if (!this.sheetHasMore && this.sheetContents.length > 0) {
                Text('— 已加载全部 ' + this.sheetContents.length + ' 项 —')
                  .fontSize(12)
                  .fontColor('#555555')
                  .padding(12)
                  .width('100%')
                  .textAlign(TextAlign.Center)
              }
            }
          }
          ListItem() {
            Column().height(40)
          }
        }
        .fadingEdge(true, { fadingEdgeLength: LengthMetrics.vp(10) })
        .width('100%')
        .padding({ left: 14, right: 14 })
        .layoutWeight(1)
        .onReachEnd(() => {
          // 仅关注和粉丝有翻页，收藏夹无需
          if (this.sheetMode !== 'folders') {
            this.loadMoreSheetData();
          }
        })
        .focusable(true)
        .focusOnTouch(true)
        .defaultFocus(true)
      }
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Center)
  }

  build() {
    NavDestination() {
      ArcSwiper() {
        //首页
        Column() {
          List({ space: 10 }) {
            // 占位空白，防止被系统返回按钮遮挡
            ListItem() {
              Column().height(40)
            }

            // 头像（大）
            ListItem() {
              Column() {
                Image(this.userDetail.headImage)
                  .width(80)
                  .height(80)
                  .borderRadius(40)
                  .objectFit(ImageFit.Cover)
                  .alt($r('app.media.avatar_alt'))
                  .onClick(() => {
                    this.pageStack.pushPath({ name: 'ImageViewer', param: this.userDetail.headImage })
                  })
              }
              .width('100%')
              .alignItems(HorizontalAlign.Center)
              .padding({ top: 16 })
            }

            // 用户名 + 等级
            ListItem() {
              Column() {
                Text(this.userDetail.name)
                  .fontSize(22)
                  .fontColor(this.userDetail.isVip ? '#FB7299' : '#FFFFFF')
                  .fontWeight(FontWeight.Bold)
                Image($r("app.media.level_" + (this.userDetail.level || '0')))
                  .width(26)
                  .height(26)
                  .margin({ left: 6 })
                  .objectFit(ImageFit.Contain)
              }
              .width('100%')
              .justifyContent(FlexAlign.Center)
              .padding({ top: 8 })
            }

            // 个性签名
            ListItem() {
              Text(this.userDetail.desc)
                .fontSize(13)
                .fontColor('#999999')
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.MARQUEE })
                .textAlign(TextAlign.Center)
                .width('100%')
                .alignSelf(ItemAlign.Center)
                .padding({ top: 4 })
            }

            // 关注按钮（isMyself=true时不显示）
            if (!this.isMyself) {
              ListItem() {
                Button() {
                  Text(this.userDetail.is_followed ? '已关注' : '关注')
                    .fontSize(14)
                    .fontColor('#FFFFFF')
                }
                .width('100%')
                .height(38)
                .backgroundColor(this.userDetail.is_followed ? '#555555' : '#FB7299')
                .borderRadius(20)
                .margin({ top: 12 })
                .alignSelf(ItemAlign.Center)
                .onClick(() => {
                  this.handleFollowToggle();
                })
              }
            }

            // 关注
            ListItem() {
              Row() {
                Text(formatCount(this.userDetail.followings))
                  .fontSize(20)
                  .fontColor('#FFFFFF')
                  .fontWeight(FontWeight.Bold)
                Text('  关注')
                  .fontSize(14)
                  .fontColor('#999999')
                  .margin({ left: 4 })
              }
              .backgroundColor('rgba(22,22,22,0.8)')
              .borderRadius(10)
              .justifyContent(FlexAlign.SpaceBetween)
              .width(175)
              .padding({
                left: 15,
                right: 15,
                top: 6,
                bottom: 6
              })
              .margin({ left: 15, right: 15 })
              .onClick(() => {
                this.handleStatClick('following');
              })
            }

            // 粉丝
            ListItem() {
              Row() {
                Text(formatCount(this.userDetail.followers))
                  .fontSize(20)
                  .fontColor('#FFFFFF')
                  .fontWeight(FontWeight.Bold)
                Text('  粉丝')
                  .fontSize(14)
                  .fontColor('#999999')
                  .margin({ left: 4 })
              }
              .backgroundColor('rgba(22,22,22,0.8)')
              .borderRadius(10)
              .width(175)
              .justifyContent(FlexAlign.SpaceBetween)
              .padding({
                left: 15,
                right: 15,
                top: 6,
                bottom: 6
              })
              .margin({ left: 15, right: 15 })
              .onClick(() => {
                this.handleStatClick('fans');
              })
            }

            // 收藏
            ListItem() {
              Row() {
                Text(this.userDetail.favourites.toString())
                  .fontSize(20)
                  .fontColor('#FFFFFF')
                  .fontWeight(FontWeight.Bold)
                Text('  收藏')
                  .fontSize(14)
                  .fontColor('#999999')
                  .margin({ left: 4 })
              }
              .backgroundColor('rgba(22,22,22,0.8)')
              .borderRadius(10)
              .width(175)
              .justifyContent(FlexAlign.SpaceBetween)
              .padding({
                left: 15,
                right: 15,
                top: 6,
                bottom: 6
              })
              .margin({ left: 15, right: 15 })
              .onClick(() => {
                this.handleStatClick('folders');
              })
            }

            // 历史记录（isMySelf=true时展示）
            if (this.isMyself) {
              ListItem() {
                Row() {
                  SymbolGlyph($r("sys.symbol.clock")).fontSize(15).fontColor(['white'])
                  Text(' 历史记录').fontSize(15)
                }
                .backgroundColor('rgba(22,22,22,0.8)')
                .borderRadius(10)
                .justifyContent(FlexAlign.Center)
                .width(175)
                .padding({
                  left: 15,
                  right: 15,
                  top: 6,
                  bottom: 6
                })
                .margin({ left: 15, right: 15 })
                .onClick(() => {
                  let listParams: VideoListPageParams = new VideoListPageParams('history', '历史记录');
                  this.pageStack.pushPath({ name: 'VideoListPage', param: listParams });
                })
              }
            }

            // 稍后再看
            if (this.isMyself) {
              ListItem() {
                Row() {
                  SymbolGlyph($r("sys.symbol.arrow_counterclockwise_clock")).fontSize(15).fontColor(['white'])
                  Text(' 稍后再看').fontSize(15)
                }
                .backgroundColor('rgba(22,22,22,0.8)')
                .borderRadius(10)
                .justifyContent(FlexAlign.Center)
                .width(175)
                .padding({
                  left: 15,
                  right: 15,
                  top: 6,
                  bottom: 6
                })
                .margin({ left: 15, right: 15 })
                .onClick(() => {
                  let listParams: VideoListPageParams = new VideoListPageParams('watchLater', '稍后再看');
                  this.pageStack.pushPath({ name: 'VideoListPage', param: listParams });
                })
              }
            }

            ListItem() {
              Column().height(40)
            }
          }
          .padding({ left: 14, right: 14 })
          .width('100%')
          .height('100%')
          .focusable(true)
          .focusOnTouch(true)
          .defaultFocus(true)
        }

        Column() {
          DynamicSection({ mid: this.userDetail.mid })
        }

        //视频投稿页
        Column() {
          List({ space: 10 }) {
            // 占位空白，防止被系统返回按钮遮挡
            ListItem() {
              Column().height(40)
            }

            ForEach(this.videoList, (item: VideoCard) => {
              ListItem() {
                VideoCardComponent({ card: item })
              }
            }, (item: VideoCard) => item.bvid || item.aid.toString())

            // 底部加载状态
            ListItem() {
              Column() {
                if (this.videoLoading) {
                  Row() {
                    LoadingProgress()
                      .width(18)
                      .height(18)
                      .color('#FB7299')
                    Text(' 加载中...')
                      .fontSize(12)
                      .fontColor('#999999')
                      .margin({ left: 6 })
                  }
                  .justifyContent(FlexAlign.Center)
                  .padding(12)
                } else if (!this.videoHasMore && this.videoList.length > 0) {
                  Text('- 已加载全部 ' + this.videoTotal + ' 个视频 -')
                    .fontSize(12)
                    .fontColor('#555555')
                    .padding(12)
                    .alignSelf(ItemAlign.Center)
                } else if (this.videoList.length === 0 && this.dataLoaded) {
                  Text('暂无视频投稿')
                    .fontSize(14)
                    .fontColor('#666666')
                    .padding(30)
                    .alignSelf(ItemAlign.Center)
                }
              }
              .width('100%')
              .alignItems(HorizontalAlign.Center)
            }

            ListItem() {
              Column().height(40)
            }
          }
          .width('100%')
          .height('100%')
          .padding({ left: 14, right: 14 })
          .onReachEnd(() => {
            this.loadMoreVideos();
          })
          .focusable(true)
          .focusOnTouch(true)
          .defaultFocus(true)
        }

        //专栏投稿页
        Column() {
          List({ space: 10 }) {
            // 占位空白，防止被系统返回按钮遮挡
            ListItem() {
              Column().height(40)
            }

            ForEach(this.articleList, (item: ArticleCard) => {
              ListItem() {
                ArticleCardComponent({ card: item })
              }
            }, (item: ArticleCard) => item.cvid.toString())

            // 底部加载状态
            ListItem() {
              Column() {
                if (this.articleLoading) {
                  Row() {
                    LoadingProgress()
                      .width(18)
                      .height(18)
                      .color('#FB7299')
                    Text(' 加载中...')
                      .fontSize(12)
                      .fontColor('#999999')
                      .margin({ left: 6 })
                  }
                  .justifyContent(FlexAlign.Center)
                  .padding(12)
                } else if (!this.articleHasMore && this.articleList.length > 0) {
                  Text('- 已加载全部 ' + this.articleTotal + ' 篇专栏 -')
                    .fontSize(12)
                    .fontColor('#555555')
                    .padding(12)
                    .alignSelf(ItemAlign.Center)
                } else if (this.articleList.length === 0 && this.dataLoaded) {
                  Text('暂无专栏投稿')
                    .fontSize(14)
                    .fontColor('#666666')
                    .padding(30)
                    .alignSelf(ItemAlign.Center)
                }
              }
              .width('100%')
              .alignItems(HorizontalAlign.Center)
            }

            ListItem() {
              Column().height(40)
            }
          }
          .width('100%')
          .height('100%')
          .padding({ left: 14, right: 14 })
          .onReachEnd(() => {
            this.loadMoreArticles();
          })
          .focusable(true)
          .focusOnTouch(true)
          .defaultFocus(true)
        }
      }
      .indicator(false)
      .height('100%')
      .width('100%')

      //注意这里有额外的返回按钮，放在List以外的第一个元素要为空占位防止遮挡
      Row() {
        if (this.isMyself) {
          Row() {
            Circle().width(8).height(8).fill('#FB7299')
            Text('个人').fontSize(16).fontColor('#EEEEEE')
              .fontWeight(FontWeight.Medium).margin({ left: 4 })
          }
          .onClick(() => {
            this.showNavMenu();
          })
          .justifyContent(FlexAlign.Center)
          .width('100%')
        } else {
          Text('<')
            .fontSize(18)
            .fontColor('#FB7299')
            .width(24)
            .textAlign(TextAlign.Center)
            .onClick(() => {
              if (this.pageStack) {
                this.pageStack.pop();
              }
            })
          Text('返回').fontSize(15).fontColor('#EEEEEE').margin({ left: 4 }).onClick(() => {
            if (this.pageStack) {
              this.pageStack.pop();
            }
          })
        }
      }
      .width('30%')
      .position({ x: 80, y: 8 })
      .padding({ left: 2, top: 8, bottom: 8 })
      .borderRadius(10)
      .backgroundColor('rgba(22,22,22,0.6)')
    }
    .bindSheet($$this.isSheetOpen, this.DetailSheetBuilder(), {
        height: SheetSize.LARGE ,
        backgroundColor: 'rgba(28,28,30,0.45)',
        blurStyle: BlurStyle.BACKGROUND_THIN})
    .height('100%')
    .width('100%')
    .backgroundImage($r("app.media.oobe"))
    .hideBackButton(true)
    .hideTitleBar(true)
    .onReady((context: NavDestinationContext) => {
      let incoming: UserCard = context.pathInfo.param as UserCard;
      if (incoming && (incoming.mid > 0)) {
        this.pageParam = incoming;
        if (incoming.mid == AppStorage.get<number>("mid")) {
          this.isMyself = true;
        }
      }
      //调用加载数据的函数
      this.loadUserData();
    })
    .onHidden(() => {
      this.isSheetOpen = false;
    })
  }

  private showNavMenu(): void {
    this.pageStack.pushPath({ name: 'Menu' });
  }
}
