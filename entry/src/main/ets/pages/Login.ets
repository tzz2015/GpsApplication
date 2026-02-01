import { router } from '@kit.ArkUI';
import { abilityAccessCtrl } from '@kit.AbilityKit';

/**
 * P0-2 登录页：iOS 风格，鸿蒙授权登录，协议勾选与隐私/用户协议链接。
 * 启动时申请定位等权限，便于后续轨迹记录页使用。
 */
@Entry
@Component
struct Login {
  @State agreed: boolean = false;

  aboutToAppear(): void {
    this.requestPermissions();
  }

  /** 申请定位、网络等权限（启动时弹窗，用户同意后后续轨迹记录可用） */
  requestPermissions(): void {
    const atManager = abilityAccessCtrl.createAtManager();
    const context = this.getUIContext().getHostContext();
    atManager.requestPermissionsFromUser(context, [
      'ohos.permission.INTERNET',
      'ohos.permission.LOCATION',
      'ohos.permission.APPROXIMATELY_LOCATION'
    ]).then(() => {
      console.info('Permissions requested');
    }).catch((err: Error) => {
      console.error('Request permissions fail: ' + JSON.stringify(err));
    });
  }

  onLoginClick(): void {
    if (!this.agreed) {
      return;
    }
    // TODO: 接入 AGC Auth 华为账号登录，成功后写登录态并跳转
    router.replaceUrl({ url: 'pages/Main' });
  }

  build() {
    Column() {
      Blank().layoutWeight(1);

      Column({ space: 16 }) {
        Image($r('app.media.startIcon'))
          .width(72)
          .height(72)
          .objectFit(ImageFit.Contain)
          .borderRadius(16);
        Text($r('app.string.app_name'))
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.label_primary'));
        Text($r('app.string.app_tagline'))
          .fontSize(15)
          .fontColor($r('app.color.label_secondary'));
      }

      Blank().layoutWeight(1);

      Column({ space: 20 }) {
        Row({ space: 6 }) {
          Checkbox()
            .select(this.agreed)
            .onChange((value: boolean) => {
              this.agreed = value;
            });
          Text($r('app.string.login_agree_prefix'))
            .fontSize(13)
            .fontColor($r('app.color.label_secondary'));
          Text($r('app.string.login_agree_privacy'))
            .fontSize(13)
            .fontColor($r('app.color.link'))
            .onClick(() => {
              router.pushUrl({ url: 'pages/PrivacyPolicy' });
            });
          Text($r('app.string.login_agree_and'))
            .fontSize(13)
            .fontColor($r('app.color.label_secondary'));
          Text($r('app.string.login_agree_user_agreement'))
            .fontSize(13)
            .fontColor($r('app.color.link'))
            .onClick(() => {
              router.pushUrl({ url: 'pages/UserAgreement' });
            });
        }
        .width('100%')
        .justifyContent(FlexAlign.Center);

        Button($r('app.string.login_button'))
          .width('100%')
          .height(50)
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.button_primary_text'))
          .backgroundColor($r('app.color.button_primary_bg'))
          .borderRadius(12)
          .enabled(this.agreed)
          .opacity(this.agreed ? 1 : 0.5)
          .onClick(() => {
            this.onLoginClick();
          });
      }
      .width('85%')
      .margin({ bottom: 48 });
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.login_background'));
  }
}
