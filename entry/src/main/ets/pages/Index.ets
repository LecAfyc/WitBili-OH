import { NavMenu } from '../components/NavMenu';
import { ImageViewPage } from './ImageViewPage';
import { LoginPage } from './LoginPage';
import { OobePage } from './OobePage';
import { QRCodePage } from './QrCodePage';
import { RcmdPage } from './RcmdPage';
import { restoreCookiesFromStorage, checkCookieRefreshIfNeeded, checkLoginStatus,
  getMyAccountInfo,
  MyAccountInfo} from '../api/LoginApi';
import { VideoDetailPage } from './VideoDetailPage';
import { CommentPage } from './CommentPage';
import { SearchPage } from './SearchPage';
import { SearchResultPage } from './SearchResultPage';
import { UserDetailPage } from './UserDetailPage';
import { DynamicListPage } from './DynamicListPage';
import { DynamicDetailPage } from './DynamicDetailPage';
import { ArticleDetailPage } from './ArticleDetailPage';
import { VideoPlayerPage } from './VideoPlayerPage';
import { VideoListPage } from './VideoListPage';

PersistentStorage.persistProp('AccountData', 'null');
PersistentStorage.persistProp('isAgreementAccepted', false);
PersistentStorage.persistProp('refresh_token', '');
PersistentStorage.persistProp('SearchHistory', '[]');
AppStorage.setOrCreate<number>('mid', 0);

@Entry
@Component
struct Index {
  @Provide('pageStack') pageStack: NavPathStack = new NavPathStack();

  // ==========================
  //        路由映射表
  // ==========================
  @Builder
  pageMap(name: string, param: Object) {
    if (name === 'Menu') {
      // 侧边菜单
      Column() {
        NavMenu()
      }
      .width('100%').height('100%')
      .padding({ top: 64, left: 16, right: 16 })
    }
    else if (name === 'OOBE') OobePage()
    else if (name === 'QrCode') QRCodePage()
    else if (name === 'Rcmd') RcmdPage()
    else if (name === 'Login') LoginPage()
    else if (name === 'ImageViewer') ImageViewPage();
    else if (name === 'VideoDetail') VideoDetailPage();
    else if (name === 'CommentPage') CommentPage();
    else if (name === 'SearchPage') SearchPage();
    else if (name === 'SearchResultPage') SearchResultPage();
    else if (name === 'UserDetailPage') UserDetailPage();
    else if (name === 'DynamicListPage') DynamicListPage();
    else if (name === 'DynamicDetailPage') DynamicDetailPage();
    else if (name === 'ArticleDetailPage') ArticleDetailPage();
    else if (name === 'VideoPlayer') VideoPlayerPage();
    else if (name === 'VideoListPage') VideoListPage();
  }

  build() {
    Navigation(this.pageStack){
      Column(){
        Text("这个页面是无用页面，如果你因为Bug来到了这里，点我可回到主页，右滑可以退出")
          .onClick(() => {
            this.pageStack.replacePath({name: "Rcmd", param: ""});
          })
          .margin({top:60})
      }
      .justifyContent(FlexAlign.Center)
      .width('100%')
      .height('100%')
    }
    .navDestination(this.pageMap)
    .onAppear(() => {
      if (!AppStorage.get<boolean>('isAgreementAccepted')) {
        this.pageStack.replacePath({name: "OOBE", param: ""});
      }else{
        if(AppStorage.get<string>('AccountData') !== 'null'){
          restoreCookiesFromStorage();
          checkCookieRefreshIfNeeded().then((refreshed: boolean) => {
            if (refreshed) {
              this.getUIContext().getPromptAction().showToast({ message: 'Cookie 已自动刷新' });
            }
          });
          checkLoginStatus().then((valid: boolean) => {
            if (!valid) {
              this.getUIContext().getPromptAction().showToast({ message: '登录状态已失效，请重新登录' });
              AppStorage.set<String>('AccountData','null');
              AppStorage.set<String>('refresh_token', "");
            } else {
              getMyAccountInfo().then((info: MyAccountInfo | null) => {
                AppStorage.set<number>('mid', info?.mid)
              })
            }
          });
        }
        this.pageStack.replacePath({name: "Rcmd", param: ""});
      }
      console.info("[Index] 加载已完成！")
      console.info("[Index] 你居然想看log？等待你的是：中英混杂 | 神秘记号 | warn随便用 | 发泄情绪")
    })
  }
}
