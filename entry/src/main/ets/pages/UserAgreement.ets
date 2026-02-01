import { NavBar } from '../common/NavBar';

/**
 * 用户协议占位页：iOS 风格，上架前替换为正式内容。
 */
@Entry
@Component
struct UserAgreement {
  build() {
    Column() {
      NavBar({ title: $r('app.string.user_agreement_title'), showBack: true });

      Scroll() {
        Column({ space: 16 }) {
          Text(
            '本页面为用户协议占位页。正式上架前请在此处填写完整的用户协议内容，包括服务条款、使用规范等。'
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
