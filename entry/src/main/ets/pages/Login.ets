import { LoginWithHuaweiIDButton, loginComponentManager } from '@kit.AccountKit';
import { window } from '@kit.ArkUI';
import { abilityAccessCtrl, common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { AuthStore } from '../common/AuthStore';
import { CloudDBService } from '../common/CloudDBService';
import { HuaweiAuthHelper, UserInfo } from '../common/HuaweiAuthHelper';
import { Config } from '../common/Config';
import { SyncService } from '../common/SyncService';

const LOG_DOMAIN = 0x0000;
const LOG_TAG = 'Login';

/**
 * 登录页：使用官方 LoginWithHuaweiIDButton 组件（个人开发者可用）
 */
@Entry
@Component
struct Login {
  @StorageProp('bottomSafeHeight') bottomSafeHeight: number = 0;
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

  onPageShow(): void {
    // 登录页为深色渐变背景，状态栏内容需要白色
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      window.getLastWindow(ctx).then((win: window.Window) => {
        win.setWindowSystemBarProperties({
          statusBarContentColor: '#FFFFFFFF'
        } as window.SystemBarProperties).catch((e: BusinessError) => {
          hilog.warn(LOG_DOMAIN, LOG_TAG, 'setStatusBar: %{public}s', JSON.stringify(e));
        });
      }).catch((e: BusinessError) => {
        hilog.warn(LOG_DOMAIN, LOG_TAG, 'getLastWindow: %{public}s', JSON.stringify(e));
      });
    } catch (e) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'onPageShow statusBar: %{public}s', JSON.stringify(e));
    }
  }

  /** 申请定位等权限 */
  requestPermissions(): void {
    try {
      const atManager = abilityAccessCtrl.createAtManager();
      const context = this.getUIContext().getHostContext() as common.Context;
      atManager.requestPermissionsFromUser(context, [
        'ohos.permission.INTERNET',
        'ohos.permission.LOCATION',
        'ohos.permission.APPROXIMATELY_LOCATION',
        'ohos.permission.LOCATION_IN_BACKGROUND',
        'ohos.permission.KEEP_BACKGROUND_RUNNING'
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
      const context = this.getUIContext().getHostContext() as common.Context;
      const authUser = AuthStore.createNewUser(user.userId, user.displayName, user.avatarUrl);

      AuthStore.setUser(context, authUser)
        .then(async () => {
          hilog.info(LOG_DOMAIN, LOG_TAG, 'User saved');
          // 建立 AGC Auth 会话（Cloud DB 写入需 Authenticated；刚用华为账号登录，静默可能成功）
          await CloudDBService.ensureAuth();
          // 重装后：先从云端恢复用户信息（昵称等），再同步本地到云端，再进首页
          await SyncService.restoreUserFromCloud(context);
          await SyncService.syncUser(context).catch((e: Error) => {
            hilog.warn(LOG_DOMAIN, LOG_TAG, 'Sync user after login: %{public}s', JSON.stringify(e));
          });
          this.getUIContext().getRouter().replaceUrl({ url: 'pages/Main' });
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

    const context = this.getUIContext().getHostContext() as common.Context;
    const mockUser = AuthStore.createNewUser('mock_user_001', '轨迹用户', '');

    AuthStore.setUser(context, mockUser)
      .then(() => {
        this.getUIContext().getRouter().replaceUrl({ url: 'pages/Main' });
      })
      .catch(() => {
        this.loginError = '登录失败，请重试';
        this.isLoggingIn = false;
      });
  }

  build() {
    Stack() {
      // 主内容区域
      Column() {
        Blank().layoutWeight(1);

        // ---- Logo 和标语 ----
        Column({ space: 16 }) {
          Image($r('app.media.startIcon'))
            .width(88)
            .height(88)
            .borderRadius(22)
            .objectFit(ImageFit.Cover)
            .shadow({ radius: 16, color: $r('app.color.login_icon_shadow'), offsetX: 0, offsetY: 6 });

          Text($r('app.string.app_name'))
            .fontSize(28)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White);
          Text($r('app.string.app_tagline'))
            .fontSize(15)
            .fontColor($r('app.color.login_title_secondary'));
        }
        .alignItems(HorizontalAlign.Center);

        Blank().layoutWeight(1);

        // ---- 登录按钮区域 ----
        Column({ space: 16 }) {
          // 错误提示
          if (this.loginError.length > 0) {
            Text(this.loginError)
              .fontSize(13)
              .fontColor($r('app.color.login_error'))
              .width('100%')
              .textAlign(TextAlign.Center);
          }

          // ★ 官方华为账号登录按钮组件
          LoginWithHuaweiIDButton({
            params: {
              style: loginComponentManager.Style.BUTTON_RED,
              extraStyle: {
                buttonStyle: new loginComponentManager.ButtonStyle()
                  .loadingStyle({ show: this.isLoggingIn })
              },
              borderRadius: 24,
              loginType: loginComponentManager.LoginType.ID,
              supportDarkMode: true
            },
            controller: this.controller
          })
            .width('100%')
            .height(50);

          // 首次登录提示
          Text($r('app.string.login_first_time'))
            .fontSize(12)
            .fontColor($r('app.color.login_subtitle'))
            .textAlign(TextAlign.Center)
            .width('100%');

          // 开发模式：模拟登录
          if (Config.IS_DEVELOPMENT_MODE) {
            Button('开发模式：模拟登录')
              .width('100%')
              .height(40)
              .fontSize(14)
              .fontColor($r('app.color.login_button_secondary'))
              .backgroundColor(Color.Transparent)
              .borderRadius(20)
              .enabled(this.agreed && !this.isLoggingIn)
              .onClick(() => {
                this.onMockLogin();
              });
          }
        }
        .width('85%')
        .margin({ bottom: 100 });
      }
      .width('100%')
      .height('100%');

      // ---- 底部协议勾选（绝对定位在底部） ----
      Row({ space: 6 }) {
        Checkbox()
          .select(this.agreed)
          .onChange((value: boolean) => {
            this.onAgreementChange(value);
          });
        Text($r('app.string.login_agree_prefix'))
          .fontSize(12)
          .fontColor($r('app.color.login_hint'));
        Text($r('app.string.login_agree_privacy'))
          .fontSize(12)
          .fontColor($r('app.color.login_link'))
          .decoration({ type: TextDecorationType.Underline })
          .onClick(() => {
            this.getUIContext().getRouter().pushUrl({ url: 'pages/PrivacyPolicy' });
          });
        Text($r('app.string.login_agree_and'))
          .fontSize(12)
          .fontColor($r('app.color.login_hint'));
        Text($r('app.string.login_agree_user_agreement'))
          .fontSize(12)
          .fontColor($r('app.color.login_link'))
          .decoration({ type: TextDecorationType.Underline })
          .onClick(() => {
            this.getUIContext().getRouter().pushUrl({ url: 'pages/UserAgreement' });
          });
      }
      .justifyContent(FlexAlign.Center)
      .width('100%')
      .position({ bottom: 20 + this.bottomSafeHeight });
    }
    .width('100%')
    .height('100%')
    .linearGradient({
      angle: 170,
      colors: [[$r('app.color.gradient_end'), 0], [$r('app.color.primary_deeper'), 0.4], [$r('app.color.primary'), 1]]
    });
  }
}
