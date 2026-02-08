/**
 * 应用配置管理
 */

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
  CREATE_TRACK: string;
  TRACK_RECORD: string;
  TRACK_DETAIL: string;
  TOMB_SPOT_DETAIL: string;
  PROFILE_EDIT: string;
  PRIVACY_POLICY: string;
  USER_AGREEMENT: string;
  ABOUT: string;
}

interface StorageConfig {
  AUTH_PREFS: string;
  TRACK_PREFS: string;
}

export class Config {
  /**
   * 是否为开发模式
   * 正式发布时设置为 false
   */
  static readonly IS_DEVELOPMENT_MODE: boolean = true;

  static readonly APP_VERSION: string = '1.0.0';
  static readonly BUILD_NUMBER: string = '20260208';

  static readonly AGC_CONFIG: AGCConfig = {
    clientId: '6917590279469130152',
    appId: '6917590279469130152',
    packageName: 'com.lyf.aoyou'
  };

  static readonly LOG_CONFIG: LogConfig = {
    domain: 0x0000,
    tag: 'AoYouTrail',
    level: Config.IS_DEVELOPMENT_MODE ? 'DEBUG' : 'INFO'
  };

  static readonly PERMISSIONS: string[] = [
    'ohos.permission.INTERNET',
    'ohos.permission.GET_NETWORK_INFO',
    'ohos.permission.LOCATION',
    'ohos.permission.APPROXIMATELY_LOCATION'
  ];

  static readonly ROUTES: RoutesConfig = {
    LOGIN: 'pages/Login',
    MAIN: 'pages/Main',
    CREATE_TRACK: 'pages/CreateOrEditTrack',
    TRACK_RECORD: 'pages/TrackRecord',
    TRACK_DETAIL: 'pages/TrackDetail',
    TOMB_SPOT_DETAIL: 'pages/TombSpotDetail',
    PROFILE_EDIT: 'pages/ProfileEdit',
    PRIVACY_POLICY: 'pages/PrivacyPolicy',
    USER_AGREEMENT: 'pages/UserAgreement',
    ABOUT: 'pages/About'
  };

  static readonly STORAGE_CONFIG: StorageConfig = {
    AUTH_PREFS: 'auth_prefs',
    TRACK_PREFS: 'track_prefs'
  };

  /**
   * GPS 采集配置
   */
  static readonly GPS_INTERVAL: number = 3;              // 定位间隔（秒）
  static readonly GPS_MIN_DISTANCE: number = 3;          // 最小移动距离（米）
  static readonly GPS_ACCURACY_THRESHOLD: number = 50;   // 精度阈值（米）
}
