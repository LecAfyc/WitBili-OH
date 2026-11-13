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
import {
  restoreCookies as restoreGuestCookies,
  checkCookies as checkGuestCookies,
  getCookieValue as getGuestCookieValue
} from '../api/CookiesApi';
import { common } from '@kit.AbilityKit';
import { connection } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
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
import { CacheDownloadPage } from './CacheDownloadPage';
import { CacheListPage } from './CacheListPage';

PersistentStorage.persistProp('AccountData', 'null');
PersistentStorage.persistProp('isAgreementAccepted', false);
PersistentStorage.persistProp('refresh_token', '');
PersistentStorage.persistProp('SearchHistory', '[]');
PersistentStorage.persistProp('ignoredUpdateVersionCode', 0);
PersistentStorage.persistProp('shownBroadcastTimestamps', '[]');
PersistentStorage.persistProp('CookiesApi_Data', '');
AppStorage.setOrCreate<number>('mid', 0);
AppStorage.setOrCreate<MyAccountInfo | null>('myself', null);

@Entry
@Component
struct Index {
  @Provide('pageStack') pageStack: NavPathStack = new NavPathStack();
  @State initialized: boolean = false
  private loginInitNeeded: boolean = false
  private netCon: connection.NetConnection = connection.createNetConnection()

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
    } else if (name === 'ImageViewer') {
      ImageViewPage();
    } else if (name === 'VideoDetail') {
      VideoDetailPage();
    } else if (name ===
      'CommentPage') {
      CommentPage();
    } else if (name === 'SearchPage') {
      SearchPage();
    } else if (name === 'SearchResultPage') {
      SearchResultPage();
    } else if (name === 'UserDetailPage') {
      UserDetailPage();
    } else if (name === 'DynamicListPage') {
      DynamicListPage();
    } else if (name === 'DynamicDetailPage') {
      DynamicDetailPage();
    } else if (name === 'ArticleDetailPage') {
      ArticleDetailPage();
    } else if (name === 'VideoPlayer') {
      VideoPlayerPage();
    } else if (name === 'VideoListPage') {
      VideoListPage();
    } else if (name === 'MessageListPage') {
      MessageListPage();
    } else if (name === 'ChatPage') {
      ChatPage();
    } else if (name === 'CacheDownload') {
      CacheDownloadPage();
    } else if (name === 'CacheList') {
      CacheListPage();
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

    this.netCon.on('netAvailable', () => {
      if (this.loginInitNeeded) {
        this.loginInitNeeded = false;
        this.tryLoginInit();
      }
    });
    this.netCon.register((error: BusinessError) => {
      if (error) {
        console.error('[Index] netCon.register failed: ' + JSON.stringify(error));
      }
    });
  }

  aboutToDisappear(): void {
    this.netCon.unregister((error: BusinessError) => {
      if (error) {
        console.error('[Index] netCon.unregister failed: ' + JSON.stringify(error));
      }
    });
  }

  private tryLoginInit(): void {
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
            AppStorage.set<number>('mid', info?.mid ?? 0)
          })
        } else if (status === LoginCheckStatus.ERROR) {
          this.getUIContext().getPromptAction().showToast({ message: '网络错误，将在恢复后重试' });
          this.loginInitNeeded = true
        }
      });
    }
  }

  /**
   * 确保访客 Cookie 环境就绪：
   *   1. 从持久化存储恢复访客环境 Cookie（跨启动）
   *   2. 已登录用户额外恢复登录态 Cookie
   *   3. 关键访客 Cookie 缺失时生成（checkCookies 幂等，只补缺失项）
   * 无论成功失败都不抛出，避免阻塞启动。
   */
  private ensureCookieEnv(): Promise<void> {
    restoreGuestCookies();
    if (AppStorage.get<string>('AccountData') !== 'null') {
      restoreCookiesFromStorage();
    }
    if (!getGuestCookieValue('_uuid') || !getGuestCookieValue('buvid3') || !getGuestCookieValue('buvid4')) {
      console.info('[Index] 访客 Cookie 环境不完整，开始生成...');
      return checkGuestCookies().catch((e: Error) => {
        console.warn('[Index] 生成访客 Cookie 环境失败: ' + JSON.stringify(e));
      });
    }
    console.info('[Index] 访客 Cookie 环境已就绪');
    return Promise.resolve();
  }

  /**
   * 启动推荐页：等待访客 Cookie 环境就绪（上限 1.5s，避免网络慢时卡启动），
   * 然后进入 Rcmd，保证首页推荐请求带上有效的 Cookie 环境。
   */
  private bootAfterAgreement(): void {
    let cookieTask: Promise<void> = this.ensureCookieEnv();
    let timeoutTask: Promise<void> = new Promise<void>((resolve) => {
      setTimeout(() => {
        resolve();
      }, 1500);
    });
    Promise.race([cookieTask, timeoutTask]).then(() => {
      this.pageStack.pushPath({ name: "Rcmd", param: "" });
    });
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
        this.tryLoginInit();
        this.bootAfterAgreement();
      }
      console.info("[Index] 加载已完成！")
    })
  }
}
