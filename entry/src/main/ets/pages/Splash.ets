import { common } from '@kit.AbilityKit';
import { AuthStore } from '../common/AuthStore';

/**
 * P0-1 启动页 / 冷启动页
 * 展示 App Logo、名称和标语，1 秒后自动跳转
 */
@Entry
@Component
struct Splash {
  @State showHint: boolean = false;
  private timerId: number = -1;

  aboutToAppear(): void {
    setTimeout(() => {
      this.showHint = true;
    }, 500);

    this.timerId = setTimeout(() => {
      this.navigateNext();
    }, 1000);
  }

  aboutToDisappear(): void {
    if (this.timerId !== -1) {
      clearTimeout(this.timerId);
    }
  }

  private navigateNext(): void {
    const context = this.getUIContext().getHostContext() as common.Context;
    const uiContext = this.getUIContext();
    AuthStore.isLoggedIn(context).then((loggedIn: boolean) => {
      const target = loggedIn ? 'pages/Main' : 'pages/Login';
      uiContext.getRouter().replaceUrl({ url: target });
    }).catch(() => {
      uiContext.getRouter().replaceUrl({ url: 'pages/Login' });
    });
  }

  build() {
    Stack() {
      // 居中内容（固定在正中，不受底部提示影响）
      Column({ space: 0 }) {
        Image($r('app.media.startIcon'))
          .width(80)
          .height(80)
          .borderRadius(20)
          .objectFit(ImageFit.Contain)
          .backgroundColor($r('app.color.icon_overlay_light'))
          .backdropBlur(20);

        Text($r('app.string.app_name'))
          .fontSize(28)
          .fontWeight(800)
          .fontColor(Color.White)
          .letterSpacing(2)
          .margin({ top: 20 });

        Text($r('app.string.splash_tagline'))
          .fontSize(14)
          .fontColor($r('app.color.splash_title_secondary'))
          .margin({ top: 8 });
      }
      .alignItems(HorizontalAlign.Center);

      // 底部提示（绝对定位，不影响中间布局）
      if (this.showHint) {
        Text($r('app.string.splash_enter'))
          .fontSize(13)
          .fontColor($r('app.color.splash_enter_text'))
          .position({ bottom: 60 })
          .width('100%')
          .textAlign(TextAlign.Center)
          .onClick(() => {
            if (this.timerId !== -1) {
              clearTimeout(this.timerId);
              this.timerId = -1;
            }
            this.navigateNext();
          });
      }
    }
    .width('100%')
    .height('100%')
    .alignContent(Alignment.Center)
    .linearGradient({
      angle: 160,
      colors: [
        [$r('app.color.splash_gradient_end'), 0],
        [$r('app.color.splash_gradient_mid'), 0.3],
        [$r('app.color.primary'), 0.65],
        [$r('app.color.splash_gradient_start'), 1]
      ]
    });
  }
}
