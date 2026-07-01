/**
 * 视频详情页
 */

import { LengthMetrics } from '@kit.ArkUI';
import { UserCard } from '../../model/UserCard';
import { VideoCard } from '../../model/ContentCard';
import { VideoPage } from '../../model/VideoPage';
import { UserCardComponent } from '../UserCardComponent';
import { likeVideo, addCoin, addVideoToFavFolders } from '../../api/VideoActionApi';
import { getUserCreatedFavFolders } from '../../api/UserApi';
import { FavFolder } from '../../model/FavFolder';
import { addToView } from '../../api/HistoryApi';
import { av2bv, formatCount } from '../../api/CommonApi';
import { getVideoQualities, VideoQuality } from '../../api/VideoDetailApi';

/** bindMenu 菜单项 */
interface MenuAction {
  value: string;
  action: () => void;
}

@Component
export struct VideoDetailArc {
  // ===== 从父页面传入的数据 =====
  @Link like: number; // 总点赞数（@Link 双向绑定，支持本地增减）
  @Link coin: number; // 总投币数（同上）
  @Link isLiked: boolean; // 当前用户是否已点赞
  @Link coinsGiven: number; // 当前用户已投币数 0/1/2
  @Link isFavoured: boolean; // 当前用户是否已收藏
  @Prop pageParam: VideoCard = new VideoCard();
  @Prop up: UserCard = new UserCard();
  @Prop staff: Array<UserCard> = [];
  @Prop staffRoles: Array<string> = [];
  @Prop danmakus: number = 0;
  @Prop time: number = 0;
  @Prop duration: number = 0;
  @Prop tags: Array<string> = [];
  @Prop desc: string = '';
  @Prop favorite: number = 0;
  @Prop share: number = 0;
  @Prop @Watch('onPagesChanged') pages: Array<VideoPage> = [new VideoPage(0)];
  @Prop bv: string = "";
  @Consume('pageStack') pageStack: NavPathStack;
  // ===== 内部状态 =====
  @State descExpanded: boolean = false;
  @State currentPage: number = 1;
  @State showFavSheet: boolean = false;
  @State favFolders: FavFolder[] = [];
  @State selectedFolderMlids: number[] = [];
  @State previousFolderMlids: number[] = []; // 打开面板时的原始选中（用来计算增删）
  @State favLoading: boolean = false;
  // ===== 清晰度 =====
  @State qualities: VideoQuality[] = [];
  @State selectedQn: number = 80;

  onPagesChanged(): void {
    if (this.pageParam.aid > 0 && this.pages && this.pages.length > 0) {
      this.loadQualities();
    }
  }

  // ===== 工具方法 =====

