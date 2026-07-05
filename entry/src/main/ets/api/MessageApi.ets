/**
 * 私信 API
 *
 */

import { httpGet, httpPostForm, ApiResponse, safeJsonParse } from './CommonApi';
import { getCookieValue } from './CookiesApi';
import { PrivateMessageSession, PrivateMessage } from '../model/PrivateMessage';
import { VideoCard } from '../model/ContentCard';
import { formatCount } from './CommonApi';
import { getBatchUserCards } from './UserApi';

// ===== 常量 =====

const API_GET_SESSIONS: string =
  'https://api.vc.bilibili.com/session_svr/v1/session_svr/get_sessions?session_type=1&group_fold=0&unfollow_fold=0&sort_rule=2&size=50&build=0&mobi_app=web';

const API_FETCH_MSGS_BASE: string =
  'https://api.vc.bilibili.com/svr_sync/v1/svr_sync/fetch_session_msgs';

const API_SEND_MSG: string = 'https://api.vc.bilibili.com/web_im/v1/web_im/send_msg';

const API_VIDEO_INFO_BASE: string = 'https://api.vc.bilibili.com/card_center/v1/card/view_list';

// ===== 返回类型 =====

export interface FetchMessagesResult {
  messages: PrivateMessage[];
  hasMore: boolean;
  emoteMap: Map<string, string>;
  minSeqno: number;
  maxSeqno: number;
}

export interface SendMessageResult {
  success: boolean;
  msgKey: number;
  message: string;
}

// ===== UUID 生成 =====

function generateUUID(): string {
  let chars: string = '0123456789abcdef';
  let pattern: string = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx';
  let result: string = '';
  for (let i: number = 0; i < pattern.length; i++) {
    let c: string = pattern[i];
    if (c === 'x') {
      let r: number = Math.floor(Math.random() * 16);
      result += chars[r];
    } else if (c === 'y') {
      let r: number = Math.floor(Math.random() * 16);
      result += chars[(r & 0x3) | 0x8];
    } else {
      result += c;
    }
  }
  return result;
}

// ===== 辅助：解析 e_infos 为表情映射 =====

function parseEmoteInfos(eInfos: Object[] | undefined): Map<string, string> {
  let emoteMap: Map<string, string> = new Map();
  if (!eInfos) {
    return emoteMap;
  }
  for (let i: number = 0; i < eInfos.length; i++) {
    let item: Record<string, Object> = eInfos[i] as Record<string, Object>;
    let text: string = (item['text'] as string) || '';
    let url: string = (item['url'] as string) || '';
    let size: number = (item['size'] as number) || 1;
    // emoji name: remove brackets "[doge]" → "doge"
    let name: string = text;
    if (name.length >= 2 && name.charAt(0) === '[' && name.charAt(name.length - 1) === ']') {
      name = name.substring(1, name.length - 1);
    }
    if (url && name) {
      emoteMap.set(name, url + '||' + size);
    }
  }
  return emoteMap;
}

// ===== 辅助：从 last_msg 提取纯文本预览 =====

function extractLastMsgPreview(lastMsg: Record<string, Object> | undefined): string {
  if (!lastMsg) {
    return '';
  }
  let msgType: number = Number(lastMsg['msg_type']) || 0;
  let content: string = (lastMsg['content'] as string) || '';

  if (msgType === 5) {
    return '消息已被撤回';
  }

  if (msgType === 1) {
    let parsed: Record<string, Object> | null = safeJsonParse(content);
    if (parsed && parsed['content']) {
      return (parsed['content'] as string) || '';
    }
    return content;
  }

  if (msgType === 11) {
    return '[视频分享]';
  }

  return '[消息]';
}

// ===== T002: getSessions =====

/**
 * 获取私信会话列表
 * 过滤 system_msg_type !== 0 的会话（系统消息/粉丝团），仅保留用户间私信
 */
