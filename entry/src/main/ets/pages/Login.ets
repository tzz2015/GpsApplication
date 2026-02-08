import { router } from '@kit.ArkUI';
import { abilityAccessCtrl } from '@kit.AbilityKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AuthStore, type AuthUser } from '../common/AuthStore';
import { HuaweiAuthHelper } from '../common/HuaweiAuthHelper';
import { Config } from '../common/Config';

const LOG_DOMAIN = 0x0000;
const LOG_TAG = 'Login';

// 定义用户信息接口
interface UserInfo {
  userId: string;
  displayName: string;
  avatarUrl: string;
}

/**
 * P0-2 登录页：iOS 风格，鸿蒙授权登录，协议勾选与隐私/用户协议链接。
 * 启动时申请定位等权限，便于后续轨迹记录页使用。
 */
@Entry
@Component
struct Login {
  @State agreed: boolean = false;
  @State isLoggingIn: boolean = false;
  @State loginError: string = '';
  private authHelper: HuaweiAuthHelper = new HuaweiAuthHelper();

  aboutToAppear(): void {
    this.requestPermissions();
    this.initializeAuthHelper();
    this.checkSilentLogin();
  }

  /** 申请定位、网络等权限（启动时弹窗，用户同意后后续轨迹记录可用） */
  requestPermissions(): void {
    const atManager = abilityAccessCtrl.createAtManager();
    const context: common.Context = this.getUIContext().getHostContext() as common.Context;
    atManager.requestPermissionsFromUser(context, [
      'ohos.permission.INTERNET',
      'ohos.permission.LOCATION',
      'ohos.permission.APPROXIMATELY_LOCATION'
    ]).then(() => {
      hilog.info(LOG_DOMAIN, LOG_TAG, 'Permissions requested');
    }).catch((err) => {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Request permissions fail: %{public}s', JSON.stringify(err));
    });
  }

  /** 初始化授权助手 */
  initializeAuthHelper(): void {
    try {
      this.authHelper.initialize();
      hilog.info(LOG_DOMAIN, LOG_TAG, 'HuaweiAuthHelper initialized');
    } catch (error) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Failed to initialize auth helper: %{public}s', JSON.stringify(error));
    }
  }

  /** 检查静默登录 */
  async checkSilentLogin(): Promise<void> {
    try {
      const user: UserInfo | null = await HuaweiAuthHelper.checkSilentLogin();
      if (user) {
        hilog.info(LOG_DOMAIN, LOG_TAG, 'Silent login success, user: %{public}s', user.userId);
        this.handleLoginSuccess(user);
      }
    } catch (error) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'Silent login check failed: %{public}s', JSON.stringify(error));
    }
  }

  /** 鸿蒙授权登录 */
  async onLoginClick(): Promise<void> {
    if (!this.agreed || this.isLoggingIn) {
      if (!this.agreed) {
        this.loginError = '请先阅读并同意用户协议和隐私政策';
      }
      return;
    }

    this.isLoggingIn = true;
    this.loginError = '';

    try {
      const response = await this.authHelper.login();
      const user: UserInfo = await HuaweiAuthHelper.handleAuthorizationResult(response);
      this.handleLoginSuccess(user);
    } catch (error) {
      this.handleLoginError(error as Error);
    }
  }

  /** 处理登录成功 */
  private handleLoginSuccess(user: UserInfo): void {
    const context: common.Context = this.getUIContext().getHostContext() as common.Context;
    
    const authUser: AuthUser = {
      userId: user.userId,
      displayName: user.displayName,
      avatarUrl: user.avatarUrl
    };
    
    AuthStore.setUser(context, authUser)
      .then(() => {
        hilog.info(LOG_DOMAIN, LOG_TAG, 'User info saved: %{public}s', user.userId);
        router.replaceUrl({ url: 'pages/Main' });
      })
      .catch((error) => {
        this.loginError = '用户信息保存失败，请重试';
        this.isLoggingIn = false;
        hilog.error(LOG_DOMAIN, LOG_TAG, 'User info save failed: %{public}s', JSON.stringify(error));
      });
  }

  /** 处理登录错误 */
  private handleLoginError(error: Error): void {
    this.loginError = error.message || '登录失败，请重试';
    this.isLoggingIn = false;
    hilog.error(LOG_DOMAIN, LOG_TAG, 'Login error: %{public}s', JSON.stringify(error));
  }

  /** 备用方案：模拟登录（仅用于开发测试） */
  private onMockLogin(): void {
    if (!this.agreed || this.isLoggingIn) {
      return;
    }
    
    this.isLoggingIn = true;
    this.loginError = '';
    
    const context: common.Context = this.getUIContext().getHostContext() as common.Context;
    const mockUser: AuthUser = {
      userId: 'mock_user_001',
      displayName: '轨迹用户',
      avatarUrl: ''
    };
    
    AuthStore.setUser(context, mockUser)
      .then(() => {
        router.replaceUrl({ url: 'pages/Main' });
      })
      .catch((error) => {
        this.loginError = '登录失败，请重试';
        this.isLoggingIn = false;
        hilog.error(LOG_DOMAIN, LOG_TAG, 'Mock login failed: %{public}s', JSON.stringify(error));
      });
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
              this.loginError = '';
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

        if (this.loginError.length > 0) {
          Text(this.loginError)
            .fontSize(13)
            .fontColor($r('app.color.destructive'))
            .width('100%')
            .textAlign(TextAlign.Center);
        }
        
        // 鸿蒙授权登录按钮
        Button(this.isLoggingIn ? $r('app.string.loading') : '华为账号登录')
          .width('100%')
          .height(50)
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.button_primary_text'))
          .backgroundColor($r('app.color.button_primary_bg'))
          .borderRadius(12)
          .enabled(this.agreed && !this.isLoggingIn)
          .opacity(this.agreed && !this.isLoggingIn ? 1 : 0.5)
          .onClick(() => {
            this.onLoginClick();
          });

        // 开发测试用的模拟登录按钮（正式发布时可移除）
        if (this.isDevelopmentMode()) {
          Button('开发模式：模拟登录')
            .width('100%')
            .height(40)
            .fontSize(14)
            .fontColor($r('app.color.label_secondary'))
            .backgroundColor(Color.Transparent)
            .borderRadius(8)
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

  /** 判断是否为开发模式 */
  private isDevelopmentMode(): boolean {
    return Config.IS_DEVELOPMENT_MODE;
  }
}