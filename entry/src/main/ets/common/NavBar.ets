import { router } from '@kit.ArkUI';

/**
 * iOS 风格导航栏：左侧返回、居中标题、可选右侧操作。
 */
@Component
export struct NavBar {
  @Prop title: string | Resource = '';
  @Prop showBack: boolean = true;

  build() {
    Row() {
      if (this.showBack) {
        Row() {
          Text('‹')
            .fontSize(28)
            .fontColor($r('app.color.primary'))
            .fontWeight(FontWeight.Normal);
          Text($r('app.string.nav_back'))
            .fontSize(17)
            .fontColor($r('app.color.primary'));
        }
        .padding({ left: 8, right: 12, top: 8, bottom: 8 })
        .onClick(() => {
          router.back();
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
    .backgroundColor($r('app.color.nav_bar_background'));
  }
}
