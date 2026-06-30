@Component
export struct ImageViewPage{
  @Consume('pageStack') pageStack: NavPathStack;
  pathStack: NavPathStack | undefined = undefined;
  pageParam: string = '';   // 传入的图片URL

  // 图片缩放与拖拽状态
  @State curScale: number = 1.0;
  @State curOffsetX: number = 0;
  @State curOffsetY: number = 0;
  @State componentWidth: number = 0;
  @State componentHeight: number = 0;
  // 缩放范围（只保留最大/最小限制，无自动贴合）
  private readonly MIN_SCALE: number = 0.5;
  private readonly MAX_SCALE: number = 5.0;

  // 边界限制参数
  private maxOffsetX: number = 0;
  private minOffsetX: number = 0;
  private maxOffsetY: number = 0;
  private minOffsetY: number = 0;

  // 手势保存状态
  private saveScale: number = 1.0;
  private saveOffsetX: number = 0;
  private saveOffsetY: number = 0;

  // 计算边界限制
  calcBoundary(): void {
    let scaledWidth = this.componentWidth * this.curScale;
    let scaledHeight = this.componentHeight * this.curScale;

    if (scaledWidth > this.componentWidth) {
      let maxX = (scaledWidth - this.componentWidth) / 2;
      this.maxOffsetX = maxX;
      this.minOffsetX = -maxX;
    } else {
      this.maxOffsetX = 0;
      this.minOffsetX = 0;
    }

    if (scaledHeight > this.componentHeight) {
      let maxY = (scaledHeight - this.componentHeight) / 2;
      this.maxOffsetY = maxY;
      this.minOffsetY = -maxY;
    } else {
      this.maxOffsetY = 0;
      this.minOffsetY = 0;
    }
  }

  // 边界限制
  restrictBoundary(): void {
    this.calcBoundary();

    if (this.curOffsetX > this.maxOffsetX) {
      this.curOffsetX = this.maxOffsetX;
    } else if (this.curOffsetX < this.minOffsetX) {
      this.curOffsetX = this.minOffsetX;
    }

    if (this.curOffsetY > this.maxOffsetY) {
      this.curOffsetY = this.maxOffsetY;
    } else if (this.curOffsetY < this.minOffsetY) {
      this.curOffsetY = this.minOffsetY;
    }
  }

  // ====== 双指缩放 ======
  onPinchStart(): void {
    console.log("[ImageViewer] PinchStart!");
    this.saveScale = this.curScale;
  }

  onPinchUpdate(event: GestureEvent): void {
    let newScale = this.saveScale * event.scale;
    newScale = Math.max(this.MIN_SCALE, Math.min(this.MAX_SCALE, newScale));
    this.curScale = newScale;
    console.log(`[ImageViewer] Pinch scale: ${this.curScale.toFixed(2)}`);
  }

  onPinchEnd(): void {
    console.log(`[ImageViewer] PinchEnd! scale=${this.curScale.toFixed(2)}`);
    // 不再自动贴合，完全自由缩放
  }

  // ====== 单指拖拽 ======
  onPanStart(): void {
    console.log("[ImageViewer] PanStart!");
    this.saveOffsetX = this.curOffsetX;
    this.saveOffsetY = this.curOffsetY;
  }

  onPanUpdate(event: GestureEvent): void {
    this.curOffsetX = this.saveOffsetX + event.offsetX;
    this.curOffsetY = this.saveOffsetY + event.offsetY;
    console.log(`[ImageViewer] Pan: (${this.curOffsetX.toFixed(0)}, ${this.curOffsetY.toFixed(0)})`);
  }

  onPanEnd(): void {
    console.log("[ImageViewer] PanEnd!");
    this.restrictBoundary();
  }

  // ====== 双击 ======
  onDoubleTap(): void {
    console.log("[ImageViewer] doubleTapped!");
    if (this.curScale > 1.1) {
      this.curScale = 1.0;
      this.curOffsetX = 0;
      this.curOffsetY = 0;
    } else {
      this.curScale = 2.0;
      this.curOffsetX = 0;
      this.curOffsetY = 0;
    }
  }

  // ====== 返回 ======
  onBack(): void {
    if (this.pathStack) {
      this.pathStack.pop();
    } else {
      this.pageStack.pop();
    }
  }

  build() {
    NavDestination(){
      Stack() {
        // 黑底背景
        Rect()
          .width("100%")
          .height("100%")
          .fill(Color.Black)

        // === 图片容器：缩放 & 位移作用在此 ===
        Stack() {
          Image(this.pageParam)
            .width("100%")
            .height("100%")
            .objectFit(ImageFit.Contain)
        }
        .width("100%")
        .height("100%")
        .scale({ x: this.curScale, y: this.curScale })
        .animation({
          duration: 500,
          curve: Curve.Rhythm
        })
        .translate({ x: this.curOffsetX, y: this.curOffsetY })
        .onAreaChange((oldValue: Area, newValue: Area) => {
          this.componentWidth = newValue.width as number;
          this.componentHeight = newValue.height as number;
          this.calcBoundary();
        })

        // 顶部返回按钮
        Circle()
          .width(36)
          .height(36)
          .fill(Color.White)
          .opacity(0.75)
          .position({ x: 100, y: 8 })
        Text("<")
          .fontSize(20)
          .fontColor(Color.Black)
          .fontWeight(FontWeight.Bold)
          .textAlign(TextAlign.Center)
          .position({ x: 100, y: 8 })
          .width(36)
          .height(36)
          .onClick(() => {
            this.onBack();
          })
      }
      .width('100%')
      .height('100%')
      .alignContent(Alignment.Center)
      .gesture(
        GestureGroup(GestureMode.Exclusive,
          // 1. 双击（优先匹配）
          TapGesture({ count: 2 })
            .onAction(() => {
              this.onDoubleTap();
            }),
          // 2. 双指缩放
          PinchGesture()
            .onActionStart((event: GestureEvent) => {
              this.onPinchStart();
            })
            .onActionUpdate((event: GestureEvent) => {
              this.onPinchUpdate(event);
            })
            .onActionEnd(() => {
              this.onPinchEnd();
            }),
          // 3. 单指拖拽
          PanGesture({ fingers: 1, distance: 3 })
            .onActionStart(() => {
              this.onPanStart();
            })
            .onActionUpdate((event: GestureEvent) => {
              this.onPanUpdate(event);
            })
            .onActionEnd(() => {
              this.onPanEnd();
            })
        )
      )
    }
    .height('100%')
    .width('100%')
    .title("ImageViewPage")
    .hideBackButton(true)
    .hideTitleBar(true)
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      this.pageParam = context.pathInfo.param as string;
    })
  }
}
