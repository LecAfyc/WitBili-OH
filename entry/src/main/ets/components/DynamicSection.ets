/**
 * 动态列表页面组件
 *
 * 嵌入首页或用户页，整体为一个 List。
 * 顶部是新动态数 + 类型切换开关（全部/视频/追番/专栏）。
 * 列表项为 DynamicCardComponent（折叠态），
 * 点击跳转动态详情页（占位），
 * 滑到底部自动翻页加载下一页。
 *
 * mid=0  → 首页推荐动态（支持类型筛选和新动态数检测）
 * mid>0  → 指定用户的空间动态（无类型筛选）
 */

import { Dynamic } from '../model/Dynamic';
import { DynamicCardComponent } from './DynamicCardComponent';
import { getDynamicFeed, getUserDynamic, checkDynamicUpdate } from '../api/DynamicApi';
import { LengthMetrics } from '@kit.ArkUI';

// ===== 类型切换配置 =====
interface TypeOption {
  label: string;
  value: string;
}

const TYPE_OPTIONS: TypeOption[] = [
  { label: '全部', value: 'all' },
  { label: '视频投稿', value: 'video' },
  { label: '图文', value: 'article' }
];

@Component
export struct DynamicSection {
  @Consume('pageStack') pageStack: NavPathStack;
  /** mid=0 加载首页动态，mid>0 加载用户空间动态 */
  @Prop mid: number = 0;

  @State dynamicList: Dynamic[] = [];
  /** 新动态数量（仅首页有效） */
  @State newCount: number = 0;
  @State isLoading: boolean = false;
  @State isRefreshing: boolean = false;
  @State hasMore: boolean = true;
  @State firstLoad: boolean = true;
  @State errorMessage: string = '';
  @State currentType: string = 'all';
  @State loadOffset: string = '';
  @State updateBaseline: string = '';

  // ==========================
  //        生命周期
  // ==========================

  aboutToAppear(): void {
    this.loadDynamics(true);
  }

  // ==========================
  //      数据加载
  // ==========================

  private async loadDynamics(isRefresh: boolean): Promise<void> {
    if (this.isLoading) return;
    this.isLoading = true;
    this.errorMessage = '';

    if (isRefresh) {
      this.loadOffset = '';
      this.dynamicList = [];
      this.hasMore = true;
      this.updateBaseline = '';
    }

    try {
      if (this.mid === 0) {
        // 首页动态
        const result = await getDynamicFeed(this.loadOffset, this.currentType);

        if (isRefresh) {
          this.dynamicList = result.list;
          this.updateBaseline = result.updateBaseline;

          // 检查新动态数量（需要 updateBaseline）
          if (this.updateBaseline) {
            try {
              this.newCount = await checkDynamicUpdate(this.currentType, this.updateBaseline);
            } catch (_e) {
              console.warn('[Dynamic] checkUpdate 失败');
              this.newCount = 0;
            }
          }
        } else {
          this.dynamicList = this.dynamicList.concat(result.list);
        }

        this.loadOffset = result.offset;
        this.hasMore = result.offset !== '';
      } else {
        // 用户空间动态
        const result = await getUserDynamic(this.mid, this.loadOffset);

        if (isRefresh) {
          this.dynamicList = result.list;
        } else {
          this.dynamicList = this.dynamicList.concat(result.list);
        }

        this.loadOffset = result.offset;
        this.hasMore = result.offset !== '';
      }

      this.firstLoad = false;
    } catch (e) {
      console.error('[DynamicSection] 加载失败:', JSON.stringify(e));
      this.errorMessage = '动态加载失败';
    } finally {
      this.isLoading = false;
      this.isRefreshing = false;
    }
  }

  private handleRefresh(): void {
    this.isRefreshing = true;
    this.hasMore = true;
    this.errorMessage = '';
    this.loadDynamics(true);
  }

