import { DynamicSection } from "../components/DynamicSection";

@Component
export struct DynamicListPage{
  @Consume('pageStack') pageStack: NavPathStack;

  private showNavMenu(): void {
    this.pageStack.pushPath({name:'Menu'});
  }

  build() {
    NavDestination(){
      this.HeaderBar()
      DynamicSection({mid: 0})
    }
    .height('100%')
    .width('100%')
    .backgroundImage($r("app.media.oobe"))
    .title("QRCodeView")
    .hideBackButton(true)
    .hideTitleBar(true)
  }

  @Builder
  HeaderBar() {
    Row() {
      Row() {
        Circle().width(8).height(8).fill('#FB7299')
        Text('动态').fontSize(16).fontColor('#EEEEEE')
          .fontWeight(FontWeight.Medium).margin({ left: 4 })
      }
      .onClick(() => {
        this.showNavMenu();
      })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding({ top: 8, bottom: 4 })
    .justifyContent(FlexAlign.Center)
  }
}