export class FavFolder {
  name: string = '';
  mlid: number = 0;
  fav_state: number = 0; // 仅当传入 rid 时有效，1=该视频已加入此收藏夹

  //Detail Information
  cover: string = '';
  ctime: number = 0;
  media_count: number = 0;

  constructor(name?: string, mlid?: number) {
    if (name !== undefined) {
      this.name = name;
    }
    if (mlid !== undefined) {
      this.mlid = mlid;
    }
  }
}
