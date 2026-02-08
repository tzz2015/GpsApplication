import { loginComponentManager } from '@kit.AccountKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const LOG_DOMAIN = 0x0000;
const LOG_TAG = 'HuaweiAuthHelper';

/** 登录返回的用户信息 */
export interface UserInfo {
  userId: string;
  displayName: string;
  avatarUrl: string;
}

/**
 * 华为账号登录工具类
 * 个人开发者使用 LoginWithHuaweiIDButton 组件登录
 */
export class HuaweiAuthHelper {

  /**
   * 从 LoginWithHuaweiIDButton 回调的凭证中提取用户信息
   * @param credential 登录按钮回调返回的 HuaweiIDCredential
   */
  static extractUserInfo(credential: loginComponentManager.HuaweiIDCredential): UserInfo {
    const fallbackId = 'hw_' + Date.now().toString();
    const user: UserInfo = {
      userId: fallbackId,
      displayName: '',
      avatarUrl: ''
    };

    // 提取 openID 或 unionID 作为用户唯一标识
    if (credential.openID && credential.openID.length > 0) {
      user.userId = credential.openID;
    } else if (credential.unionID && credential.unionID.length > 0) {
      user.userId = credential.unionID;
    }

    hilog.info(LOG_DOMAIN, LOG_TAG,
      'User extracted: id=%{public}s, unionID=%{public}s',
      user.userId,
      credential.unionID || 'none');

    return user;
  }

  /**
   * 获取用户友好的错误提示
   */
  static getErrorMessage(error: BusinessError): string {
    hilog.error(LOG_DOMAIN, LOG_TAG,
      'Login error: code=%{public}d, message=%{public}s',
      error.code, error.message);

    switch (error.code) {
      case 1001500001:
        return ''; // 用户取消登录，不提示
      case 1001500002:
        return '登录超时，请重试';
      case 1001500003:
        return '应用未授权，请联系开发者';
      case 1001502001:
        return '华为账号服务异常，请稍后重试';
      case 1001502002:
        return '应用授权未开通，请联系开发者';
      case 1001500005:
        return '网络异常，请检查网络连接';
      case 12300001:
        return '系统服务不可用，请检查网络';
      case 12300003:
        return ''; // 用户取消
      case 12300006:
        return '网络异常，请检查网络连接';
      default:
        return '登录失败（错误码: ' + error.code.toString() + '），请重试';
    }
  }
}
