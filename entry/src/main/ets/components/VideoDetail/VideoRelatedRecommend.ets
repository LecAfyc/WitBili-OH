/**
 * 视频相关推荐组件
 *
 * 传入 aid/bvid 标识符，组件内部通过 aboutToAppear() 自行调用 getRelatedVideos() 加载推荐数据。
 * 数据加载职责由组件自治，页面层仅传入标识符参数。
 */

import { VideoCard } from '../../model/ContentCard';
import { VideoCardComponent } from '../VideoCardComponent';
import { getRelatedVideos } from '../../api/RecommendApi';

@Component
export struct VideoRelatedRecommend {
  @Consume('pageStack') pageStack: NavPathStack;
  // ===== 从父页面传入的参数 =====
  @Prop @Watch('onAidChanged') aid: number = 0;
  @Prop bvid: string = '';
  // ===== 组件内部状态 =====
  @State relatedVideos: VideoCard[] = [];
  @State isLoading: boolean = true;
  @State loadError: string = '';

  // ===== 生命周期：加载数据 =====
  aboutToAppear(): void {
    if (this.aid > 0 || this.bvid) {
      this.loadRelatedVideos();
    }
  }

  onAidChanged(): void {
    if (this.aid > 0 && this.isLoading) {
      this.loadRelatedVideos();
    }
  }

  private async loadRelatedVideos(): Promise<void> {
    this.isLoading = true;
    this.loadError = '';
    try {
      let list = await getRelatedVideos(this.aid > 0 ? this.aid : undefined, this.bvid);
      this.relatedVideos = list;
      this.isLoading = false;
      console.info('[VideoRelatedRecommend] 推荐加载完成: ' + list.length.toString() + ' 条');
    } catch (e) {
      this.isLoading = false;
      this.loadError = '推荐视频加载失败';
      console.error('[VideoRelatedRecommend] 推荐加载失败:', String(e));
    }
  }

  build() {
    Column() {
      // ===== 加载状态 =====
      if (this.isLoading) {
        Column() {
          LoadingProgress().width(36).height(36)
          Text('加载中...').fontSize(13).fontColor('#888888').margin({ top: 8 })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .justifyContent(FlexAlign.Center)
        .layoutWeight(1)
      } else if (this.loadError) {
        Column() {
          Text(this.loadError).fontSize(13).fontColor('#888888')
          Text('点击重试').fontSize(12).fontColor('#FB7299').margin({ top: 12 })
            .onClick(() => {
              this.loadRelatedVideos();
            })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .justifyContent(FlexAlign.Center)
        .layoutWeight(1)
      } else {
        // ===== 推荐列表 =====
        List({ space: 8 }) {

          ListItem() {
            Column().height('14%')
          }

          ForEach(this.relatedVideos, (item: VideoCard, index?: number) => {
            ListItem() {
              VideoCardComponent({ card: item })
            }
          })

          ListItem() {
            Column().height('14%')
          }

        }
        .width('100%')
        .height('100%')
        .layoutWeight(1)
        .edgeEffect(EdgeEffect.Spring)
        .padding({ left: 16, right: 16 })
      }
    }
    .width('100%')
    .height('100%')
  }
}