  @Builder
  favFolderSheetBuilder() {
    Column() {
      Text('选择收藏夹')
        .fontSize(15).fontColor('#FFFFFF').fontWeight(FontWeight.Bold)
        .margin({ top: 14, bottom: 10 })

      if (this.favLoading) {
        LoadingProgress().width(28).height(28).margin({ top: 24 })
      } else if (this.favFolders.length === 0) {
        Text('暂未创建收藏夹\n请先在网页版或手机版创建')
          .fontSize(13)
          .fontColor('#999999')
          .margin({ top: 20 })
          .textAlign(TextAlign.Center)
          .width('80%')
      } else {
        Scroll() {
          Column({ space: 6 }) {
            ForEach(this.favFolders, (folder: FavFolder) => {
              Row() {
                // 选中状态指示圈
                // Text(this.selectedFolderMlids.indexOf(folder.mlid) >= 0 ? '󰇚' : '󰁵')
                SymbolGlyph(
                  this.selectedFolderMlids.indexOf(folder.mlid) >= 0 ? $r("sys.symbol.checkmark_square_fill") :
                    $r("sys.symbol.square"))
                  .fontSize(18)
                  .fontColor([this.selectedFolderMlids.indexOf(folder.mlid) >= 0 ? '#FB7299' : '#666666'])
                  .margin({ right: 8 })

                Text(folder.name)
                  .fontSize(14)
                  .fontColor(this.selectedFolderMlids.indexOf(folder.mlid) >= 0 ? '#FB7299' : '#DDDDDD')
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)

                Text('' + (folder.media_count > 0 ? folder.media_count : ''))
                  .fontSize(11).fontColor('#888888')
              }
              .width('85%')
              .padding({
                left: 12,
                right: 12,
                top: 10,
                bottom: 10
              })
              .borderRadius(8)
              .backgroundColor('rgba(66,66,66,0.4)')
              .onClick(() => {
                let idx: number = this.selectedFolderMlids.indexOf(folder.mlid);
                if (idx >= 0) {
                  // 取消选中
                  let arr: number[] = [];
                  for (let i: number = 0; i < this.selectedFolderMlids.length; i++) {
                    if (this.selectedFolderMlids[i] !== folder.mlid) {
                      arr.push(this.selectedFolderMlids[i]);
                    }
                  }
                  this.selectedFolderMlids = arr;
                } else {
                  // 选中
                  let arr: number[] = [];
                  for (let i: number = 0; i < this.selectedFolderMlids.length; i++) {
                    arr.push(this.selectedFolderMlids[i]);
                  }
                  arr.push(folder.mlid);
                  this.selectedFolderMlids = arr;
                }
              })
            }, (folder: FavFolder) => String(folder.mlid))
          }
          .width('100%')
          .padding({ left: 8, right: 8 })
        }
        .scrollable(ScrollDirection.Vertical)
        .scrollBar(BarState.Off)
        .fadingEdge(true, { fadingEdgeLength: LengthMetrics.vp(15) })
        .layoutWeight(1)
      }

      // 确认按钮
      Button(this.selectedFolderMlids.length > 0 ? '确认' : '取消收藏')
        .width('50%')
        .height(36)
        .backgroundColor(this.selectedFolderMlids.length > 0 ? '#FB7299' : '#555555')
        .borderRadius(18)
        .fontColor('#FFFFFF')
        .fontSize(14)
        .margin({ top: 8, bottom: 14 })
        .enabled(!this.favLoading)
        .onClick(() => {
          this.onConfirmFav();
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#1C1C1E')
    .alignItems(HorizontalAlign.Center)
  }

  // ===== 分P Radio 构建 =====
  @Builder
  pageRadioItem(page: VideoPage, index: number) {
    Row() {
      Radio({ value: String(page.page), group: 'videoPage' })
        .checked(this.currentPage === page.page)
        .onChange((isChecked: boolean) => {
          if (isChecked) {
            this.currentPage = page.page;
            console.info('[VideoDetail] 切换分P:', page.page, page.part);
          }
        })

      Column() {
        Text('P' + page.page).fontSize(11).fontColor('#FB7299').fontWeight(FontWeight.Medium)
        Text(page.part)
          .fontSize(10)
          .fontColor('#999999')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.MARQUEE })
          .width(60)
          .textAlign(TextAlign.Center)
      }
      .margin({ left: 2, right: 10 })
      .alignItems(HorizontalAlign.Center)
    }
    .padding({
      top: 4,
      bottom: 4,
      left: 2,
      right: 2
    })
  }

