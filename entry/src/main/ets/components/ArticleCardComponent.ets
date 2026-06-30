/**
 * 专栏卡片组件
 */

import { ArticleCard } from '../model/ContentCard';

@Component
export struct ArticleCardComponent {
  // ===== 对外属性 =====
  @Prop card: ArticleCard = new ArticleCard();
  @Prop color: string = "";
  @Consume('pageStack') pageStack: NavPathStack;

  // ===== 工具方法 =====

  /**
   * 格式化播放量字符串（角标截断）
   * 太长时截取前 4 位显示
   */
  private formatView(view: string): string {
    if (view.length > 12) {
      return view.substring(0, 4) + '..';
    }
    return view;
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
            .width(85)
            .height(57)
            .borderRadius(6)
            .backgroundColor('#1E1E1E')

          // 封面图片
          Image(this.card.covers.length > 0 ? this.card.covers[0] : $r('app.media.article_placeholder'))
            .width(85)
            .height(57)
            .objectFit(ImageFit.Cover)
            .borderRadius(6)
            .alt($r('app.media.article_placeholder'))

          // 阅读量角标（左下角）
          Row() {
            SymbolGlyph($r("sys.symbol.play_fill")).fontSize(8).fontColor(['#FFFFFF'])
            Text(this.formatView(this.card.formatedView))
              .fontSize(8)
              .fontColor('#FFFFFF')
              .margin({ left: 2 })
              .fontWeight(FontWeight.Medium)
          }
          .backgroundColor('#B0000000')
          .padding({ left: 4, right: 4, top: 1, bottom: 1 })
          .borderRadius(3)
          .position({ x: 3, y: 42 })
        }
        .width(85)
        .height(57)
        .align(Alignment.TopStart)

        // ======================
        //    右侧：文字信息
        // ======================
        Column() {
          // 标题（最多 3 行，超出省略）
          Text(this.card.title)
            .fontSize(11)
            .fontColor('#EEEEEE')
            .fontWeight(FontWeight.Medium)
            .lineHeight(18)
            .maxLines(3)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .textAlign(TextAlign.Start)

          Blank()

          // UP 主信息
          if (this.card.upName !== ""){
            Row() {
              Circle()
                .width(8)
                .height(8)
                .fill('#3D3D3D')
              Text(this.card.upName)
                .fontSize(9)
                .fontColor('#999999')
                .margin({ left: 3 })
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
                .textAlign(TextAlign.Start)
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
          }
        }
        .height(70)
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
      console.info('[ArticleCard] 点击:', this.card.title, this.card.cvid);
      this.pageStack.pushPath({name: 'ArticleDetailPage', param: this.card})
    })
  }
}
