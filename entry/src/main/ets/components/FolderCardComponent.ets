/**
 * 收藏夹卡片组件
 */

import { FavFolder } from '../model/FavFolder';
import { VideoListPageParams } from '../pages/VideoListPage';

@Component
export struct FolderCardComponent {
  // ===== 对外属性 =====
  @Prop card: FavFolder = new FavFolder();
  @Prop color?: string = '';
  @Consume('pageStack') pageStack: NavPathStack;

  toThumb(url: string): string {
    if (url.indexOf('@') === -1) return url + '@60w_60h';
    return url;
  }

  // ===== 构建 =====
  build() {
    Column() {
      // 卡片主体：左侧封面 + 右侧信息
      Row() {
        // ======================
        //    左侧：封面区域
        // ======================
        Stack() {
          // 占位背景（图片没加载出来时显示）
          Column()
            .width(42)
            .height(28)
            .borderRadius(6)
            .backgroundColor('#1E1E1E')

          // 封面图片
          Image(this.card.cover)
            .width(42)
            .height(28)
            .objectFit(ImageFit.Cover)
            .borderRadius(6)
            .alt($r('app.media.placeholder'))
        }
        .width(42)
        .height(28)
        .align(Alignment.TopStart)

        // ======================
        //    右侧：文字信息
        // ======================
        Column() {
          // 标题（最多 3 行，超出省略）
          Text(this.card.name)
            .fontSize(15)
            .fontColor('#EEEEEE')
            .fontWeight(FontWeight.Bold)
            .lineHeight(18)
            .maxLines(3)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .textAlign(TextAlign.Start)
        }
        .justifyContent(FlexAlign.Center)
        .height(30)
        .padding({ left: 8 })
        .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding(8)
    }
    .width('100%')
    .backgroundColor(this.color !== null && this.color !== undefined && this.color !== '' ? this.color : 'rgba(22,22,22,0.8)')
    .borderRadius(10)
    .onClick(() => {
      console.info('[FolderCard] 点击:', this.card.name, this.card.mlid);
      let listParams: VideoListPageParams = new VideoListPageParams('collection', this.card.name, this.card.mlid);
      this.pageStack.pushPath({ name: 'VideoListPage', param: listParams });
    })
  }
}