  // ===== 构建 =====
  build() {
    List({ space: 14 }) {
      // ── 1. 返回按钮 ──
      /*
      ListItem() {
        Row() {
          Text('󰃚').fontSize(18).fontColor('#FB7299').width(24).textAlign(TextAlign.Center)
          Text('返回').fontSize(15).fontColor('#EEEEEE').margin({ left: 6 })
        }
        .width('90%')
        .padding({ left: 12, top: 8, bottom: 8 })
        .borderRadius(10)
        .backgroundColor('rgba(22,22,22,0.6)')
        .onClick(() => { if (this.pageStack) this.pageStack.pop(); })
      }
      * */
      ListItem() {
        Column().height('14%')
      }

      // ── 2. 封面大图 ──
      ListItem() {
        Column() {
          Image(this.pageParam.cover)
            .width('100%')
            .aspectRatio(16 / 9)
            .borderRadius(12)
            .objectFit(ImageFit.Cover)
            .alt($r('app.media.placeholder'))
            .onClick(() => {
              this.pageStack.pushPath({ name: 'ImageViewer', param: this.pageParam.cover });
            })
        }
        .width('92%')
      }

      // ── 3. 标题 ──
      ListItem() {
        Text(this.pageParam.title)
          .fontSize(16)
          .fontColor('#FFFFFF')
          .fontWeight(FontWeight.Bold)
          .lineHeight(22)
          .width('92%')
          .textAlign(TextAlign.Start)
      }

      // ── 4. 分P选择器 ──
      if (this.pages.length > 1) {
        ListItem() {
          Column() {
            Text('分P选择')
              .fontSize(11)
              .fontColor('#888888')
              .width('92%')
              .textAlign(TextAlign.Start)
              .margin({ bottom: 6 })
            Scroll() {
              Row() {
                ForEach(this.pages, (page: VideoPage, index: number) => {
                  this.pageRadioItem(page, index)
                }, (page: VideoPage) => String(page.cid))
              }
              .alignItems(VerticalAlign.Center)
            }
            .scrollable(ScrollDirection.Horizontal)
            .scrollBar(BarState.Off)
            .width('100%')
          }
          .width('92%').padding(6).backgroundColor('rgba(22,22,22,0.4)').borderRadius(10)
        }
      }

      // ── 5. 播放按钮 ──
      ListItem() {
        Row() {
          SymbolGlyph($r("sys.symbol.play_round_rectangle_fill"))
            .fontSize(18)
            .fontColor(['#FFFFFF'])
            .margin({ right: 6 })
          Text('播放视频').fontSize(17).fontColor('#FFFFFF').fontWeight(FontWeight.Bold)
        }
        .width('88%')
        .height(48)
        .backgroundColor('#FB7299')
        .borderRadius(24)
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          let cid: number = this.getCurrentCid();
          if (cid <= 0 && this.pages.length > 0) {
            cid = this.pages[0].cid;
          }
          console.info('[VideoDetail] 跳转播放页, aid:', this.pageParam.aid,
            'cid:', cid, 'qn:', this.selectedQn);
          let playParam: Record<string, Object> = {
            'videoCard': this.pageParam,
            'cid': cid,
            'qn': this.selectedQn
          };
          this.pageStack.pushPath({
            name: 'VideoPlayer',
            param: playParam
          });
        })
      }

      // ── 5b. 清晰度选择（加载完成后显示） ──
      if (this.qualities.length > 0) {
        ListItem() {
          Column() {
            Row() {
              Text('画质').fontSize(11).fontColor('#888888').margin({ right: 8 })
              Scroll() {
                Row({ space: 6 }) {
                  ForEach(this.qualities, (item: VideoQuality) => {
                    if (item.qn !== 120 && item.qn !== 116) {
                      Text(item.name)
                        .fontSize(12)
                        .fontColor(item.qn === this.selectedQn ? '#FB7299' : '#CCCCCC')
                        .fontWeight(item.qn === this.selectedQn ? FontWeight.Bold : FontWeight.Regular)
                        .padding({
                          left: 10,
                          right: 10,
                          top: 4,
                          bottom: 4
                        })
                        .borderRadius(12)
                        .backgroundColor(item.qn === this.selectedQn
                          ? 'rgba(251,114,153,0.15)'
                          : 'rgba(66,66,66,0.4)')
                        .onClick(() => {
                          this.selectedQn = item.qn;
                          console.info('[VideoDetail] 切换清晰度:', item.name, 'qn=' + item.qn);
                        })
                    }
                  }, (item: VideoQuality) => String(item.qn))
                }
              }
              .scrollable(ScrollDirection.Horizontal)
              .scrollBar(BarState.Off)
              .layoutWeight(1)
            }
            .width('100%')
            .padding({ top: 6, bottom: 2 })
          }
          .width('88%')
          .alignItems(HorizontalAlign.Start)
        }
      }

      // ── 6. 统计信息 ──
      ListItem() {
        Column() {
          Row() {
            Row() {
              SymbolGlyph($r("sys.symbol.play_circle_fill")).fontSize(12).fontColor(['#999999'])
              Text(formatCount(Number(this.pageParam.formatedView))).fontSize(12)
                .fontColor('#CCCCCC').margin({ left: 3 })
            }.margin({ right: 16 })

            Row() {
              SymbolGlyph($r("sys.symbol.sort")).fontSize(12).fontColor(['#999999'])
              Text(formatCount(this.danmakus)).fontSize(12)
                .fontColor('#CCCCCC').margin({ left: 3 })
            }
          }.width('100%').margin({ bottom: 6 })

          Row() {
            Row() {
              SymbolGlyph($r("sys.symbol.clock")).fontSize(12).fontColor(['#999999'])
              Text(this.formatPublishTime(this.time)).fontSize(12)
                .fontColor('#CCCCCC').margin({ left: 3 })
            }.margin({ right: 16 })

            Row() {
              SymbolGlyph($r("sys.symbol.arrow_counterclockwise_clock")).fontSize(12).fontColor(['#999999'])
              Text(this.formatDuration(this.duration)).fontSize(12)
                .fontColor('#CCCCCC').margin({ left: 3 })
            }
          }.width('100%').margin({ bottom: 6 })
        }
        .width('92%').alignItems(HorizontalAlign.Start)
      }

