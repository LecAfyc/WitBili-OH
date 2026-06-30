/**
 * 动态详情页
 *
 * ArcSwiper 双页：
 *   1. 动态详情（isExpand=true 展开的 DynamicCardComponent）
 *   2. 评论区（CommentSection，type=17）
 *
 * 接收参数：Dynamic 对象（含 dynamicId）
 */

import { ArcSwiper } from '@kit.ArkUI';
import { DynamicCardComponent } from '../components/DynamicCardComponent';
import { CommentSection } from '../components/VideoDetail/CommentSection';
import { getDynamicDetail } from '../api/DynamicApi';
import { Dynamic } from '../model/Dynamic';

@Component
export struct DynamicDetailPage {
  @Consume('pageStack') pageStack: NavPathStack;

  @State pageParam: Dynamic = new Dynamic();
  @State isLoading: boolean = true;

  build() {
    NavDestination() {
      ArcSwiper() {
        // ───── 第 1 页：动态详情（展开态） ─────
        Column() {

          if (this.isLoading) {
            LoadingProgress().width(40).height(40).color('#FB7299')
          } else {
            // 以单个可滚动视图展示完整动态
            Scroll() {
              Column(){
                Blank().height("14%")
                DynamicCardComponent({ dynamic: this.pageParam, isExpand: true })
                  .margin({ top: 8 })
                Blank().height("14%")
              }
              .width("100%")
            }
            .scrollable(ScrollDirection.Vertical)
            .clip(true)
            .width('100%')
            .height('100%')
            .focusable(true)
            .focusOnTouch(true)
            .defaultFocus(true)
          }
        }
        .width('100%')
        .height('100%')
        .padding({left: 14, right: 14})

        // ───── 第 2 页：评论区（type=11 为动态评论区类型） ─────
        Column() {
          if (this.pageParam.comment_id > 0) {
            CommentSection({
              aid: this.pageParam.comment_id,
              type: [11,17]
            })
          } else {
            Column() {
              Text('暂无评论').fontSize(14).fontColor('#888888')
            }
            .width('100%').height('100%')
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
          }
        }
        .width('100%')
        .height('100%')
      }
      .indicator(false)
      .height('100%')
      .width('100%')

      // ───── 悬浮返回按钮 ─────
      Row() {
        Text('<').fontSize(18).fontColor('#FB7299').width(24).textAlign(TextAlign.Center)
        Text('返回').fontSize(15).fontColor('#EEEEEE').margin({ left: 4 })
      }
      .width('30%')
      .position({ x: 80, y: 8 })
      .padding({ left: 2, top: 8, bottom: 8 })
      .borderRadius(10)
      .backgroundColor('rgba(22,22,22,0.6)')
      .onClick(() => { if (this.pageStack) this.pageStack.pop(); })
    }
    .height('100%')
    .width('100%')
    .backgroundImage($r("app.media.oobe"))
    .hideBackButton(true)
    .hideTitleBar(true)
    .onReady((context: NavDestinationContext) => {
      let incoming: Dynamic = context.pathInfo.param as Dynamic;
      if (incoming) {
        this.pageParam = incoming;
        // 异步加载详情（刷新数据、补全字段）
        this.refreshDetail(incoming.dynamicId);
      }
    })
  }

  /**
   * 从 API 刷新动态详情，补齐 API 可能返回的额外字段
   */
  private async refreshDetail(dyid: number): Promise<void> {
    try {
      const detail: Dynamic | null = await getDynamicDetail(dyid);
      if (detail) {
        // 保留外部传入的引用字段（如 userInfo），再覆盖 API 返回的数据
        if (!detail.userInfo || !detail.userInfo.mid) {
          detail.userInfo = this.pageParam.userInfo;
        }
        if (!detail.message) {
          detail.message = this.pageParam.message;
          detail.emoteMap = this.pageParam.emoteMap;
          detail.memberMap = this.pageParam.memberMap;
        }
        this.pageParam = detail;
      }
    } catch (e) {
      console.warn('[DynamicDetail] refresh 失败，使用初始数据:', String(e));
    } finally {
      this.isLoading = false;
    }
  }
}
