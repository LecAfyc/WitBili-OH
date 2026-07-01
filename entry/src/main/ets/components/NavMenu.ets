/**
 * 导航菜单组件
 *
 * 手表圆屏使用 Column 菜单替代底部 Tab。
 * NavPathStack 由父组件通过参数传入，用于页面跳转。
 */
import { ArcList, ArcListItem } from "@ohos.arkui.ArcList";
import { LengthMetrics } from "@kit.ArkUI";
import { UserCard } from "../model/UserCard";
import { getMyAccountInfo, MyAccountInfo } from "../api/LoginApi";


@Component
export struct NavMenu {
  @Consume('pageStack') pageStack: NavPathStack;

  build() {
    NavDestination() {
      ArcList({ initialIndex: 1 }) {
        ArcListItem() {
          Row() {
            SymbolGlyph($r("sys.symbol.discover_fill")).fontSize(20).fontColor(['#FB7299']).width(32)
            Text('推荐').fontSize(17).fontColor('#EEEEEE').margin({ left: 8 })
          }
          .width('80%')
          .padding({ top: 14, bottom: 14, left: 16 })
          .borderRadius(10)
          .backgroundColor('#161616')
          .onClick(() => {
            this.navigateTo('Rcmd')
          })
        }

        ArcListItem() {
          Row() {
            SymbolGlyph($r("sys.symbol.worldclock")).fontSize(20).fontColor(['#FB7299']).width(32)
            Text('动态').fontSize(17).fontColor('#EEEEEE').margin({ left: 8 })
          }
          .width('80%')
          .padding({ top: 14, bottom: 14, left: 16 })
          .borderRadius(10)
          .backgroundColor('#161616')
          .onClick(() => {
            let accountData: string = AppStorage.get<string>('AccountData') || '';
            console.info('[NavMenu]data = ' + accountData);
            if (accountData === 'null') {
              console.info('[NavMenu] 未登录，前往Loginpage ');
              this.navigateTo('Login');
            } else {
              console.info('[NavMenu] 已登录 ');
              getMyAccountInfo().then((my: MyAccountInfo | null) => {
                if (my !== null && my !== undefined) {
                  this.navigateTo('DynamicListPage')
                }
              })
            }
          })
        }

        ArcListItem() {
          Row() {
            SymbolGlyph($r("sys.symbol.magnifyingglass")).fontSize(20).fontColor(['#FB7299']).width(32)
            Text('搜索').fontSize(17).fontColor('#EEEEEE').margin({ left: 8 })
          }
          .width('80%')
          .padding({ top: 14, bottom: 14, left: 16 })
          .borderRadius(10)
          .backgroundColor('#161616')
          .onClick(() => {
            this.navigateTo('SearchPage');
          })
        }

        ArcListItem() {
          Row() {
            SymbolGlyph($r("sys.symbol.person")).fontSize(20).fontColor(['#FB7299']).width(32)
            Text('个人').fontSize(17).fontColor('#EEEEEE').margin({ left: 8 })
          }
          .width('80%')
          .padding({ top: 14, bottom: 14, left: 16 })
          .borderRadius(10)
          .backgroundColor('#161616')
          .onClick(() => {
            let accountData: string = AppStorage.get<string>('AccountData') || '';
            console.info('[NavMenu]data = ' + accountData);
            if (accountData === 'null') {
              console.info('[NavMenu] 未登录，前往Loginpage ');
              this.navigateTo('Login');
            } else {
              console.info('[NavMenu] 已登录 ');
              getMyAccountInfo().then((my: MyAccountInfo | null) => {
                if (my !== null && my !== undefined) {
                  this.navigateTo('UserDetailPage', new UserCard(my.uname, "", my.mid));
                }
              })
            }
          })
        }

        ArcListItem() {
          Row() {
            SymbolGlyph($r("sys.symbol.envelope")).fontSize(20).fontColor(['#FB7299']).width(32)
            Text('私信').fontSize(17).fontColor('#EEEEEE').margin({ left: 8 })
          }
          .width('80%')
          .padding({ top: 14, bottom: 14, left: 16 })
          .borderRadius(10)
          .backgroundColor('#161616')
          .onClick(() => {
            let accountData: string = AppStorage.get<string>('AccountData') || '';
            console.info('[NavMenu]data = ' + accountData);
            if (accountData === 'null') {
              console.info('[NavMenu] 未登录，前往Loginpage ');
              this.navigateTo('Login');
            } else {
              console.info('[NavMenu] 已登录 ');
              // TODO: push 私信
            }
          })
        }

        ArcListItem() {
          Row() {
            SymbolGlyph($r("sys.symbol.gearshape")).fontSize(20).fontColor(['#FB7299']).width(32)
            Text('设置').fontSize(17).fontColor('#EEEEEE').margin({ left: 8 })
          }
          .width('80%')
          .padding({ top: 14, bottom: 14, left: 16 })
          .borderRadius(10)
          .backgroundColor('#161616')
          .onClick(() => {
            this.getUIContext().getPromptAction().showToast({ message: "对应功能未完成，给你看图吧" })
            this.navigateTo('ImageViewer', "https://t.alcy.cc/mp");
          })
        }

        ArcListItem() {
          Row() {
            SymbolGlyph($r("sys.symbol.arrowshape_down_to_line_fill")).fontSize(20).fontColor(['#FB7299']).width(32)
            Text('缓存').fontSize(17).fontColor('#EEEEEE').margin({ left: 8 })
          }
          .width('80%')
          .padding({ top: 14, bottom: 14, left: 16 })
          .borderRadius(10)
          .backgroundColor('#161616')
          .onClick(() => {
            this.getUIContext().getPromptAction().showToast({ message: "对应功能未完成，给你看图吧" })
            this.navigateTo('ImageViewer', "https://t.alcy.cc/mp");
          })
        }
      }
      .width('100%')
      .space(LengthMetrics.px(22))
      .opacity(0.8)
      .focusable(true)
      .focusOnTouch(true)
      .defaultFocus(true)
    }
    .width('100%')
    .height('100%')
    .hideBackButton(true)
    .hideTitleBar(true)
    .mode(NavDestinationMode.DIALOG)
    .systemTransition(NavigationSystemTransitionType.FADE)
    .backgroundBlurStyle(BlurStyle.BACKGROUND_THIN)
  }

  private navigateTo(targetPageName: string, param?: Object) {
    const allPageNames = this.pageStack.getAllPathName();
    const stackSize = allPageNames.length;
    if (stackSize <= 1) {
      console.warn('[NavMenu] 页面不足，无法执行操作');
      return;
    }
    const previousPageName = allPageNames[stackSize - 2];
    this.pageStack.pop();
    if (previousPageName !== targetPageName) {
      this.pageStack.replacePathByName(targetPageName, param);
    }
  }
}
