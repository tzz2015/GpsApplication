import { router } from '@kit.ArkUI';
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
    AuthStore.isLoggedIn(context).then((loggedIn: boolean) => {
      const target = loggedIn ? 'pages/Main' : 'pages/Login';
      router.replace({ url: target });
    }).catch(() => {
      router.replace({ url: 'pages/Login' });
    });
  }

  build() {
    Stack() {
      // 居中内容（固定在正中，不受底部提示影响）
      Column({ space: 0 }) {
        Column() {
          Text('🏔️')
            .fontSize(42);
        }
        .width(80)
        .height(80)
        .borderRadius(20)
        .backgroundColor('#22FFFFFF')
        .justifyContent(FlexAlign.Center)
        .backdropBlur(20);

        Text('遨游轨迹')
          .fontSize(28)
          .fontWeight(800)
          .fontColor(Color.White)
          .letterSpacing(2)
          .margin({ top: 20 });

        Text('记录每一段值得传承的路程')
          .fontSize(14)
          .fontColor('#CCFFFFFF')
          .margin({ top: 8 });
      }
      .alignItems(HorizontalAlign.Center);

      // 底部提示（绝对定位，不影响中间布局）
      if (this.showHint) {
        Text('点击进入 →')
          .fontSize(13)
          .fontColor('#66FFFFFF')
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
      colors: [['#2E5AE8', 0], ['#1A3DB8', 0.5], ['#0F2680', 1]]
    });
  }
}
