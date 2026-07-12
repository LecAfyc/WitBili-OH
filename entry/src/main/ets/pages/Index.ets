import { NavMenu } from '../components/NavMenu';
import { ImageViewPage } from './ImageViewPage';
import { LoginPage } from './LoginPage';
import { OobePage } from './OobePage';
import { QRCodePage } from './QrCodePage';
import { RcmdPage } from './RcmdPage';
import {
  restoreCookiesFromStorage,
  checkCookieRefreshIfNeeded,
  checkLoginStatus,
  getMyAccountInfo,
  LoginCheckStatus,
  MyAccountInfo
} from '../api/LoginApi';
import { common } from '@kit.AbilityKit';
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
import { MessageListPage } from './MessageListPage';
import { ChatPage } from './ChatPage';

PersistentStorage.persistProp('AccountData', 'null');
PersistentStorage.persistProp('isAgreementAccepted', false);
PersistentStorage.persistProp('refresh_token', '');
PersistentStorage.persistProp('SearchHistory', '[]');
AppStorage.setOrCreate<number>('mid', 0);

@Entry
@Component
struct Index {
  @Provide('pageStack') pageStack: NavPathStack = new NavPathStack();
  @State initialized: boolean = false

  // ==========================
  //        路由映射表
  // ==========================
  @Builder
  pageMap(name: string, _param: Object) {
    if (name === 'Menu') {
      // 侧边菜单
      Column() {
        NavMenu()
      }
      .width('100%').height('100%')
      .padding({ top: 64, left: 16, right: 16 })
    } else if (name === 'OOBE') {
      OobePage()
    } else if (name === 'QrCode') {
      QRCodePage()
    } else if (name ===
      'Rcmd') {
      RcmdPage()
    } else if (name === 'Login') {
      LoginPage()
    } else if (name ===
      'ImageViewer') {
      ImageViewPage();
    } else if (name === 'VideoDetail') {
      VideoDetailPage();
    } else if (name ===
      'CommentPage') {
      CommentPage();
    } else if (name === 'SearchPage') {
      SearchPage();
    } else if (name ===
      'SearchResultPage') {
      SearchResultPage();
    } else if (name === 'UserDetailPage') {
      UserDetailPage();
    } else if (name ===
      'DynamicListPage') {
      DynamicListPage();
    } else if (name ===
      'DynamicDetailPage') {
      DynamicDetailPage();
    } else if (name ===
      'ArticleDetailPage') {
      ArticleDetailPage();
    } else if (name === 'VideoPlayer') {
      VideoPlayerPage();
    } else if (name === 'VideoListPage') {
      VideoListPage();
    } else if (name === 'MessageListPage') {
      MessageListPage();
    } else if (name === 'ChatPage') {
      ChatPage();
    }
  }

  aboutToAppear(): void {
    this.pageStack.setInterception({
      willShow: (_from: NavDestinationContext | NavBar, to: NavDestinationContext | NavBar,
        operation: NavigationOperation, _isAnimated: boolean) => {
        if (operation === NavigationOperation.POP && to === 'navBar') {
          AppStorage.get<common.UIAbilityContext>("UiAbilityContext")?.terminateSelf().catch(() => {
            this.pageStack.clear();
          });
        }
      }
    })
  }

  build() {
    Navigation(this.pageStack) {
      Column()
    }
    .navDestination(this.pageMap)
    .onAppear(() => {
      if (this.initialized) {
        return;
      }
      this.initialized = true;
      if (!AppStorage.get<boolean>('isAgreementAccepted')) {
        this.pageStack.pushPath({ name: "OOBE", param: "" });
      } else {
        if (AppStorage.get<string>('AccountData') !== 'null') {
          restoreCookiesFromStorage();
          checkCookieRefreshIfNeeded().then((refreshed: boolean) => {
            if (refreshed) {
              this.getUIContext().getPromptAction().showToast({ message: 'Cookie 已自动刷新' });
            }
          });
          checkLoginStatus().then((status: LoginCheckStatus) => {
            if (status === LoginCheckStatus.INVALID) {
              this.getUIContext().getPromptAction().showToast({ message: '登录状态已失效，请重新登录' });
              AppStorage.set<String>('AccountData', 'null');
              AppStorage.set<String>('refresh_token', "");
            } else if (status === LoginCheckStatus.VALID) {
              getMyAccountInfo().then((info: MyAccountInfo | null) => {
                AppStorage.set<number>('mid', info?.mid)
              })
            } else if (status === LoginCheckStatus.ERROR) {
              this.getUIContext().getPromptAction().showToast({ message: '网络错误！' });
              AppStorage.set<number>('mid', 0)
            }
          });
        }
        this.pageStack.pushPath({ name: "Rcmd", param: "" });
      }
      console.info("[Index] 加载已完成！")
    })
  }
}
