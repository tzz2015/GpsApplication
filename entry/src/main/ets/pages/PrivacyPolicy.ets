import { router } from '@kit.ArkUI';
import { NavBar } from '../common/NavBar';

/**
 * 隐私政策占位页：iOS 风格，上架前替换为正式内容。
 */
@Entry
@Component
struct PrivacyPolicy {
  build() {
    Column() {
      NavBar({ title: $r('app.string.privacy_title'), showBack: true });

      Scroll() {
        Column({ space: 16 }) {
          Text(
            '本页面为隐私政策占位页。正式上架前请在此处填写完整的隐私政策内容，包括但不限于：\n\n' +
            '· 我们收集哪些信息（如轨迹与位置数据的用途）；\n' +
            '· 信息的可见范围、存储与删除方式；\n' +
            '· 符合隐私合规要求的其他说明。'
          )
            .fontSize(15)
            .fontColor($r('app.color.label_primary'))
            .width('100%')
            .padding(16);
        }
        .width('100%')
        .backgroundColor($r('app.color.card_background'))
        .borderRadius(12)
        .margin(16);
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)
      .backgroundColor($r('app.color.app_background'));
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.app_background'));
  }
}
