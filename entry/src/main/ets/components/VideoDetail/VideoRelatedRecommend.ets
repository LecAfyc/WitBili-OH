/**
 * 视频相关推荐组件
 *
 * 展示当前视频下方的相关视频推荐列表，使用 VideoCardComponent 渲染每一项。
 * 数据由父页面（VideoDetailPage）传入，通过 @Prop 绑定。
 */

import { VideoCard } from '../../model/ContentCard';
import { VideoCardComponent } from '../VideoCardComponent';

@Component
export struct VideoRelatedRecommend {
  @Consume('pageStack') pageStack: NavPathStack;

  // ===== 对外属性 =====
  @Prop relatedVideos: VideoCard[] = [];

  build() {
    Column() {
      // ===== 推荐列表 =====
      List({ space: 8 }) {

        ListItem(){
          Column().height('14%')
        }

        ForEach(this.relatedVideos, (item: VideoCard, index?: number) => {
          ListItem() {
            VideoCardComponent({ card: item })
          }
        })

        ListItem(){
          Column().height('14%')
        }

      }
      .width('100%')
      .height('100%')
      .layoutWeight(1)
      .edgeEffect(EdgeEffect.Spring)
      .padding({left: 16, right: 16})
    }
    .width('100%')
    .height('100%')
  }
}