export async function getSessions(): Promise<PrivateMessageSession[]> {
  let sessions: PrivateMessageSession[] = [];

  try {
    let resp: ApiResponse = await httpGet(API_GET_SESSIONS);

    if (resp.code !== 0 || !resp.data) {
      console.warn('[MessageApi] getSessions 失败: code=' + resp.code + ' msg=' + resp.message);
      return sessions;
    }

    let data: Record<string, Object> = resp.data as Record<string, Object>;
    let sessionList: Object[] | undefined = data['session_list'] as Object[] | undefined;

    if (!sessionList) {
      return sessions;
    }

    for (let i: number = 0; i < sessionList.length; i++) {
      let item: Record<string, Object> = sessionList[i] as Record<string, Object>;

      // 过滤：只保留 system_msg_type === 0 的用户会话
      let systemMsgType: number = Number(item['system_msg_type']) || 0;
      if (systemMsgType !== 0) {
        continue;
      }

      // talker 信息在 account_info 中
      let accountInfo: Record<string, Object> | undefined = item['account_info'] as Record<string, Object> | undefined;
      let talkerId: number = Number(item['talker_id']) || 0;
      let talkerName: string = '';
      let talkerAvatar: string = '';
      if (accountInfo) {
        talkerName = (accountInfo['name'] as string) || '';
        talkerAvatar = (accountInfo['pic_url'] as string) || '';
      }

      // 最近消息预览
      let lastMsg: Record<string, Object> | undefined = item['last_msg'] as Record<string, Object> | undefined;
      let lastMsgContent: string = extractLastMsgPreview(lastMsg);
      let lastMsgType: number = lastMsg ? ((lastMsg['msg_type'] as number) ?? 0) : 0;
      let lastMsgTimestamp: number = lastMsg ? (Number(lastMsg['timestamp']) || 0) : 0;

      let session: PrivateMessageSession = new PrivateMessageSession(
        talkerId,
        talkerName,
        talkerAvatar,
        lastMsgType,
        lastMsgContent,
        lastMsgTimestamp,
        (Number(item['unread_count']) || 0),
        (Number(item['session_type']) || 1),
        (Number(item['max_seqno']) || 0)
      );

      sessions.push(session);
    }

    // 批量获取用户信息填充名称和头像
    if (sessions.length > 0) {
      let uids: number[] = [];
      for (let i: number = 0; i < sessions.length; i++) {
        uids.push(sessions[i].talkerId);
      }
      let cardMap: Map<number, import('../model/UserCard').UserCard> = await getBatchUserCards(uids);
      for (let i: number = 0; i < sessions.length; i++) {
        let card: import('../model/UserCard').UserCard | undefined = cardMap.get(sessions[i].talkerId);
        if (card) {
          sessions[i].talkerName = card.name;
          sessions[i].talkerAvatar = card.headImage;
        } else if (!sessions[i].talkerName) {
          // 降级：cards API 也未返回名称
          sessions[i].talkerName = '用户' + sessions[i].talkerId;
        }
      }
    }

    console.info('[MessageApi] getSessions 成功: ' + sessions.length + ' 个会话');
  } catch (e) {
    console.error('[MessageApi] getSessions 异常: ' + String(e));
  }

  return sessions;
}

// ===== T003: fetchMessages =====

/**
 * 获取指定会话的历史消息
 * @param talkerId 对方用户 mid
 */
