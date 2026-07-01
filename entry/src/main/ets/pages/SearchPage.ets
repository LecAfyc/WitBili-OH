import { LengthMetrics } from "@kit.ArkUI";

@Component
export struct SearchPage {
  @Consume('pageStack') pageStack: NavPathStack;
  // ===== 搜索 =====
  @StorageLink('SearchHistory') searchHistoryJson: string = '[]';
  @State searchText: string = '';

  build() {
    NavDestination() {
      Stack() {
        Column() {
          this.HeaderBar()
          this.MainContent()
        }
        .width('100%').height('100%')
        .padding({
          left: 16,
          right: 16,
          top: 8,
          bottom: 16
        })
      }
      .width('100%').height('100%')
    }
    .height('100%')
    .width('100%')
    .hideBackButton(true)
    .hideTitleBar(true)
    .backgroundImage($r("app.media.oobe"))
  }

  // ==========================
  @Builder
  HeaderBar() {
    Row() {
      Row() {
        Circle().width(8).height(8).fill('#FB7299')
        Text('搜索').fontSize(16).fontColor('#EEEEEE')
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

  // ==========================
  @Builder
  MainContent() {
    Column() {
      // ── 搜索栏 ──
      Row() {
        TextInput({ placeholder: '点击搜索' })
          .height(42)
          .layoutWeight(1)
          .backgroundColor('#33FFFFFF')
          .placeholderColor('#888888')
          .fontColor('#EEEEEE')
          .borderRadius(8)
          .onChange((value: string) => {
            this.searchText = value;
          })
          .onSubmit(() => {
            this.doSearch();
          })

        Button() {
          SymbolGlyph($r("sys.symbol.magnifyingglass"))
        }
        .height(42)
        .width(42)
        .backgroundColor('#FB7299')
        .fontColor('#FFFFFF')
        .borderRadius(32)
        .margin({ left: 8 })
        .onClick(() => {
          this.doSearch();
        })
      }
      .width('100%')
      .padding({ top: 12, bottom: 8 })

      // ── 搜索历史 ──
      if (this.getHistoryList().length > 0) {
        Row() {
          Text('搜索历史')
            .fontSize(14)
            .fontColor('#AAAAAA')

          Blank()

          Text('清空')
            .fontSize(13)
            .fontColor('#FB7299')
            .onClick(() => {
              this.clearHistory();
            })
        }
        .width('100%')
        .padding({ top: 16, bottom: 8 })

        List({ space: 2 }) {
          ForEach(this.getHistoryList(), (item: string) => {
            ListItem() {
              Row() {
                SymbolGlyph($r("sys.symbol.list_bullet_circle"))
                  .fontSize(14)
                  .fontColor(['#777777'])

                Text(item)
                  .fontSize(15)
                  .fontColor('#DDDDDD')
                  .margin({ left: 10 })
                  .layoutWeight(1)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })

                SymbolGlyph($r("sys.symbol.xmark_circle"))
                  .fontSize(12)
                  .fontColor(['#777777'])
                  .padding({ left: 8, right: 4 })
                  .onClick(() => {
                    this.removeHistoryItem(item);
                  })
              }
              .width('100%')
              .padding({
                top: 10,
                bottom: 10,
                left: 4,
                right: 4
              })
              .borderRadius(6)
              .onClick(() => {
                this.searchText = item;
                this.doSearch();
              })
            }
          }, (item: string) => item)

          ListItem() {
            Column().height('40%')
          }

        }
        .width('100%')
        .layoutWeight(1)
        .edgeEffect(EdgeEffect.Spring)
        .fadingEdge(true, { fadingEdgeLength: LengthMetrics.vp(10) })
        .focusable(true)
        .focusOnTouch(true)
        .defaultFocus(true)
      } else {
        // ── 无历史 ──
        Column() {
          SymbolGlyph($r("sys.symbol.arrow_counterclockwise_clock"))
            .fontSize(35)
          Text('暂无历史')
            .fontSize(14)
            .fontColor('#666666')
            .margin({ top: 12 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      }
    }
    .width('100%').height('100%')
  }

  private getHistoryList(): string[] {
    const raw = this.searchHistoryJson;
    if (raw === undefined || raw === null || raw === '') {
      return [];
    }
    try {
      const parsed: string[] = JSON.parse(raw) as string[];
      if (!Array.isArray(parsed)) {
        return [];
      }
      return parsed;
    } catch {
      return [];
    }
  }

  private saveSearchHistory(keyword: string): void {
    let list = this.getHistoryList();
    list = list.filter(item => item !== keyword); // 去重
    list.unshift(keyword); // 最新放最前
    if (list.length > 10) {
      list = list.slice(0, 10);
    } // 最多10条
    this.searchHistoryJson = JSON.stringify(list);
  }

  private doSearch(): void {
    const keyword = this.searchText.trim();
    if (!keyword) {
      return;
    }
    this.saveSearchHistory(keyword);
    this.pageStack.pushPath({ name: 'SearchResultPage', param: keyword });
  }

  private clearHistory(): void {
    this.searchHistoryJson = '[]';
  }

  // ==========================
  //          顶栏

  private removeHistoryItem(keyword: string): void {
    let list = this.getHistoryList().filter(item => item !== keyword);
    this.searchHistoryJson = JSON.stringify(list);
  }

  // ==========================
  //        主内容区

  private showNavMenu(): void {
    this.pageStack.pushPath({ name: 'Menu' });
  }
}
