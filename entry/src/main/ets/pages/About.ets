import { NavBar } from '../common/NavBar';
import { Config } from '../common/Config';

/**
 * 关于页面
 */
@Entry
@Component
struct About {
  build() {
    Column() {
      NavBar({ title: '关于遨游轨迹', showBack: true });

      Column({ space: 16 }) {
        Blank().height(32);

        // App 图标（与桌面/启动页一致）
        Image($r('app.media.startIcon'))
          .width(80)
          .height(80)
          .borderRadius(20)
          .objectFit(ImageFit.Contain);

        Text($r('app.string.app_name'))
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.label_primary'));

        Text('V' + Config.APP_VERSION)
          .fontSize(14)
          .fontColor($r('app.color.label_tertiary'));

        Text($r('app.string.about_tagline'))
          .fontSize(15)
          .fontColor($r('app.color.label_secondary'))
          .margin({ top: 8 });

        Column().layoutWeight(1);

        Column({ space: 4 }) {
          Text($r('app.string.about_desc'))
            .fontSize(12)
            .fontColor($r('app.color.label_tertiary'))
            .textAlign(TextAlign.Center);
          Text('Build ' + Config.BUILD_NUMBER)
            .fontSize(11)
            .fontColor($r('app.color.label_tertiary'));
        }
        .margin({ bottom: 32 });
      }
      .layoutWeight(1)
      .width('100%')
      .alignItems(HorizontalAlign.Center)
      .backgroundColor($r('app.color.app_background'));
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.app_background'));
  }
}
