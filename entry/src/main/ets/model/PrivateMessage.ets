/**
 * 私信相关数据模型
 *
 */

import { VideoCard } from './ContentCard';

// ===== 私信会话 =====

export class PrivateMessageSession {
  talkerId: number = 0;
  talkerName: string = '';
  talkerAvatar: string = '';
  lastMsgType: number = 0;
  lastMsgContent: string = '';
  lastMsgTimestamp: number = 0;
  unreadCount: number = 0;
  sessionType: number = 1;
  maxSeqno: number = 0;

  constructor(talkerId?: number, talkerName?: string, talkerAvatar?: string, lastMsgType?: number,
    lastMsgContent?: string, lastMsgTimestamp?: number, unreadCount?: number, sessionType?: number,
    maxSeqno?: number) {
    if (talkerId !== undefined) {
      this.talkerId = talkerId;
    }
    if (talkerName !== undefined) {
      this.talkerName = talkerName;
    }
    if (talkerAvatar !== undefined) {
      this.talkerAvatar = talkerAvatar;
    }
    if (lastMsgType !== undefined) {
      this.lastMsgType = lastMsgType;
    }
    if (lastMsgContent !== undefined) {
      this.lastMsgContent = lastMsgContent;
    }
    if (lastMsgTimestamp !== undefined) {
      this.lastMsgTimestamp = lastMsgTimestamp;
    }
    if (unreadCount !== undefined) {
      this.unreadCount = unreadCount;
    }
    if (sessionType !== undefined) {
      this.sessionType = sessionType;
    }
    if (maxSeqno !== undefined) {
      this.maxSeqno = maxSeqno;
    }
  }
}

// ===== 私信消息 =====

export class PrivateMessage {
  senderUid: number = 0;
  receiverType: number = 1;
  receiverId: number = 0;
  msgType: number = 0;
  content: string = '';
  contentParsed: Record<string, Object> | null = null;
  msgSeqno: number = 0;
  timestamp: number = 0;
  msgKey: number = 0;
  msgStatus: number = 0;
  emoteMap: Map<string, string> = new Map();
  videoCard: VideoCard | null = null;

  constructor(senderUid?: number, receiverType?: number, receiverId?: number, msgType?: number,
    content?: string, contentParsed?: Record<string, Object> | null, msgSeqno?: number, timestamp?: number,
    msgKey?: number, msgStatus?: number, emoteMap?: Map<string, string>, videoCard?: VideoCard | null) {
    if (senderUid !== undefined) {
      this.senderUid = senderUid;
    }
    if (receiverType !== undefined) {
      this.receiverType = receiverType;
    }
    if (receiverId !== undefined) {
      this.receiverId = receiverId;
    }
    if (msgType !== undefined) {
      this.msgType = msgType;
    }
    if (content !== undefined) {
      this.content = content;
    }
    if (contentParsed !== undefined) {
      this.contentParsed = contentParsed;
    }
    if (msgSeqno !== undefined) {
      this.msgSeqno = msgSeqno;
    }
    if (timestamp !== undefined) {
      this.timestamp = timestamp;
    }
    if (msgKey !== undefined) {
      this.msgKey = msgKey;
    }
    if (msgStatus !== undefined) {
      this.msgStatus = msgStatus;
    }
    if (emoteMap !== undefined) {
      this.emoteMap = emoteMap;
    }
    if (videoCard !== undefined) {
      this.videoCard = videoCard;
    }
  }
}
