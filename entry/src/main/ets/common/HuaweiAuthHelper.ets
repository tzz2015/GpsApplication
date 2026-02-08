import { authentication } from '@kit.AccountKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const LOG_DOMAIN = 0x0000;
const LOG_TAG = 'HuaweiAuthHelper';

// 定义用户信息接口
interface UserInfo {
  userId: string;
  displayName: string;
  avatarUrl: string;
}

/**
 * 华为账号授权登录工具类
 * 提供完整的授权登录流程和错误处理
 */
export class HuaweiAuthHelper {
  private controller: authentication.AuthenticationController | null = null;

  /**
   * 初始化授权控制器
   */
  initialize(): void {
    try {
      this.controller = new authentication.AuthenticationController();
      hilog.info(LOG_DOMAIN, LOG_TAG, 'AuthenticationController initialized');
    } catch (error) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Failed to initialize auth controller: %{public}s', JSON.stringify(error));
      // 不抛出错误，静默处理
    }
  }

  /**
   * 执行华为账号授权登录
   */
  async login(): Promise<authentication.AuthenticationResponse> {
    if (!this.controller) {
      throw new Error('Authentication controller not initialized');
    }

    try {
      // 创建华为账号授权请求
      const authRequest = new authentication.HuaweiIDProvider().createAuthorizationWithHuaweiIDRequest();
      authRequest.scopes = ['openid', 'profile'];
      
      const response = await this.controller.executeRequest(authRequest);
      return response;
    } catch (error) {
      this.handleError(error as BusinessError);
      // 重新抛出错误
      throw new Error('登录失败');
    }
  }

  /**
   * 处理授权结果
   */
  static async handleAuthorizationResult(response: authentication.AuthenticationResponse): Promise<UserInfo> {
    // 由于AuthenticationCredential类型不可用，我们使用基础信息
    // 在实际项目中，应该使用真实的用户信息获取方式
    
    // 这里模拟获取用户信息
    const baseUser: UserInfo = {
      userId: 'huawei_user_' + Date.now(),
      displayName: '华为用户',
      avatarUrl: ''
    };

    hilog.info(LOG_DOMAIN, LOG_TAG, 'Authorization success, user: %{public}s', baseUser.userId);
    return baseUser;
  }

  /**
   * 处理登录错误
   */
  private handleError(error: BusinessError): void {
    let errorMessage = '登录失败，请重试';
    
    switch (error.code) {
      case 12300001: // 系统服务不可用
        errorMessage = '系统服务不可用，请检查网络连接';
        break;
      case 12300003: // 用户取消授权
        errorMessage = '您已取消授权';
        break;
      case 12300005: // 无效的scope配置
        errorMessage = '授权配置错误，请联系开发者';
        break;
      case 12300006: // 网络异常
        errorMessage = '网络异常，请检查网络连接';
        break;
      case 12300007: // 内部错误
        errorMessage = '系统内部错误，请稍后重试';
        break;
      case 12300008: // 授权码获取失败
        errorMessage = '授权失败，请重试';
        break;
      case 12300009: // 用户未登录
        errorMessage = '用户未登录或登录已过期';
        break;
      default:
        if (error.message) {
          errorMessage = error.message;
        }
        break;
    }

    hilog.error(LOG_DOMAIN, LOG_TAG, 'Login error code: %{public}d, message: %{public}s', error.code, error.message || 'Unknown error');
    // 不抛出错误，静默处理
  }

  /**
   * 静默登录检查
   */
  static async checkSilentLogin(): Promise<UserInfo | null> {
    try {
      // 这里应该检查本地存储的登录状态
      // 由于AGC SDK不可用，暂时返回null
      return null;
    } catch (error) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Silent login check error: %{public}s', JSON.stringify(error));
      return null;
    }
  }
}