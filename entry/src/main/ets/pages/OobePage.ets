import { ArcSwiper } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';

@Component
export struct OobePage{
  @Consume('pageStack') pageStack: NavPathStack;
  @State agr: boolean = false;
  pathStack: NavPathStack | undefined = undefined;
  pageParam: string = '';

  build() {
    NavDestination(){
      ArcSwiper() {
        Column() {
          Image($r("app.media.startIcon")).width('20%').height('20%')
          Text("WitBili-OH")
            .fontSize('45px')
            .fontWeight(FontWeight.Bold)
            .margin({ top: 6 })
            .fontColor('#FB7299')
          Text(">>> 右滑以继续")
            .fontSize('27px')
            .fontWeight(FontWeight.Bold)
            .margin({ top: 6 })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)

        if (!this.agr){
          Column() {
            Text('请仔细阅读用户协议')
              .fontSize('18vp')
              .fontColor('#FB7299')
              .fontWeight(FontWeight.Bold)
              .fontWeight(FontWeight.Medium)
              .textAlign(TextAlign.Center)
              .margin({ bottom: 8, top: 10 })
              .padding({ left: 10, right: 10 })

            Button('查看用户协议')
              .fontSize('16vp')
              .fontColor('#ff4c4cf6')
              .backgroundColor(Color.Transparent)
              .padding({ top: 4, bottom: 4 })
              .onClick(() => {
                this.pageStack.pushPath(
                  { name: "QrCode", param: "https://test.com/agreement还没写.html" })
              })

            Button('同意')
              .fontSize('18vp')
              .width('70%')
              .height(40)
              .backgroundColor('#FB7299')
              .fontColor(Color.White)
              .borderRadius(20)
              .margin({ top: 12 })
              .onClick(() => {
                this.agr = true;
                AppStorage.set<boolean>('isAgreementAccepted', true);
              })

            Button('不同意')
              .fontSize('18vp')
              .width('70%')
              .height(40)
              .backgroundColor(Color.Transparent)
              .fontColor('#FB7299')
              .border({ width: 1, color: '#FB7299' })
              .borderRadius(20)
              .margin({ top: 6 })
              .onClick(() => {
                AppStorage.get<common.UIAbilityContext>("UiAbilityContext")?.terminateSelf().catch(() => {
                  this.pageStack.clear();
                });
              })
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .animation({
            duration: 600,
            curve: Curve.Rhythm,
            playMode: PlayMode.Alternate,
          })
        }

        if(this.agr){
          Column() {
            Text('提示')
              .fontSize('18vp')
              .fontColor('#FB7299')
              .fontWeight(FontWeight.Bold)
              .fontWeight(FontWeight.Medium)
              .textAlign(TextAlign.Center)
              .margin({ bottom: 8})
              .padding({ left: 10, right: 10 })

            Image($r('app.media.tip'))
              .width(150)
              .height(68)

            Text('在主界面内，通过点击页签查看更多功能')
              .fontSize('18vp')
              .width('70%')
              .height(40)
              .fontColor(Color.White)
              .borderRadius(20)
              .margin({ top: 12 })
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .animation({
            duration: 600,
            curve: Curve.Rhythm,
            playMode: PlayMode.Alternate,
          })

          Column() {
            Text('！极早期版本注意 ！')
              .fontSize('18vp')
              .fontColor('#FB7299')
              .fontWeight(FontWeight.Bold)
              .fontWeight(FontWeight.Medium)
              .textAlign(TextAlign.Center)
              .margin({ bottom: 8})
              .padding({ left: 10, right: 10 })

            Text('你现在使用的是非常不稳定的Dev版本！已知Bug：\n' +
              '登录过一天就会掉\n' +
              '部分功能缺失\n' +
              '永远卡在“正在加载”页面\n' +
              '动态无法点赞\n' +
              '以及，一定会有更多...\n' +
              '你可以向开发者反馈，但不要信息轰炸和直接开喷！')
              .fontSize('10vp')
              .width('70%')
              .fontColor(Color.White)
              .borderRadius(20)
              .margin({ top: 12 })

          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .animation({
            duration: 600,
            curve: Curve.Rhythm,
            playMode: PlayMode.Alternate,
          })

          Column() {
            Text('登录到BiliBili')
              .fontSize('18vp')
              .fontColor('#FB7299')
              .fontWeight(FontWeight.Bold)
              .fontWeight(FontWeight.Medium)
              .textAlign(TextAlign.Center)
              .margin({ bottom: 8 , top: 10})
              .padding({ left: 10, right: 10 })

            SymbolGlyph($r("sys.symbol.person"))
              .fontSize('30vp')
              .padding({ top: 4, bottom: 4 })

            Text('不想登录？直接右滑 >>>')
              .fontSize('14vp')
              .opacity(0.7)
              .padding({ top: 4, bottom: 4 })

            Button('前往登录页面')
              .fontSize('18vp')
              .width('70%')
              .height(40)
              .backgroundColor('#FB7299')
              .fontColor(Color.White)
              .borderRadius(20)
              .margin({ top: 12 })
              .onClick(() => {
                if(AppStorage.get<string>('AccountData') === 'null') this.pageStack.pushPath({name: "Login"})
              })
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .animation({
            duration: 600,
            curve: Curve.Rhythm,
            playMode: PlayMode.Alternate,
          })

          Column(){
            Image($r("app.media.startIcon")).width('20%').height('20%')
            Text("WitBili-OH")
              .fontSize('45px')
              .fontWeight(FontWeight.Bold)
              .margin({top:6})
              .fontColor('#FB7299')
            Button(">>> 开始WitBili-OH之旅",{ type: ButtonType.Capsule, stateEffect: false })
              .fontSize('27px')
              .fontWeight(FontWeight.Bold)
              .margin({top:6})
              .shadow({ radius: 2, color: 'rgba(0, 0, 0, 0.55)', offsetX: 2, offsetY: 2 })
              .backgroundColor(Color.Transparent)
              .fontColor('#FB7299')
              .border({ width: 1, color: '#FB7299' })
              .onClick(() => {
                this.pageStack.pushPath({name: "Rcmd", param: ""});
              })
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
        }
      }
    }
    .height('100%')
    .width('100%')
    .hideBackButton(true)
    .hideTitleBar(true)
    .backgroundImage($r("app.media.oobe"))
  }
}