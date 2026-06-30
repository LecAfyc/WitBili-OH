/**
 * 用户卡片组件
 *
 * 当 card.isVip 为 true 时，用户名显示为 #FB7299 粉色；
 * 当 card.level 有值时，在用户名右侧显示对应等级的图标。
 */

import { UserCard } from '../model/UserCard';

@Component
export struct UserCardComponent {
  @Consume('pageStack') pageStack: NavPathStack;
  // ===== 对外属性 =====
  @Prop card: UserCard = new UserCard();
  @Prop extraInfo: string = "";
  /** 基准字号（默认 14），头像、等级图标、边距等均跟随缩放 */
  @Prop baseFontSize: number = 14;
  @Prop color?: string = '';

  // 计算大小
  s = this.baseFontSize / 14;
  avatarW = 36 * this.s;
  levelW = 16 * this.s;
  extraH = 15 * this.s;
  cardH = 56 * this.s;

  toThumb(url: string): string {
    if (url.indexOf('@') === -1) return url + '@35w_35h';
    return url;
  }

  // ===== 构建 =====
  build() {
    Row() {
      // 左边：圆形头像
      Image(this.toThumb(this.card.headImage))
        .width(this.avatarW)
        .height(this.avatarW)
        .borderRadius(this.avatarW / 2)
        .margin({ left: 12 * this.s })
        .objectFit(ImageFit.Cover)
        .alt($r('app.media.avatar_alt'))

      // 右边：用户名 + 等级图标 + extraInfo
      Column() {
        Row() {
          // 用户名：大会员显示粉色
          Text(this.card.name)
            .fontSize(this.baseFontSize)
            .fontColor(this.card.isVip ? '#FB7299' : '#FFFFFF')
            .fontWeight(FontWeight.Medium)
            .lineHeight(this.baseFontSize * 18 / 14)
            .maxLines(1)
            .constraintSize({ maxWidth: 122})
            .textOverflow({ overflow: TextOverflow.MARQUEE })

          // 等级图标（有 level 属性时才显示）
          if (this.card.level !== undefined && this.card.level !== null) {
            Image($r('app.media.level_' + this.card.level))
              .width(this.levelW)
              .height(this.levelW)
              .objectFit(ImageFit.Contain)
              .margin({ left: 4 * this.s })
          }
        }
        .alignItems(VerticalAlign.Center)
        .width('100%')

        Text(this.extraInfo)
          .fontSize(this.baseFontSize * 11 / 14)
          .fontColor('#AAAAAA')
          .lineHeight(this.extraH)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.MARQUEE })
      }
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.Center)
      .layoutWeight(1)
      .padding({ left: 10 * this.s, right: 12 * this.s })
    }
    .width('100%')
    .height(this.cardH)
    .backgroundColor(this.color !== null && this.color !== undefined && this.color !== '' ? this.color : 'rgba(22,22,22,0.8)')
    .borderRadius(10)
    .onClick(() => {
      console.info('[UserCard] 点击:', this.card.mid, this.card.name);
      this.pageStack.pushPath({name: 'UserDetailPage', param: this.card})
    })
  }
}
