import { UserCard } from "./UserCard";


export class SingleComment {
  rpid: number = 0; //评论id
  oid: number = 0; //评论区对象id（视频aid等）
  sender: UserCard = new UserCard(); //发送者
  isOnTop: boolean = false; //是否置顶，置顶的要在内容开头加一个“置顶”标识
  time_desc: string = ""; //后端返回的已格式化时间
  ip_desc: string = ""; //后端返回的已格式化的用户IP属地
  message: string = ""; //评论本体
  memberMap: Map<string, UserCard> = new Map(); //@到的用户列表，在Api阶段解析为用户名 -> UserCard的映射
  emoteMap: Map<string, string> = new Map(); //表情转义符，"[表情名]" -> 图片链接的映射
  pictures: string[] = []; //评论附带的图片的url
  likes: number = 0; //点赞数
  replys: number = 0; //回复数
  hotReply: string[] = ["", ""] //精选回复，0-2个
  action: number = 0; //当前用户操作：0=无 1=已点赞 2=已点踩

  constructor(sender?: UserCard, isOnTop?: boolean, time_desc?: string, ip_desc?: string, message?: string,
    memberMap?: Map<string, UserCard>, emoteMap?: Map<string, string>, pictures?: string[], likes?: number,
    replys?: number, rpid?: number, action?: number) {
    if (sender !== undefined) {
      this.sender = sender;
    }
    if (isOnTop !== undefined) {
      this.isOnTop = isOnTop;
    }
    if (time_desc !== undefined) {
      this.time_desc = time_desc;
    }
    if (ip_desc !== undefined) {
      this.ip_desc = ip_desc;
    }
    if (message !== undefined) {
      this.message = message;
    }
    if (memberMap !== undefined) {
      this.memberMap = memberMap;
    }
    if (emoteMap !== undefined) {
      this.emoteMap = emoteMap;
    }
    if (pictures !== undefined) {
      this.pictures = pictures;
    }
    if (likes !== undefined) {
      this.likes = likes;
    }
    if (replys !== undefined) {
      this.replys = replys;
    }
    if (rpid !== undefined) {
      this.rpid = rpid;
    }
    if (action !== undefined) {
      this.action = action;
    }
  }
}
