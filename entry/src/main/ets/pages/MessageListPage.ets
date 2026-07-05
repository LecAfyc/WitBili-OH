/**
 * 私信会话列表页
 *
 * 显示用户间的私信会话列表，每项使用 UserCardComponent 渲染。
 */

import { LengthMetrics } from '@kit.ArkUI';
import { PrivateMessageSession } from '../model/PrivateMessage';
import { UserCard } from '../model/UserCard';
import { UserCardComponentStatic } from '../components/UserCardComponentStatic';
import { getSessions } from '../api/MessageApi';

@Component
export struct MessageListPage {
  @Consume('pageStack') pageStack: NavPathStack;
  // ===== 状态 =====
  @State sessions: PrivateMessageSession[] = [];
  @State isLoading: boolean = false;
  @State errorMessage: string = '';
  @State firstLoad: boolean = true;

  aboutToAppear(): void {
    this.loadSessions();
  }

  build() {
    NavDestination() {
      Stack() {
        Column() {
          this.HeaderBar()
          this.MainContent()
        }
        .width('100%').height('100%')
        .padding({
          left: 16,
          right: 16,
          top: 8,
          bottom: 16
        })
      }
      .width('100%').height('100%')
    }
    .height('100%')
    .width('100%')
    .hideBackButton(true)
    .hideTitleBar(true)
    .backgroundImage($r("app.media.oobe"))
  }

  // ==========================
  //        顶栏
  // ==========================
  @Builder
  HeaderBar() {
    Row() {
      Row() {
        Circle().width(8).height(8).fill('#FB7299')
        Text('私信').fontSize(16).fontColor('#EEEEEE')
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

  // ==========================
  //        主内容区
  // ==========================
  @Builder
  MainContent() {
    if (this.firstLoad && this.isLoading) {
      Column() {
        LoadingProgress().width(40).height(40).color('#FB7299')
        Text('加载中...').fontSize(15).fontColor('#666666').margin({ top: 12 })
      }
      .width('100%').height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    } else if (this.sessions.length === 0) {
      Column() {
        Text('暂无私信').fontSize(16).fontColor('#888888')
        if (this.errorMessage) {
          Text(this.errorMessage)
            .fontSize(14)
            .fontColor('#666666')
            .textAlign(TextAlign.Center)
            .margin({ top: 8 })
            .lineHeight(20)
        }
        Text('点击刷新').fontSize(13).fontColor('#FB7299').margin({ top: 16 })
          .onClick(() => {
            this.loadSessions();
          })
      }
      .width('100%').height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    } else {
      List({ space: 8 }) {
        ForEach(this.sessions, (session: PrivateMessageSession, index?: number) => {
          ListItem() {
            UserCardComponentStatic({
              card: new UserCard(session.talkerName, session.talkerAvatar, session.talkerId),
              extraInfo: session.lastMsgContent,
              baseFontSize: 13
            })
              .onClick(() => {
                console.info('[MessageListPage] 点击会话: ' + session.talkerId + ' ' + session.talkerName);
                let chatParam: Record<string, Object> = {
                  'talkerId': session.talkerId,
                  'talkerName': session.talkerName,
                  'talkerAvatar': session.talkerAvatar
                };
                this.pageStack.pushPath({ name: 'ChatPage', param: chatParam });
              })
          }
        })
      }
      .width('100%')
      .height('100%')
      .edgeEffect(EdgeEffect.Spring)
      .fadingEdge(true, { fadingEdgeLength: LengthMetrics.vp(20) })
      .focusable(true)
      .focusOnTouch(true)
      .defaultFocus(true)
    }
  }

  // ===== 数据加载 =====
  private async loadSessions(): Promise<void> {
    if (this.isLoading) {
      return;
    }
    this.isLoading = true;
    this.errorMessage = '';

    try {
      let list: PrivateMessageSession[] = await getSessions();
      this.sessions = list;
      this.firstLoad = false;
      if (list.length === 0) {
        this.errorMessage = '暂无用户私信会话';
      }
    } catch (e) {
      console.error('[MessageListPage] 加载失败: ' + String(e));
      this.errorMessage = '网络开小差了\n下拉重试';
      this.firstLoad = false;
    } finally {
      this.isLoading = false;
    }
  }

  // ===== 显示导航菜单 =====
  private showNavMenu(): void {
    this.pageStack.pushPath({ name: 'Menu' });
  }
}