      // ── 7. 视频标签 ──
      ListItem() {
        Scroll() {
          Text() {
            ForEach(this.tags, (tag: string, index: number) => {
              Span(tag).fontSize(13).fontColor('#FB7299')
                .padding({
                  left: 4,
                  right: 4,
                  top: 2,
                  bottom: 2
                })
                .onClick(() => {
                  console.info('[VideoDetail] 点击标签:', tag);
                  this.pageStack.pushPath({ name: 'SearchResultPage', param: tag });
                })
              if (index < this.tags.length - 1) {
                Span(' / ').fontSize(13).fontColor('#555555')
              }
            }, (tag: string) => tag)
          }
          .width('100%').textAlign(TextAlign.Center)
        }
        .width('92%')
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
      }

      // ── 8. 简介 ──
      ListItem() {
        Column() {
          Text(this.desc)
            .fontSize(13)
            .fontColor('#BBBBBB')
            .lineHeight(18)
            .maxLines(this.descExpanded ? 100 : 1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
          Text(this.descExpanded ? '↑ 收起' : '↓ 展开').fontSize(11)
            .fontColor('#FB7299').margin({ top: 4 })
        }
        .width('92%')
        .onClick(() => {
          this.descExpanded = !this.descExpanded;
        })
      }

      // ── 9. UP主卡片 ──
      if (this.staff.length <= 0) {
        ListItem() {
          UserCardComponent({ card: this.up, extraInfo: 'UP主·投稿视频', baseFontSize: 14 }).width('92%')
        }
      }

      // ── 10. 合作成员列表 ──
      if (this.staff.length > 0) {
        ListItem() {
          Column() {
            Text('创作者团队')
              .fontSize(11)
              .fontColor('#888888')
              .width('92%')
              .textAlign(TextAlign.Start)
              .margin({ bottom: 4, top: 2 })
          }
          .width('92%')
        }

        ForEach(this.staff, (member: UserCard, index: number) => {
          ListItem() {
            UserCardComponent({
              card: member,
              extraInfo: index < this.staffRoles.length ? this.staffRoles[index] : '合作者',
              baseFontSize: 14
            }).width('92%')
          }
        }, (member: UserCard) => String(member.mid))
      }

      // ── 11. 点赞 / 投币 / 收藏 ──
      ListItem() {
        Row() {
          // 点赞
          Column() {
            SymbolGlyph($r("sys.symbol.hand_thumbsup_fill"))
              .fontSize(28)
              .fontColor([this.isLiked ? '#FB7299' : '#BBBBBB'])

            Text(formatCount(this.like))
              .fontSize(11)
              .fontColor(this.isLiked ? '#FB7299' : '#999999')
              .margin({ top: 3 })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Center)
          .onClick(() => {
            this.onLikeClick();
          })

          // 投币
          Column() {
            SymbolGlyph($r("sys.symbol.smallcircle_filled_circle"))
              .fontSize(28)
              .fontColor([this.coinsGiven > 0 ? '#FB7299' : '#BBBBBB'])

            Text(formatCount(this.coin))
              .fontSize(11)
              .fontColor(this.coinsGiven > 0 ? '#FB7299' : '#999999')
              .margin({ top: 3 })

            // 投币进度指示（小点，空心→实心）
            Row() {
              Circle().width(5).height(5)
                .fill(this.coinsGiven >= 1 ? '#FB7299' : '#555555')
                .margin({ right: 3 })
              Circle().width(5).height(5)
                .fill(this.coinsGiven >= 2 ? '#FB7299' : '#555555')
            }
            .margin({ top: 2 })
            .justifyContent(FlexAlign.Center)
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Center)
          .onClick(() => {
            this.onCoinClick();
          })

          // 收藏
          Column() {
            SymbolGlyph($r("sys.symbol.star"))
              .fontSize(28)
              .fontColor([this.isFavoured ? '#FB7299' : '#BBBBBB'])

            Text(formatCount(this.favorite))
              .fontSize(11)
              .fontColor(this.isFavoured ? '#FB7299' : '#999999')
              .margin({ top: 3 })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Center)
          .onClick(() => {
            this.onFavClick();
          })
          .bindSheet($$this.showFavSheet, this.favFolderSheetBuilder(), { height: SheetSize.LARGE })
        }
        .width('92%')
        .padding({ top: 12, bottom: 12 })
        .backgroundColor('rgba(22,22,22,0.5)')
        .borderRadius(12)
      }

      // ── 12. 更多按钮 ──
      ListItem() {
        Row() {
          Text('∷ 更多').fontSize(15).fontColor('#999999')
        }
        .width('88%')
        .height(42)
        .backgroundColor('rgba(22,22,22,0.6)')
        .borderRadius(21)
        .justifyContent(FlexAlign.Center)
        .bindMenu(new Array<MenuAction>(
          {
            value: '缓存', action: () => {
            console.info('[More] 缓存');
          }
          },
          {
            value: '流转', action: () => {
            this.pageStack.pushPath({ name: 'QrCode', param: 'https://www.bilibili.com/video/' + this.bv });
          }
          },
          {
            value: '稍后再看', action: async () => {
            let aid: number = this.pageParam.aid;
            if (aid <= 0) {
              this.toast('视频ID无效');
              return;
            }
            let res = await addToView(aid);
            if (res.success) {
              this.toast('已加入稍后再看');
            } else {
              this.toast(res.message || '加入失败');
            }
          }
          }
        ))
      }

      ListItem() {
        Column().height('14%')
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: '7.5%' })
  }

  private formatPublishTime(ts: number): string {
    const d = new Date(ts * 1000);
    const y = d.getFullYear();
    const mo = String(d.getMonth() + 1).padStart(2, '0');
    const dd = String(d.getDate()).padStart(2, '0');
    const h = String(d.getHours()).padStart(2, '0');
    const mi = String(d.getMinutes()).padStart(2, '0');
    const s = String(d.getSeconds()).padStart(2, '0');
    return `${y}/${mo}/${dd} ${h}:${mi}:${s}`;
  }

  private formatDuration(sec: number): string {
    const h = Math.floor(sec / 3600);
    const m = Math.floor((sec % 3600) / 60);
    const s = sec % 60;
    if (h > 0) {
      return `${h}:${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`;
    }
    return `${m}:${String(s).padStart(2, '0')}`;
  }

  // ===== 工具：获取当前分P的 cid =====
  private getCurrentCid(): number {
    if (!this.pages || !Array.isArray(this.pages) || this.pages.length === 0) {
      console.warn('[VideoDetail] pages 无效，返回默认 cid=0');
      return 0; // 或返回你预设的兜底 cid
    }
    for (let i: number = 0; i < this.pages.length; i++) {
      if (this.pages[i].page === this.currentPage) {
        return this.pages[i].cid;
      }
    }
    return this.pages[0].cid;
  }

  // ===== 加载清晰度列表 =====
  private async loadQualities(): Promise<void> {
    let aid: number = this.pageParam.aid;
    let cid: number = this.getCurrentCid();
    /*
    if (cid <= 0) {
      console.warn('[VideoDetail] cid 不可用，跳过清晰度加载');
      return;
    }
    * */
    let bvid: string = this.pageParam.bvid;
    if (!bvid) {
      bvid = av2bv(aid);
    }
    try {
      let list: VideoQuality[] = await getVideoQualities(bvid, cid);
      if (list.length > 0) {
        this.qualities = list;
        // 默认选第一个（最高清晰度）
        this.selectedQn = Math.min(list[0].qn, 80);
        console.info('[VideoDetail] 清晰度列表加载完成: ' + list.length + ' 项');
        for (let i: number = 0; i < list.length; i++) {
          console.info(
            '  [' + i + '] name=' + list[i].name + ' qn=' + list[i].qn);
        }
      }
    } catch (e) {
      console.warn('[VideoDetail] 加载清晰度列表失败:', String(e));
    }
  }

  // ===== Toast 快捷方法 =====
  private toast(msg: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: msg });
    } catch (e) {
      console.warn('[VideoDetail] Toast 失败:', String(e));
    }
  }

  // ===== 点赞/取消点赞 =====
  private async onLikeClick(): Promise<void> {
    let aid: number = this.pageParam.aid;
    if (!aid || aid <= 0) {
      this.toast('稿件信息不完整');
      return;
    }

    // 乐观更新
    let prevLiked: boolean = this.isLiked;
    let prevLikeCount: number = this.like;
    this.isLiked = !this.isLiked;
    this.like += this.isLiked ? 1 : -1;

    let result = await likeVideo(aid, this.isLiked ? 1 : 2);
    if (result.success) {
      this.toast(result.message);
    } else {
      // 回滚
      this.isLiked = prevLiked;
      this.like = prevLikeCount;
      this.toast(result.message);
    }
  }

  // ===== 投币（每次 1 枚，最多 2 枚） =====
  private async onCoinClick(): Promise<void> {
    let aid: number = this.pageParam.aid;
    if (!aid || aid <= 0) {
      this.toast('稿件信息不完整');
      return;
    }
    if (this.coinsGiven >= 2) {
      this.toast('该视频已投满 2 枚硬币');
      return;
    }

    // 乐观更新
    let prevCoin: number = this.coinsGiven;
    let prevCoinTotal: number = this.coin;
    this.coinsGiven++;
    this.coin++;

    let result = await addCoin(aid, 1);
    if (result.success) {
      this.toast(result.message);
    } else {
      this.coinsGiven = prevCoin;
      this.coin = prevCoinTotal;
      this.toast(result.message);
    }
  }

  // ===== 收藏逻辑 =====
  private async onFavClick(): Promise<void> {
    let aid: number = this.pageParam.aid;
    if (!aid || aid <= 0) {
      this.toast('稿件信息不完整');
      return;
    }

    this.favLoading = true;
    try {
      // 1. 获取当前登录账户的 mid
      let myMid = AppStorage.get<number>('mid');
      if (myMid === null || myMid === 0 || myMid === undefined) {
        this.toast('请先登录');
        this.favLoading = false;
        return;
      }

      // 2. 单次请求：传入 rid 获取全部收藏夹及各自的 fav_state
      let result = await getUserCreatedFavFolders(myMid, 2, aid);
      this.favFolders = result.folders;

      // 3. 根据 fav_state 预选中已加入的收藏夹
      let preSelected: number[] = [];
      for (let i: number = 0; i < result.folders.length; i++) {
        if (result.folders[i].fav_state === 1) {
          preSelected.push(result.folders[i].mlid);
        }
      }
      this.selectedFolderMlids = preSelected;
      this.previousFolderMlids = preSelected;
      console.info('[VideoDetail] 获取到 ' + result.folders.length + ' 个收藏夹，预选中 ' + preSelected.length + ' 个');

      this.favLoading = false;

      // 4. 打开半模态选择器
      this.showFavSheet = true;
    } catch (e) {
      this.favLoading = false;
      this.toast('获取收藏夹失败');
      console.error('[VideoDetail] 收藏夹加载失败:', String(e));
    }
  }

  private async onConfirmFav(): Promise<void> {
    let aid: number = this.pageParam.aid;
    if (!aid || aid <= 0) {
      this.toast('稿件信息不完整');
      return;
    }

    // 计算 diff：要新增和要删除的收藏夹
    let addFolders: FavFolder[] = [];
    let delFolders: FavFolder[] = [];

    for (let i: number = 0; i < this.favFolders.length; i++) {
      let mlid: number = this.favFolders[i].mlid;
      let inCurrent: boolean = this.selectedFolderMlids.indexOf(mlid) >= 0;
      let inPrevious: boolean = this.previousFolderMlids.indexOf(mlid) >= 0;

      if (inCurrent && !inPrevious) {
        addFolders.push(this.favFolders[i]);
      } else if (!inCurrent && inPrevious) {
        delFolders.push(this.favFolders[i]);
      }
    }

    // 如果没有变化，直接关闭面板
    if (addFolders.length === 0 && delFolders.length === 0) {
      this.showFavSheet = false;
      return;
    }

    // 乐观更新：根据结果更新收藏状态
    let prevFavoured: boolean = this.isFavoured;
    let newFavoured: boolean = this.selectedFolderMlids.length > 0;
    this.isFavoured = newFavoured;
    this.showFavSheet = false;

    let result = await addVideoToFavFolders(aid, addFolders, delFolders);
    if (result.success) {
      this.toast(result.message);
    } else {
      // 回滚
      this.isFavoured = prevFavoured;
      this.toast(result.message);
    }
  }
}
