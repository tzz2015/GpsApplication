/**
 * 应用配置管理
 * 用于管理开发环境和生产环境的配置切换
 */

// 定义配置接口
interface AGCConfig {
  clientId: string;
  appId: string;
  packageName: string;
}

interface LogConfig {
  domain: number;
  tag: string;
  level: string;
}

interface RoutesConfig {
  LOGIN: string;
  MAIN: string;
  PROFILE_EDIT: string;
  PRIVACY_POLICY: string;
  USER_AGREEMENT: string;
}

interface StorageConfig {
  AUTH_PREFS: string;
  TRACK_PREFS: string;
}

export class Config {
  /**
   * 是否为开发模式
   * 开发模式会启用模拟登录等调试功能
   * 正式发布时应设置为false
   */
  static readonly IS_DEVELOPMENT_MODE: boolean = true;

  /**
   * 应用版本信息
   */
  static readonly APP_VERSION: string = '1.0.0';
  static readonly BUILD_NUMBER: string = '20241201';

  /**
   * AGC配置信息
   */
  static readonly AGC_CONFIG: AGCConfig = {
    clientId: '6917590279469130152',
    appId: '6917590279469130152',
    packageName: 'com.lyf.aoyou'
  };

  /**
   * 华为账号授权范围配置
   */
  static readonly HUAWEI_AUTH_SCOPES: string[] = ['openid', 'profile'];

  /**
   * 日志配置
   */
  static readonly LOG_CONFIG: LogConfig = {
    domain: 0x0000,
    tag: 'TrailApp',
    level: Config.IS_DEVELOPMENT_MODE ? 'DEBUG' : 'INFO'
  };

  /**
   * 权限配置
   */
  static readonly PERMISSIONS: string[] = [
    'ohos.permission.INTERNET',
    'ohos.permission.GET_NETWORK_INFO',
    'ohos.permission.LOCATION',
    'ohos.permission.APPROXIMATELY_LOCATION'
  ];

  /**
   * 页面路由配置
   */
  static readonly ROUTES: RoutesConfig = {
    LOGIN: 'pages/Login',
    MAIN: 'pages/Main',
    PROFILE_EDIT: 'pages/ProfileEdit',
    PRIVACY_POLICY: 'pages/PrivacyPolicy',
    USER_AGREEMENT: 'pages/UserAgreement'
  };

  /**
   * 存储配置
   */
  static readonly STORAGE_CONFIG: StorageConfig = {
    AUTH_PREFS: 'auth_prefs',
    TRACK_PREFS: 'track_prefs'
  };
}