export async function fetchMessages(talkerId: number): Promise<FetchMessagesResult> {
  let result: FetchMessagesResult = {
    messages: [],
    hasMore: false,
    emoteMap: new Map(),
    minSeqno: 0,
    maxSeqno: 0
  };

  try {
    let url: string = API_FETCH_MSGS_BASE +
      '?talker_id=' + talkerId +
      '&session_type=1' +
      '&size=50';

    let resp: ApiResponse = await httpGet(url);

    if (resp.code !== 0 || !resp.data) {
      console.warn('[MessageApi] fetchMessages 失败: code=' + resp.code + ' msg=' + resp.message);
      return result;
    }

    let data: Record<string, Object> = resp.data as Record<string, Object>;

    console.info("[MessageApi] resp = " + JSON.stringify(resp))
    // 解析 e_infos → emoteMap
    let eInfos: Object[] | undefined = data['e_infos'] as Object[] | undefined;
    let emoteMap: Map<string, string> = parseEmoteInfos(eInfos);
    result.emoteMap = emoteMap;
    console.info('[MessageApi] fetchMessages emote 数量: ' + emoteMap.size);

    // 框架信息
    let hasMore: number = Number(data['has_more']) || 0;
    result.hasMore = hasMore === 1;
    result.minSeqno = Number(data['min_seqno']) || 0;
    result.maxSeqno = Number(data['max_seqno']) || 0;

    // 解析 messages 数组
    let messages: Object[] | undefined = data['messages'] as Object[] | undefined;
    if (!messages) {
      return result;
    }

    for (let i: number = 0; i < messages.length; i++) {
      let msgObj: Record<string, Object> = messages[i] as Record<string, Object>;
      let msg: PrivateMessage = new PrivateMessage();

      msg.senderUid = Number(msgObj['sender_uid']) || 0;
      msg.receiverType = Number(msgObj['receiver_type']) || 1;
      msg.receiverId = Number(msgObj['receiver_id']) || 0;
      msg.msgType = Number(msgObj['msg_type']) || 0;
      msg.content = (msgObj['content'] as string) || '';
      msg.msgSeqno = Number(msgObj['msg_seqno']) || 0;
      msg.timestamp = Number(msgObj['timestamp']) || 0;
      msg.msgKey = Number(msgObj['msg_key']) || 0;
      msg.msgStatus = Number(msgObj['msg_status']) || 0;
      msg.emoteMap = emoteMap;

      // 解析 content JSON
      let contentParsed: Record<string, Object> | null = safeJsonParse(msg.content);
      msg.contentParsed = contentParsed;

      // msg_type=7 或 msg_type=11: 解析为 VideoCard
      if ((msg.msgType === 7 || msg.msgType === 11) && contentParsed) {
        // 新格式: {id, title, thumb, author, author_id, source, headline}
        // 旧格式: {rid, type_, bvid, title, cover, desc, view, danmaku, pub_date}
        let aid: number = Number(contentParsed['id']) || Number(contentParsed['rid']) || 0;
        let title: string = (contentParsed['title'] as string) || '';
        let cover: string = (contentParsed['thumb'] as string) || (contentParsed['cover'] as string) || '';
        let upName: string = (contentParsed['author'] as string) || '';
        let bvid: string = (contentParsed['bvid'] as string) || '';

        let videoCard: VideoCard = new VideoCard(
          title,
          upName,
          '',
          cover,
          aid,
          bvid
        );
        msg.videoCard = videoCard;
      }

      result.messages.push(msg);
    }

    console.info('[MessageApi] fetchMessages 成功: ' + result.messages.length + ' 条消息');
  } catch (e) {
    console.error('[MessageApi] fetchMessages 异常: ' + String(e));
  }

  return result;
}

// ===== T004: sendTextMessage =====

/**
 * 发送文字私信
 * @param receiverId 接收者 uid
 * @param text 消息文本
 * @param senderUid 发送者 uid（当前登录用户的 mid）
 */
