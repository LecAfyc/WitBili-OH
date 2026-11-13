/**
 * 缓存视频列表页
 *
 * 展示沙箱中已缓存的视频，点击可离线播放，长按删除。
 */

import { LengthMetrics } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { CachedVideo } from '../model/CachedVideo';
import {
  createOfflinePlayParam,
  formatBytes,
  loadCachedVideos,
  removeCachedVideo
} from '../utils/VideoCacheStore';

@Component
export struct CacheListPage {
  @Consume('pageStack') pageStack: NavPathStack;
  @State videos: CachedVideo[] = [];

  build() {
    NavDestination() {
      Column() {
        this.HeaderBar()

        if (this.videos.length === 0) {
          this.EmptyView()
        } else {
          List({ space: 8 }) {
            ForEach(this.videos, (item: CachedVideo) => {
              ListItem() {
                this.CacheItem(item)
              }
              .gesture(
                LongPressGesture({ duration: 500 })
                  .onAction(() => {
                    this.confirmDelete(item);
                  })
              )
            }, (item: CachedVideo) => item.bvid + '_' + item.cid.toString() + '_' + item.qn.toString())
          }
          .width('100%')
          .layoutWeight(1)
          .edgeEffect(EdgeEffect.Spring)
          .fadingEdge(true, { fadingEdgeLength: LengthMetrics.vp(20) })
          .focusable(true)
          .focusOnTouch(true)
          .defaultFocus(true)
          .cachedCount(1)
        }
      }
      .width('100%')
      .height('100%')
      .padding({
        left: 16,
        right: 16,
        top: 8,
        bottom: 16
      })
    }
    .width('100%')
    .height('100%')
    .hideBackButton(true)
    .hideTitleBar(true)
    .backgroundImage($r('app.media.oobe'))
    .onReady(() => {
      this.reload();
    })
  }

  aboutToAppear(): void {
    this.reload();
  }

  @Builder
  HeaderBar() {
    Row() {
      Row() {
        Circle().width(8).height(8).fill('#FB7299')
        Text('缓存').fontSize(16).fontColor('#EEEEEE')
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

  private showNavMenu(): void {
    this.pageStack.pushPath({ name: 'Menu' });
  }

  @Builder
  EmptyView() {
    Column() {
      SymbolGlyph($r("sys.symbol.arrowshape_down_to_line_fill"))
        .fontSize(32)
        .fontColor(['#555555'])
      Text('暂无缓存视频')
        .fontSize(15)
        .fontColor('#888888')
        .margin({ top: 10 })
      Text('在视频详情页选择「更多 - 缓存」')
        .fontSize(11)
        .fontColor('#666666')
        .textAlign(TextAlign.Center)
        .margin({ top: 6 })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  CacheItem(item: CachedVideo) {
    Row() {
      Image(item.cover)
        .width(52)
        .height(34)
        .objectFit(ImageFit.Cover)
        .borderRadius(6)
        .alt($r('app.media.placeholder'))

      Column() {
        Text(item.title)
          .fontSize(13)
          .fontColor('#EEEEEE')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Row() {
          Text(item.qnName || ('qn' + item.qn.toString()))
            .fontSize(9)
            .fontColor('#FB7299')
            .padding({
              left: 5,
              right: 5,
              top: 1,
              bottom: 1
            })
            .borderRadius(4)
            .backgroundColor('rgba(251,114,153,0.15)')
          Text(formatBytes(item.totalBytes))
            .fontSize(9)
            .fontColor('#888888')
            .margin({ left: 6 })
          if (item.isDash) {
            Text('DASH')
              .fontSize(9)
              .fontColor('#666666')
              .margin({ left: 6 })
          }
        }
        .margin({ top: 4 })
        .alignItems(VerticalAlign.Center)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 8 })
    }
    .width('100%')
    .padding(8)
    .backgroundColor('rgba(22,22,22,0.6)')
    .borderRadius(10)
    .onClick(() => {
      this.play(item);
    })
  }

  private reload(): void {
    let context: common.UIAbilityContext | undefined =
      AppStorage.get<common.UIAbilityContext>('UiAbilityContext');
    if (!context) {
      return;
    }
    this.videos = loadCachedVideos(context);
  }

  private play(item: CachedVideo): void {
    this.pageStack.pushPath({
      name: 'VideoPlayer',
      param: createOfflinePlayParam(item)
    });
  }

  private confirmDelete(item: CachedVideo): void {
    this.getUIContext().getPromptAction().showDialog({
      message: '删除缓存「' + item.title + '」？',
      buttons: [
        { text: '取消', color: '#999999' },
        { text: '删除', color: '#FF0000' }
      ]
    }).then((result) => {
      if (result.index === 1) {
        this.doDelete(item);
      }
    }).catch(() => {
      // 用户取消
    });
  }

  private doDelete(item: CachedVideo): void {
    let context: common.UIAbilityContext | undefined =
      AppStorage.get<common.UIAbilityContext>('UiAbilityContext');
    if (!context) {
      return;
    }
    removeCachedVideo(context, item);
    this.videos = loadCachedVideos(context);
    this.getUIContext().getPromptAction().showToast({ message: '已删除缓存' });
  }
}
