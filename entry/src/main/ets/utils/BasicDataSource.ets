/**
 * 通用 BasicDataSource —— LazyForEach 数据源适配器
 *
 * 用于替代 ForEach 实现长列表懒加载，大幅提升性能。
 * 由于本项目中数据几乎都是整体替换（而非增量修改），
 * 所有数据变更统一通过 notifyDataReload() 通知框架重绘。
 *
 * 用法：
 *   private videoDS: BasicDataSource<VideoCard> = new BasicDataSource<VideoCard>();
 *   // 赋值数据
 *   this.videoDS.resetData(newArray);
 *   // build 中
 *   LazyForEach(this.videoDS, (item: VideoCard) => { ... }, (item: VideoCard) => keyStr)
 */

export class BasicDataSource<T> implements IDataSource {
  private dataArray: T[] = [];
  private listeners: DataChangeListener[] = [];

  public totalCount(): number {
    return this.dataArray.length;
  }

  public getData(index: number): T {
    return this.dataArray[index];
  }

  /** 重置全部数据（用于首次加载 / 下拉刷新） */
  public resetData(items: T[]): void {
    this.dataArray = items;
    this.notifyDataReload();
  }

  /** 追加数据（用于加载更多） */
  public appendData(items: T[]): void {
    let arr: T[] = [];
    for (let i: number = 0; i < this.dataArray.length; i++) {
      arr.push(this.dataArray[i]);
    }
    for (let i: number = 0; i < items.length; i++) {
      arr.push(items[i]);
    }
    this.dataArray = arr;
    this.notifyDataReload();
  }

  /** 删除指定位置的一条数据 */
  public deleteData(index: number): void {
    if (index < 0 || index >= this.dataArray.length) {
      return;
    }
    let arr: T[] = [];
    for (let i: number = 0; i < this.dataArray.length; i++) {
      if (i !== index) {
        arr.push(this.dataArray[i]);
      }
    }
    this.dataArray = arr;
    this.notifyDataReload();
  }

  /** 获取底层数组（只读） */
  public getAllData(): T[] {
    return this.dataArray;
  }

  /** 截断到指定长度 */
  public trimTo(maxLen: number): void {
    if (this.dataArray.length > maxLen) {
      let arr: T[] = [];
      let start: number = this.dataArray.length - maxLen;
      for (let i: number = start; i < this.dataArray.length; i++) {
        arr.push(this.dataArray[i]);
      }
      this.dataArray = arr;
      this.notifyDataReload();
    }
  }

  // ===== IDataSource 必需实现 =====

  public registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  public unregisterDataChangeListener(listener: DataChangeListener): void {
    let idx: number = this.listeners.indexOf(listener);
    if (idx >= 0) {
      this.listeners.splice(idx, 1);
    }
  }

  public onDataReloaded(): void {
    for (let i: number = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataReloaded();
    }
  }

  public onDataAdd(index: number): void {
    for (let i: number = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataAdd(index);
    }
  }

  public onDataDelete(index: number): void {
    for (let i: number = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataDelete(index);
    }
  }

  public onDataChange(index: number): void {
    for (let i: number = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataChange(index);
    }
  }

  public onDataMove(from: number, to: number): void {
    for (let i: number = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataMove(from, to);
    }
  }

  // ===== 内部方法 =====

  private notifyDataReload(): void {
    for (let i: number = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataReloaded();
    }
  }
}
