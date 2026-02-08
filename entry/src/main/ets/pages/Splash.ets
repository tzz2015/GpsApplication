import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { AuthStore } from '../common/AuthStore';

/**
 * P0-1 启动页 / 冷启动页
 * 展示 App Logo、名称和标语，2.5 秒后自动跳转：
 *   - 已登录 → 首页 Main
 *   - 未登录 → 登录页 Login
 */
@Entry
@Component
struct Splash {
  @State showHint: boolean = false;
  private timerId: number = -1;

  aboutToAppear(): void {
    // 延迟显示底部提示文字
    setTimeout(() => {
      this.showHint = true;
    }, 500);

    // 1 秒后自动跳转
    this.timerId = setTimeout(() => {
      this.navigateNext();
    }, 1000);
  }

  aboutToDisappear(): void {
    if (this.timerId !== -1) {
      clearTimeout(this.timerId);
    }
  }

  /** 检查登录状态并跳转 */
  private navigateNext(): void {
    const context = getContext(this) as common.UIAbilityContext;
    AuthStore.isLoggedIn(context).then((loggedIn: boolean) => {
      const target = loggedIn ? 'pages/Main' : 'pages/Login';
      router.replaceUrl({ url: target });
    }).catch(() => {
      router.replaceUrl({ url: 'pages/Login' });
    });
  }

  build() {
    Column() {
      Blank().layoutWeight(1);

      // Logo
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

      // App 名称
      Text('遨游轨迹')
        .fontSize(28)
        .fontWeight(800)
        .fontColor(Color.White)
        .letterSpacing(2)
        .margin({ top: 20 });

      // 标语
      Text('记录每一段值得传承的路程')
        .fontSize(14)
        .fontColor('#CCFFFFFF')
        .margin({ top: 8 });

      Blank().layoutWeight(1);

      // 底部提示
      if (this.showHint) {
        Text('点击进入 →')
          .fontSize(13)
          .fontColor('#66FFFFFF')
          .margin({ bottom: 60 })
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
    .linearGradient({
      angle: 160,
      colors: [['#2E5AE8', 0], ['#1A3DB8', 0.5], ['#0F2680', 1]]
    })
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center);
  }
}
