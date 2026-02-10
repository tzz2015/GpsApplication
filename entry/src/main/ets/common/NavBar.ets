/**
 * iOS 风格导航栏：左侧返回、居中标题、可选右侧操作。
 * 自动适配沉浸式状态栏（顶部安全区）。
 */
@Component
export struct NavBar {
  @Prop title: string | Resource = '';
  @Prop showBack: boolean = true;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;

  build() {
    Column() {
      // 状态栏占位
      Row()
        .width('100%')
        .height(this.statusBarHeight);

      // 导航栏主体
      Row() {
        if (this.showBack) {
          Row({ space: 6 }) {
            Text('<')
              .fontSize(18)
              .fontColor($r('app.color.primary'))
              .fontWeight(FontWeight.Bold);
            Text($r('app.string.nav_back'))
              .fontSize(16)
              .fontColor($r('app.color.primary'));
          }
          .alignItems(VerticalAlign.Center)
          .height(44)
          .padding({ left: 12, right: 12 })
          .onClick(() => {
            this.getUIContext().getRouter().back();
          });
        }

        Blank();
        Text(this.title)
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.label_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });

        Blank();

        if (this.showBack) {
          Row()
            .width(60)
            .height(44);
        }
      }
      .width('100%')
      .height(44)
      .alignItems(VerticalAlign.Center);
    }
    .width('100%')
    .backgroundColor($r('app.color.nav_bar_background'));
  }
}
