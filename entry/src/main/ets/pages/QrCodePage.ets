@Component
export struct QRCodePage {
  @Consume('pageStack') pageStack: NavPathStack;
  pathStack: NavPathStack | undefined = undefined;
  pageParam: string = '';

  build() {
    NavDestination() {
      List() {
        ListItem() {
          Text(this.pageParam).fontSize('25px').margin({ top: 30 }).width('60%')
        }

        ListItem() {
          QRCode(this.pageParam)
            .width('65%')
            .height('65%')
            .backgroundColor('rgba(255,255,255,0.75)')
            .margin({ top: 4, bottom: 30 })
        }
      }
      .height('100%')
      .width('100%')
      .focusable(true)
      .focusOnTouch(true)
      .defaultFocus(true)
      .alignListItem(ListItemAlign.Center)
    }
    .height('100%')
    .width('100%')
    .backgroundImage($r("app.media.oobe"))
    .title("QRCodeView")
    .hideBackButton(true)
    .hideTitleBar(true)
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      this.pageParam = context.pathInfo.param as string;
    })
  }
}