  private handleLoadMore(): void {
    if (!this.isLoading && this.hasMore) {
      this.loadDynamics(false);
    }
  }

  private toggleType(type: string): void {
    if (this.currentType === type) return;
    this.currentType = type;
    this.loadDynamics(true);
  }

  // ==========================
  //        页面跳转
  // ==========================

  private onDynamicTap(dyn: Dynamic): void {
    console.info('[Dynamic] tap dyid=' + dyn.dynamicId);
    this.pageStack.pushPath({ name: 'DynamicDetailPage', param: dyn });
  }

  // ==========================
  //          构建
  // ==========================

  build() {
    Column() {
      if (this.firstLoad && this.isLoading && this.dynamicList.length === 0) {
        // 首次加载
        Column() {
          LoadingProgress().width(40).height(40).color('#FB7299')
          Text('加载中...').fontSize(15).fontColor('#666666').margin({ top: 12 })
        }
        .width('100%').height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else if (this.dynamicList.length === 0 && !this.isLoading) {
        // 没有动态
        Column() {
          Text(this.mid === 0 ? '暂无动态' : 'TA还没有发过动态')
            .fontSize(14).fontColor('#888888')
            .textAlign(TextAlign.Center).lineHeight(20)
          Text('点击刷新').fontSize(13).fontColor('#FB7299').margin({ top: 16 })
            .onClick(() => { this.handleRefresh(); })
        }
        .width('100%').height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        Refresh({ refreshing: this.isRefreshing }) {
          List({ space: 0 }) {
            if (this.mid > 0){
              ListItem(){
                Column().height("14%")
              }
            }
            // ─── 顶部栏：新动态数量 + 类型切换 ───
            ListItem() {
              Column() {
                // 首页显示类型切换，用户空间不显示
                if (this.mid === 0) {
                  Row({ space: 10 }) {
                    ForEach(TYPE_OPTIONS, (opt: TypeOption) => {
                      Text(opt.label)
                        .fontSize(12)
                        .fontColor(this.currentType === opt.value ? '#FB7299' : '#777777')
                        .fontWeight(this.currentType === opt.value
                          ? FontWeight.Medium : FontWeight.Regular)
                        .onClick(() => { this.toggleType(opt.value); })
                    })
                  }
                  .margin({ top: 6 })
                }
              }
              .width('100%')
              .alignItems(HorizontalAlign.Center)
              .padding({ top: 8, bottom: 8 })
            }

            // ─── 动态卡片（折叠态） ───
            ForEach(this.dynamicList, (item: Dynamic, index: number) => {
              ListItem() {
                DynamicCardComponent({ dynamic: item, isExpand: false })
              }
              .onClick(() => { this.onDynamicTap(item); })
            })

            // ─── 底部加载更多指示 ───
            ListItem() {
              Row() {
                if (this.isLoading) {
                  LoadingProgress().width(18).height(18).color('#FB7299')
                  Text('加载更多...').fontSize(12).fontColor('#777777').margin({ left: 6 })
                } else if (!this.hasMore && this.dynamicList.length > 0) {
                  Text('— 没有更多了 —').fontSize(12).fontColor('#555555')
                }
              }
              .width('100%').justifyContent(FlexAlign.Center)
              .padding({ top: 8, bottom: 16 })
            }

            // 底部留白
            ListItem() {
              Column().height('14%')
            }
          }
          .width('100%').height('110%')
          .onReachEnd(() => { this.handleLoadMore(); })
          .edgeEffect(EdgeEffect.Spring)
          .fadingEdge(true, { fadingEdgeLength: LengthMetrics.vp(20) })
          .padding({ left: 14, right: 14 })
          .focusable(true)
          .focusOnTouch(true)
          .defaultFocus(true)
        }
        .onRefreshing(() => { this.handleRefresh(); })
        .refreshOffset(60)
        .width('100%').height('100%')
      }
    }
    .width('100%').height('100%')
  }
}
