import { router } from '@kit.ArkUI';
import { LoginWithHuaweiIDButton, loginComponentManager } from '@kit.AccountKit';
import { abilityAccessCtrl, common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { AuthStore } from '../common/AuthStore';
import { HuaweiAuthHelper, UserInfo } from '../common/HuaweiAuthHelper';
import { Config } from '../common/Config';

const LOG_DOMAIN = 0x0000;
const LOG_TAG = 'Login';

/**
 * 登录页：使用官方 LoginWithHuaweiIDButton 组件（个人开发者可用）
 */
@Entry
@Component
struct Login {
  @State agreed: boolean = false;
  @State isLoggingIn: boolean = false;
  @State loginError: string = '';

  /** 华为账号登录按钮控制器 */
  controller: loginComponentManager.LoginWithHuaweiIDButtonController =
    new loginComponentManager.LoginWithHuaweiIDButtonController()
      /**
       * 当协议状态变化时，需通过 controller 通知登录按钮
       */
      .onClickLoginWithHuaweiIDButton(
        (error: BusinessError, credential: loginComponentManager.HuaweiIDCredential) => {
          if (error) {
            this.handleLoginError(error);
            return;
          }
          if (credential) {
            this.handleLoginCredential(credential);
          }
        });

  aboutToAppear(): void {
    this.requestPermissions();
    // 初始化协议状态：未同意
    this.controller.setAgreementStatus(loginComponentManager.AgreementStatus.NOT_ACCEPTED);
  }

  /** 申请定位等权限 */
  requestPermissions(): void {
    try {
      const atManager = abilityAccessCtrl.createAtManager();
      const context = getContext(this) as common.UIAbilityContext;
      atManager.requestPermissionsFromUser(context, [
        'ohos.permission.INTERNET',
        'ohos.permission.LOCATION',
        'ohos.permission.APPROXIMATELY_LOCATION'
      ]).then(() => {
        hilog.info(LOG_DOMAIN, LOG_TAG, 'Permissions granted');
      }).catch((err: BusinessError) => {
        hilog.error(LOG_DOMAIN, LOG_TAG, 'Request permissions fail: %{public}s', JSON.stringify(err));
      });
    } catch (e) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'requestPermissions error: %{public}s', JSON.stringify(e));
    }
  }

  /** 协议勾选状态变化 */
  onAgreementChange(value: boolean): void {
    this.agreed = value;
    this.loginError = '';
    // ★ 关键：通知华为登录按钮协议状态
    if (value) {
      this.controller.setAgreementStatus(loginComponentManager.AgreementStatus.ACCEPTED);
    } else {
      this.controller.setAgreementStatus(loginComponentManager.AgreementStatus.NOT_ACCEPTED);
    }
  }

  /** 处理登录凭证（按钮回调成功） */
  handleLoginCredential(credential: loginComponentManager.HuaweiIDCredential): void {
    this.isLoggingIn = true;
    this.loginError = '';

    hilog.info(LOG_DOMAIN, LOG_TAG,
      'Login credential received, openID=%{public}s',
      credential.openID || 'none');

    // 从凭证中提取用户信息
    const user: UserInfo = HuaweiAuthHelper.extractUserInfo(credential);

    // 设置默认昵称（LoginWithHuaweiIDButton 不返回昵称）
    if (user.displayName.length === 0) {
      user.displayName = '轨迹用户';
    }

    this.handleLoginSuccess(user);
  }

  /** 处理登录错误 */
  handleLoginError(error: BusinessError): void {
    const errMsg = HuaweiAuthHelper.getErrorMessage(error);
    if (errMsg.length > 0) {
      this.loginError = errMsg;
    }
    this.isLoggingIn = false;
    hilog.error(LOG_DOMAIN, LOG_TAG, 'Login failed: %{public}s', JSON.stringify(error));
  }

  /** 处理登录成功 */
  private handleLoginSuccess(user: UserInfo): void {
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const authUser = AuthStore.createNewUser(user.userId, user.displayName, user.avatarUrl);

      AuthStore.setUser(context, authUser)
        .then(() => {
          hilog.info(LOG_DOMAIN, LOG_TAG, 'User saved, navigating to Main');
          router.replaceUrl({ url: 'pages/Main' });
        })
        .catch((error: Error) => {
          hilog.error(LOG_DOMAIN, LOG_TAG, 'User save failed: %{public}s', JSON.stringify(error));
          this.loginError = '用户信息保存失败，请重试';
          this.isLoggingIn = false;
        });
    } catch (error) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Context error: %{public}s', JSON.stringify(error));
      this.loginError = '系统错误，请重试';
      this.isLoggingIn = false;
    }
  }

  /** 模拟登录（仅开发测试） */
  private onMockLogin(): void {
    if (!this.agreed || this.isLoggingIn) {
      return;
    }
    this.isLoggingIn = true;
    this.loginError = '';

    const context = getContext(this) as common.UIAbilityContext;
    const mockUser = AuthStore.createNewUser('mock_user_001', '轨迹用户', '');

    AuthStore.setUser(context, mockUser)
      .then(() => {
        router.replaceUrl({ url: 'pages/Main' });
      })
      .catch(() => {
        this.loginError = '登录失败，请重试';
        this.isLoggingIn = false;
      });
  }

  build() {
    Column() {
      Blank().layoutWeight(1);

      // ---- Logo 和标语 ----
      Column({ space: 16 }) {
        Column() {
          Text('🗺')
            .fontSize(48);
        }
        .width(80)
        .height(80)
        .borderRadius(20)
        .backgroundColor($r('app.color.primary_light'))
        .justifyContent(FlexAlign.Center)
        .shadow({ radius: 12, color: '#1A3478F6', offsetX: 0, offsetY: 4 });

        Text('遨游轨迹')
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.label_primary'));
        Text('记录扫墓轨迹，守护家族记忆')
          .fontSize(15)
          .fontColor($r('app.color.label_secondary'));
      }
      .alignItems(HorizontalAlign.Center);

      Blank().layoutWeight(1);

      // ---- 协议勾选 + 登录按钮 ----
      Column({ space: 20 }) {
        // 协议勾选
        Row({ space: 6 }) {
          Checkbox()
            .select(this.agreed)
            .onChange((value: boolean) => {
              this.onAgreementChange(value);
            });
          Text('已阅读并同意')
            .fontSize(13)
            .fontColor($r('app.color.label_secondary'));
          Text('《隐私政策》')
            .fontSize(13)
            .fontColor($r('app.color.link'))
            .onClick(() => {
              router.pushUrl({ url: 'pages/PrivacyPolicy' });
            });
          Text('与')
            .fontSize(13)
            .fontColor($r('app.color.label_secondary'));
          Text('《用户协议》')
            .fontSize(13)
            .fontColor($r('app.color.link'))
            .onClick(() => {
              router.pushUrl({ url: 'pages/UserAgreement' });
            });
        }
        .width('100%')
        .justifyContent(FlexAlign.Center);

        // 错误提示
        if (this.loginError.length > 0) {
          Text(this.loginError)
            .fontSize(13)
            .fontColor($r('app.color.destructive'))
            .width('100%')
            .textAlign(TextAlign.Center);
        }

        // ★ 官方华为账号登录按钮组件（个人开发者必须使用此组件）
        LoginWithHuaweiIDButton({
          params: {
            style: loginComponentManager.Style.BUTTON_RED,
            borderRadius: 24,
            loginType: loginComponentManager.LoginType.ID,
            supportDarkMode: true
          },
          controller: this.controller
        })
          .width('100%')
          .height(50);

        // 开发模式：模拟登录
        if (Config.IS_DEVELOPMENT_MODE) {
          Button('开发模式：模拟登录')
            .width('100%')
            .height(40)
            .fontSize(14)
            .fontColor($r('app.color.label_secondary'))
            .backgroundColor(Color.Transparent)
            .borderRadius(20)
            .enabled(this.agreed && !this.isLoggingIn)
            .onClick(() => {
              this.onMockLogin();
            });
        }
      }
      .width('85%')
      .margin({ bottom: 48 });
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.login_background'));
  }
}
