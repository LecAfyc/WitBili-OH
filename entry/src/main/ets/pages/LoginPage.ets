/**
 * 扫码登录页面（NavDestination）
 * 参考 QRLoginFragment.java + LoginActivity.java
 *
 * 取消按钮逻辑：
 *   页面栈内只有本页 → pop() 回到推荐页
 *   页面栈内有多页    → pop() 出栈
 */

import { checkCookies, generateQRCode, pollLoginState, saveLoginCookies, restoreCookiesFromStorage, requestSSOs, PollResult,
  checkCookieRefreshIfNeeded } from '../api/LoginApi';

const POLL_INTERVAL: number = 2000;
const QR_EXPIRE_MS: number = 180000;

@Component
export struct LoginPage {
  @Consume('pageStack') pageStack: NavPathStack;

  @State qrUrl: string = '';
  @State statusText: string = '获取二维码中...';
  @State isScanning: boolean = false;
  @State isExpired: boolean = false;
  @State isSuccess: boolean = false;

  private qrcodeKey: string = '';
  private timerId: number = -1;
  private startTime: number = 0;

  aboutToAppear(): void {
    this.startQRLogin();
  }

  aboutToDisappear(): void {
    this.stopPolling();
  }

  // ===== QR 流程 =====

  private async startQRLogin(): Promise<void> {
    try {
      this.statusText = '初始化环境...';
      // 第一步：从持久化恢复已有 Cookie
      restoreCookiesFromStorage();

      // 第二步：前置初始化浏览器 Cookie 环境（buvid3, _uuid, b_lsid 等）
      await checkCookies();

      // 第三步：获取二维码
      this.statusText = '获取二维码中...';
      let result = await generateQRCode();
      this.qrUrl = result.url;
      this.qrcodeKey = result.qrcodeKey;
      this.statusText = '请使用 B 站扫码';
      this.isExpired = false;
      this.startTime = Date.now();
      this.startPolling();
    } catch (e) {
      this.statusText = '获取二维码失败';
      console.error('[Login] 生成失败:', JSON.stringify(e));
    }
  }

  private startPolling(): void {
    this.stopPolling();
    this.isScanning = true;

    let poll: () => void = () => {
      if (!this.isScanning) return;
      if (Date.now() - this.startTime > QR_EXPIRE_MS) {
        this.statusText = '二维码已过期，点击刷新';
        this.isExpired = true;
        this.isScanning = false;
        return;
      }

      pollLoginState(this.qrcodeKey).then(async (result: PollResult) => {
        if (result.code === 0) {
          console.info("[Login]用户已确认登录，正在进行后处理")
          this.isScanning = false;
          this.isSuccess = true;
          this.statusText = '正在处理登录...';
          // 保存 cookies 到持久化存储
          if (result.data) {
            try {
              saveLoginCookies(result.data);
            } catch (e) {
              console.error('[Login] saveLoginCookies 异常:', JSON.stringify(e));
            }
          }
          // SSO Cookie 扩散
          requestSSOs().then(() => {
            this.statusText = '登录成功！';
            console.info('[Login] 登录流程全部完成');
          }).catch((e: Error) => {
            console.warn('[Login] SSO 扩散异常:', JSON.stringify(e));
            this.statusText = '登录成功！';
          });
          setTimeout(() => {
            this.pageStack.pop();
          }, 800);
        } else if (result.code === 86090) {
          this.statusText = '已扫码，请在手机上确认';
          this.timerId = setTimeout(poll, POLL_INTERVAL);
        } else if (result.code === 86101) {
          this.statusText = '请使用 B 站扫码';
          this.timerId = setTimeout(poll, POLL_INTERVAL);
        } else if (result.code === 86038) {
          this.statusText = '二维码已过期，点击刷新';
          this.isExpired = true;
          this.isScanning = false;
        } else {
          this.statusText = '状态异常 (' + result.code + ')';
          this.isScanning = false;
        }
      }).catch((e: Error) => {
        let errStr: string = (e && e.message) || JSON.stringify(e);
        console.error('[Login] 轮询失败:', errStr);
        this.statusText = '网络异常，重试中...';
        this.timerId = setTimeout(poll, POLL_INTERVAL);
      });
    };

    this.timerId = setTimeout(poll, POLL_INTERVAL);
  }

  private stopPolling(): void {
    this.isScanning = false;
    if (this.timerId !== -1) {
      clearTimeout(this.timerId);
      this.timerId = -1;
    }
  }

  private refreshQR(): void {
    this.isExpired = false;
    this.statusText = '获取二维码中...';
    this.startQRLogin();
  }

  private exitLogin(): void {
    this.stopPolling();
    this.pageStack.pop();
  }

  // ===== UI =====

  build() {
    NavDestination(){
        Column() {
          List(){
            // 标题
            ListItem() {
              Text('扫码登录')
                .fontSize(18)
                .fontColor('#EEEEEE')
                .fontWeight(FontWeight.Bold)
                .margin({ top: 10 })
                .width('100%')
                .textAlign(TextAlign.Center)
            }

            // 二维码
            ListItem() {
              Stack() {
                if (this.qrUrl) {
                  QRCode(this.qrUrl)
                    .width(150)
                    .height(150)
                    .backgroundColor('#FFFFFF')
                } else {
                  LoadingProgress().width(36).height(36).color('#FB7299')
                }

                if (this.isSuccess) {
                  Column() {
                    Text('✓').fontSize(64).fontColor('#FB7299').fontWeight(FontWeight.Bold)
                    Text('登录成功，即将重启App').fontSize(16).fontColor('#FFFFFF').margin({ top: 8 })
                  }
                  .width(200).height(200)
                  .justifyContent(FlexAlign.Center)
                  .alignItems(HorizontalAlign.Center)
                  .backgroundColor('#CC000000')
                  .borderRadius(12)
                }
              }
              .width('100%').height(170)
              .align(Alignment.Center)
              .margin({ bottom: 4 })
            }
            .align(Alignment.Center)
            // 状态
            ListItem() {
              Text(this.statusText)
                .fontSize(13)
                .fontColor('#999999')
                .width('100%')
                .textAlign(TextAlign.Center)
                .margin({ bottom: 4 })
                .onClick(() => {
                  if (this.isExpired) this.refreshQR();
                })
            }
            .align(Alignment.Center)

            ListItem() {
              Row(){
                Button('返回')
                  .fontSize(14)
                  .fontColor('#999999')
                  .backgroundColor('#2A2A2A')
                  .borderRadius(20)
                  .width(80)
                  .height(36)
                  .onClick(() => {
                    this.exitLogin();
                  })
              }
              .width('100%')
              .justifyContent(FlexAlign.Center)
            }
            .align(Alignment.Center)
        }
        .width('100%').height('100%')
        .focusable(true)
        .focusOnTouch(true)
        .defaultFocus(true)
      }
      .width('100%').height('100%')
    }
    .width('100%')
    .height('100%')
    .hideBackButton(true)
    .hideTitleBar(true)
  }
}
