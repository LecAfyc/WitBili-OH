/**
 * 聊天页面
 *
 * 显示与指定用户的私信历史，支持文字（含内嵌表情）、视频分享卡片渲染。
 */

import { LengthMetrics } from '@kit.ArkUI';
import { PrivateMessage } from '../model/PrivateMessage';
import { fetchMessages, FetchMessagesResult, sendTextMessage } from '../api/MessageApi';
import { getVideoDetail, VideoDetailResult } from '../api/VideoDetailApi';
import { VideoCardComponent } from '../components/VideoCardComponent';
import { VideoCard } from '../model/ContentCard';
import { getCookieValue } from '../api/CookiesApi';

// ===== 段类型（用于消息文本+表情混合渲染） =====

enum SegKind { TEXT, EMOJI }

interface Seg {
  kind: SegKind;
  text: string;
  emojiUrl?: string;
  emojiSize?: number;
}

// ===== 聊天参数接口 =====

interface ChatParams {
  talkerId: number;
  talkerName: string;
  talkerAvatar: string;
}

@Component
export struct ChatPage {
  @Consume('pageStack') pageStack: NavPathStack;
  // ===== 路由参数 =====
  @State talkerId: number = 0;
  @State talkerName: string = '';
  @State talkerAvatar: string = '';

  // ===== 状态 =====
  @State messages: PrivateMessage[] = [];
  @State isLoading: boolean = false;
  @State errorMessage: string = '';
  @State firstLoad: boolean = true;
  @State emoteMap: Map<string, string> = new Map();
  @State myUid: number = 0;
  @State inputText: string = '';
  @State isSending: boolean = false;

