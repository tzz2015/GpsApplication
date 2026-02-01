import { NavBar } from '../common/NavBar';

/**
 * 关于轨迹：应用名称、版本、简介。
 */
@Entry
@Component
struct About {
  build() {
    Column() {
      NavBar({ title: $r('app.string.profile_about'), showBack: true });

      Scroll() {
        Column({ space: 16 }) {
          Image($r('app.media.startIcon'))
            .width(64)
            .height(64)
            .borderRadius(14)
            .objectFit(ImageFit.Cover)
            .margin({ top: 24 });
          Text($r('app.string.app_name'))
            .fontSize(22)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.label_primary'));
          Text($r('app.string.about_content'))
            .fontSize(15)
            .fontColor($r('app.color.label_secondary'))
            .textAlign(TextAlign.Center)
            .margin({ top: 8 });
        }
        .width('100%');
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off);
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.app_background'));
  }
}
