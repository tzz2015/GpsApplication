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

        // App 图标
        Column() {
          Text('🗺')
            .fontSize(48);
        }
        .width(80)
        .height(80)
        .borderRadius(20)
        .backgroundColor($r('app.color.primary_light'))
        .justifyContent(FlexAlign.Center);

        Text('遨游轨迹')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.label_primary'));

        Text('V' + Config.APP_VERSION)
          .fontSize(14)
          .fontColor($r('app.color.label_tertiary'));

        Text('记录扫墓轨迹，守护家族记忆')
          .fontSize(15)
          .fontColor($r('app.color.label_secondary'))
          .margin({ top: 8 });

        Column().layoutWeight(1);

        Column({ space: 4 }) {
          Text('记录祖先墓地位置，让祭祖文化更容易延续')
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