  // 消息列表引用（用于滚动到底部）
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    // 获取当前用户 mid
    let dedeUserId: string = getCookieValue('DedeUserID');
    if (dedeUserId) {
      this.myUid = parseInt(dedeUserId);
    } else {
      this.myUid = AppStorage.get<number>('mid') ?? 0;
    }
  }

  build() {
    NavDestination() {
      Column() {
        this.MessageList()
        this.InputArea()
      }
      .width('100%').height('100%')
      .padding({
        left: 16,
        right: 16,
        top: 8,
        bottom: 16
      })
    }
    .height('100%')
    .width('100%')
    .hideBackButton(true)
    .hideTitleBar(true)
    .backgroundImage($r("app.media.oobe"))
    .onReady((context: NavDestinationContext) => {
      let incoming: Record<string, Object> = context.pathInfo.param as Record<string, Object>;
      if (incoming) {
        this.talkerId = (incoming['talkerId'] as number) ?? 0;
        this.talkerName = (incoming['talkerName'] as string) || '';
        this.talkerAvatar = (incoming['talkerAvatar'] as string) || '';
        console.info('[ChatPage] onReady: talkerId=' + this.talkerId + ' name=' + this.talkerName);
        this.loadMessages();
      }
    })
  }

  // ==========================
  //        消息列表
  // ==========================
  @Builder
  MessageList() {
    if (this.firstLoad && this.isLoading) {
      Column() {
        LoadingProgress().width(40).height(40).color('#FB7299')
        Text('加载中...').fontSize(15).fontColor('#666666').margin({ top: 12 })
      }
      .width('100%').height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    } else if (this.messages.length === 0 && !this.isLoading) {
      Column() {
        Text('暂无消息').fontSize(16).fontColor('#888888')
        if (this.errorMessage) {
          Text(this.errorMessage)
            .fontSize(14)
            .fontColor('#666666')
            .textAlign(TextAlign.Center)
            .margin({ top: 8 })
        }
        Text('点击刷新').fontSize(13).fontColor('#FB7299').margin({ top: 16 })
          .onClick(() => {
            this.loadMessages();
          })
      }
      .width('100%').height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    } else {
      List({ space: 8, scroller: this.scroller }) {
        ForEach(this.messages, (msg: PrivateMessage, index?: number) => {
          ListItem() {
            this.MessageItem(msg)
          }
        })
      }
      .width('100%')
      .layoutWeight(1)
      .edgeEffect(EdgeEffect.Spring)
      .fadingEdge(true, { fadingEdgeLength: LengthMetrics.vp(10) })
      .focusable(true)
      .focusOnTouch(true)
      .defaultFocus(true)
    }
  }

  // ==========================
  //       单条消息渲染
  // ==========================
  @Builder
  MessageItem(msg: PrivateMessage) {
    Column() {
      if (msg.msgType === 1) {
        // 文字消息
        this.TextMessage(msg)
      } else if (msg.msgType === 5) {
        // 撤回消息
        this.RecallMessage()
      } else if (msg.msgType === 11 || msg.msgType === 7) {
        // 视频分享
        this.VideoShareMessage(msg)
      } else {
        // 其他类型降级为纯文本
        this.TextMessage(msg)
      }
    }
    .width('100%')
    .alignItems(msg.senderUid === this.myUid ? HorizontalAlign.End : HorizontalAlign.Start)
  }

  // ==========================
  //       文字消息（含表情）
  // ==========================
  @Builder
  TextMessage(msg: PrivateMessage) {
    Row() {
      Column() {
        Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Start }) {
          ForEach(this.parseMessage(msg), (s: Seg) => {
            if (s.kind === SegKind.TEXT) {
              Text(s.text)
                .fontSize(13)
                .fontColor('#EEEEEE')
                .textAlign(TextAlign.Start)
            } else if (s.kind === SegKind.EMOJI) {
              Image(s.emojiUrl!)
                .width(s.emojiSize || 22)
                .height(s.emojiSize || 22)
                .objectFit(ImageFit.Contain)
                .margin({ left: 1, right: 1 })
            }
          })
        }
        .padding({ left: 10, right: 10, top: 8, bottom: 8 })
        .constraintSize({ maxWidth: '75%' })
      }
      .borderRadius(10)
      .backgroundColor(msg.senderUid === this.myUid ? '#FB7299' : 'rgba(22,22,22,0.9)')
    }
    .width('100%')
    .justifyContent(msg.senderUid === this.myUid ? FlexAlign.End : FlexAlign.Start)
    .padding({ left: 8, right: 8 })
  }

  // ==========================
  //        撤回消息
  // ==========================
  @Builder
  RecallMessage() {
    Text('消息已被撤回')
      .fontSize(12)
      .fontColor('#888888')
      .fontStyle(FontStyle.Italic)
      .padding({ top: 4, bottom: 4, left: 12, right: 12 })
  }

  // ==========================
  //       视频分享消息
  // ==========================
  @Builder
  VideoShareMessage(msg: PrivateMessage) {
    Column() {
      if (msg.videoCard) {
        VideoCardComponent({ card: msg.videoCard })
      } else {
        // 降级：显示文字
        Text('[视频分享]')
          .fontSize(12)
          .fontColor('#888888')
          .padding({ top: 4, bottom: 4, left: 12, right: 12 })
      }
    }
    .constraintSize({ maxWidth: '90%' })
    .padding({ left: 10, right: 10, top: 8, bottom: 8 })
  }

  // ==========================
  //        输入区域
  // ==========================
  @Builder
  InputArea() {
    Row() {
      TextInput({ text: $$this.inputText, placeholder: '输入消息...' })
        .placeholderColor('#666666')
        .placeholderFont({ size: 13 })
        .fontSize(13)
        .fontColor('#EEEEEE')
        .backgroundColor('rgba(22,22,22,0.8)')
        .borderRadius(8)
        .height(36)
        .layoutWeight(1)
        .padding({ left: 10, right: 10 })

      Button('↑')
        .fontSize(10)
        .fontColor('#FFFFFF')
        .backgroundColor(this.inputText.trim().length === 0 || this.isSending ? '#555555' : '#FB7299')
        .borderRadius(8)
        .height(36)
        .width(27)
        .margin({ left: 8 })
        .enabled(this.inputText.trim().length > 0 && !this.isSending)
        .onClick(() => {
          this.doSend();
        })
    }
    .width('100%')
    .padding({ top: 8, bottom: 4 , left: 12, right: 12})
    .alignItems(VerticalAlign.Center)
  }

  // ===== 发送消息 =====

  private async doSend(): Promise<void> {
    let text: string = this.inputText.trim();
    if (text.length === 0 || this.isSending) {
      return;
    }

    this.isSending = true;

    try {
      let result = await sendTextMessage(this.talkerId, text, this.myUid);
      if (result.success) {
        // 清空输入框
        this.inputText = '';
        // 刷新消息列表
        await this.loadMessages();
      } else {
        this.toast(result.message);
      }
    } catch (e) {
      this.toast('发送失败: ' + String(e));
      console.error('[ChatPage] doSend 异常: ' + String(e));
    } finally {
      this.isSending = false;
    }
  }

  private toast(msg: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: msg, duration: 2000 });
    } catch (e) {
      console.warn('[ChatPage] Toast 失败: ' + String(e));
    }
  }

  // ===== 消息文本 + 表情解析 =====

  /**
   * 解析消息文本中的 [表情名] 标记，映射到 emoteMap 中的表情图片
   */
  private parseMessage(msg: PrivateMessage): Seg[] {
    let text: string = '';
    // msg_type=1 的内容格式为 {"content": "文本内容"}
    if (msg.msgType === 1 && msg.contentParsed) {
      text = (msg.contentParsed['content'] as string) || '';
    } else {
      text = msg.content || '';
    }

    let segs: Seg[] = [];
    let idx: number = 0;
    // 正则匹配 [表情名]
    let re: RegExp = /\[([^\]]+)\]/g;
    let m: RegExpExecArray | null;

    while ((m = re.exec(text)) !== null) {
      // 匹配前的纯文本
      if (m.index > idx) {
        segs.push({ kind: SegKind.TEXT, text: text.slice(idx, m.index) });
      }

      // [表情名]
      if (m[1] !== undefined) {
        let val: string | undefined = this.emoteMap.get(m[1]);
        if (val) {
          let sep: number = val.indexOf('||');
          let url: string = sep !== -1 ? val.substring(0, sep) : val;
          let size: number = sep !== -1 ? (Number(val.substring(sep + 2)) || 1) : 1;
          segs.push({
            kind: SegKind.EMOJI,
            text: m[0],
            emojiUrl: url,
            emojiSize: size === 2 ? 30 : 22
          });
        } else {
          // 未找到表情，当纯文本
          segs.push({ kind: SegKind.TEXT, text: m[0] });
        }
      }

      idx = m.index + m[0].length;
    }

    // 尾部剩余文本
    if (idx < text.length) {
      segs.push({ kind: SegKind.TEXT, text: text.slice(idx) });
    }

    return this.mergeText(segs);
  }

  /** 合并相邻文本段 */
  private mergeText(segs: Seg[]): Seg[] {
    let out: Seg[] = [];
    let buf: string = '';
    for (let i: number = 0; i < segs.length; i++) {
      let s: Seg = segs[i];
      if (s.kind === SegKind.TEXT) {
        buf += s.text;
      } else {
        if (buf) {
          out.push({ kind: SegKind.TEXT, text: buf });
          buf = '';
        }
        out.push(s);
      }
    }
    if (buf) {
      out.push({ kind: SegKind.TEXT, text: buf });
    }
    return out;
  }

  // ===== 数据加载 =====

  private async loadMessages(): Promise<void> {
    if (this.isLoading) {
      return;
    }
    this.isLoading = true;
    this.errorMessage = '';

    try {
      let result: FetchMessagesResult = await fetchMessages(this.talkerId);
      this.messages = result.messages.reverse();
      this.emoteMap = result.emoteMap;
      this.firstLoad = false;

      // 视频消息缺失作者信息时用 VideoDetailApi 兜底（用于只有 id 的罕见情况）
      for (let i: number = 0; i < this.messages.length; i++) {
        let msg: PrivateMessage = this.messages[i];
        if ((msg.msgType === 7 || msg.msgType === 11) && msg.videoCard) {
          if (msg.videoCard.aid > 0 && !msg.videoCard.upName) {
            try {
              let detail: VideoDetailResult = await getVideoDetail(undefined, msg.videoCard.aid);
              msg.videoCard.upName = detail.up.name;
              msg.videoCard.formatedView = detail.pageParam.formatedView;
              msg.videoCard.bvid = detail.pageParam.bvid || msg.videoCard.bvid;
            } catch (e) {
              console.warn('[ChatPage] getVideoDetail 失败: ' + String(e));
            }
          }
        }
      }
      if (result.messages.length === 0) {
        this.errorMessage = '暂无消息记录';
      }
      // 滚动到底部（最新消息）
      setTimeout(() => {
        this.scroller.scrollEdge(Edge.Bottom);
      }, 100);
    } catch (e) {
      console.error('[ChatPage] 加载失败: ' + String(e));
      this.errorMessage = '加载失败，点击重试';
      this.firstLoad = false;
    } finally {
      this.isLoading = false;
    }
  }
}