export async function sendTextMessage(receiverId: number, text: string,
  senderUid: number): Promise<SendMessageResult> {
  let result: SendMessageResult = {
    success: false,
    msgKey: 0,
    message: ''
  };

  // 获取 csrf token
  let csrf: string = getCookieValue('bili_jct');
  if (!csrf) {
    result.message = '登录状态已失效，请重新登录';
    console.warn('[MessageApi] sendTextMessage: bili_jct 为空');
    return result;
  }

  // 构建消息体
  let devId: string = generateUUID();
  let timestamp: number = Math.floor(Date.now() / 1000);

  // content 字段需要双重 JSON 编码：{"content":"{text}"}
  let contentJson: string = '{"content":' + JSON.stringify(text) + '}';

  let formData: string =
    'msg[sender_uid]=' + senderUid +
    '&msg[receiver_id]=' + receiverId +
    '&msg[receiver_type]=1' +
    '&msg[msg_type]=1' +
    '&msg[msg_status]=0' +
    '&msg[dev_id]=' + devId +
    '&msg[timestamp]=' + timestamp +
    '&msg[new_face_version]=1' +
    '&msg[content]=' + encodeURIComponent(contentJson) +
    '&csrf=' + encodeURIComponent(csrf) +
    '&csrf_token=' + encodeURIComponent(csrf);

  console.info('[MessageApi] sendTextMessage: receiver=' + receiverId + ' len=' + text.length);

  try {
    let resp: ApiResponse = await httpPostForm(API_SEND_MSG, formData);

    console.info('[MessageApi] sendTextMessage 响应: code=' + resp.code + ' msg=' + resp.message);

    if (resp.code === 0) {
      result.success = true;
      result.message = '发送成功';
      // 从 data 中提取 msg_key
      if (resp.data) {
        let data: Record<string, Object> = resp.data as Record<string, Object>;
        result.msgKey = (data['msg_key'] as number) ?? 0;
      }
    } else if (resp.code === -111 || resp.code === -101) {
      result.message = '登录状态已失效，请重新登录';
    } else if (resp.code === 21013) {
      result.message = '对方已将你拉黑';
    } else if (resp.code === 21016) {
      result.message = '你已被对方禁言';
    } else {
      result.message = '发送失败(' + resp.code + '): ' + resp.message;
    }
  } catch (e) {
    result.message = '网络异常: ' + String(e);
    console.error('[MessageApi] sendTextMessage 异常: ' + String(e));
  }

  return result;
}

// ===== T005: getVideoInfo =====

/**
 * 根据 aid 批量获取视频信息
 * @param aids 视频 aid 数组
 */
export async function getVideoInfo(aids: number[]): Promise<VideoCard[]> {
  let videoCards: VideoCard[] = [];

  if (aids.length === 0) {
    return videoCards;
  }

  // 拼接逗号分隔的 aids
  let aidsStr: string = aids[0].toString();
  for (let i: number = 1; i < aids.length; i++) {
    aidsStr += ',' + aids[i];
  }

  try {
    let url: string = API_VIDEO_INFO_BASE +
      '?aids=' + aidsStr +
      '&build=0' +
      '&mobi_app=web';

    let resp: ApiResponse = await httpGet(url);

    if (resp.code !== 0 || !resp.data) {
      console.warn('[MessageApi] getVideoInfo 失败: code=' + resp.code + ' msg=' + resp.message);
      return videoCards;
    }

    let data: Record<string, Object> = resp.data as Record<string, Object>;
    let archiveList: Object[] | undefined = data['archive'] as Object[] | undefined;

    if (!archiveList) {
      return videoCards;
    }

    for (let i: number = 0; i < archiveList.length; i++) {
      let archive: Record<string, Object> = archiveList[i] as Record<string, Object>;

      let videoCard: VideoCard = new VideoCard(
        (archive['title'] as string) || '',
        (archive['up_name'] as string) || '',
        formatCount((archive['view'] as number) ?? 0),
        (archive['pic'] as string) || '',
        (archive['aid'] as number) ?? 0,
        (archive['bvid'] as string) || ''
      );

      videoCards.push(videoCard);
    }

    console.info('[MessageApi] getVideoInfo 成功: ' + videoCards.length + ' 个视频');
  } catch (e) {
    console.error('[MessageApi] getVideoInfo 异常: ' + String(e));
  }

  return videoCards;
}
