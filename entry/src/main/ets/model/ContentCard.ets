export class ContentCard {
  title: string = '';
  upName: string = '';
  formatedView: string = '';

  constructor(title?: string, upName?: string, view?: string) {
    if (title !== undefined) {
      this.title = title;
    }
    if (upName !== undefined) {
      this.upName = upName;
    }
    if (view !== undefined) {
      this.formatedView = view;
    }
  }
}

export class VideoCard extends ContentCard {
  bvid: string = '';
  aid: number = 0;
  cover: string = "";

  constructor(title?: string, upName?: string, view?: string, cover?: string, aid?: number, bvid?: string) {
    super(title, upName, view);
    if (cover !== undefined) {
      this.cover = cover;
    }
    if (aid !== undefined) {
      this.aid = aid;
    }
    if (bvid !== undefined) {
      this.bvid = bvid;
    }
  }
}

export class ArticleCard extends ContentCard {
  cvid: number = 0;
  covers: string[] = [];

  constructor(title?: string, upName?: string, view?: string, covers?: string[], cvid?: number) {
    super(title, upName, view);
    if (covers !== undefined) {
      this.covers = covers;
    }
    if (cvid !== undefined) {
      this.cvid = cvid;
    }
  }
}