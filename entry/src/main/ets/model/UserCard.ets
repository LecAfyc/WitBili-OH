export class UserCard {
  name: string = '';
  headImage: string = '';
  mid: number = 0;

  // 以下内容非必要，部分B站Api也不会给
  /** 是否为大会员 */
  isVip?: boolean = undefined;
  /** 用户等级：0,1,2,3,4,5,6,h */
  level?: string = undefined;
  /** 个性签名 **/
  desc?: string = undefined;

  constructor(name?: string, headImage?: string, uid?: number, isVip?: boolean, level?: string, desc?: string) {
    if (name !== undefined) this.name = name;
    if (headImage !== undefined) this.headImage = headImage;
    if (uid !== undefined) this.mid = uid;
    if (isVip !== undefined) this.isVip = isVip;
    if (level !== undefined) this.level = level;
    if (desc !== undefined) this.desc = desc;
  }
}

export class UserDetailCard extends UserCard{
  sex: string = ""  // 男/女/保密
  silence: boolean = false;  //是否被封号
  is_followed: boolean = false;  //我是否为该用户粉丝
  followings: number = 0;   //关注数
  followers: number = 0;   //粉丝数
  favourites: number = 0;   //（公开）收藏夹数
  video: number = 0;    //投稿视频数
  opus: number = 0;    //发送动态数
  constructor(name: string, headImage: string, uid: number, isVip: boolean, level: string, desc: string, sex: string, silence: boolean, is_followed: boolean, followings: number, followers: number, favourites: number, video: number, opus: number) {
    super(name, headImage, uid, isVip, level, desc);
    this.sex = sex;
    this.silence = silence;
    this.is_followed = is_followed;
    this.followings = followings;
    this.followers = followers;
    this.favourites = favourites;
    this.video = video;
    this.opus = opus;
  }
}
