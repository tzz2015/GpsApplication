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
  TEST_LAB: string;
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

  static readonly APP_VERSION: string = '1.0.2';
  static readonly BUILD_NUMBER: string = '20260208';
  static readonly CLOUD_DB_ZONE_PROD: string = 'aoyou';
  static readonly CLOUD_DB_ZONE_TEST: string = 'aoyouTest';
  static readonly CLOUD_STORAGE_TEST_PREFIX: string = 'test/';

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
    ABOUT: 'pages/About',
    TEST_LAB: 'pages/TestLab'
  };

  static readonly STORAGE_CONFIG: StorageConfig = {
    AUTH_PREFS: 'auth_prefs',
    TRACK_PREFS: 'track_prefs'
  };

  /**
   * GPS 采集配置
   */
  static readonly GPS_INTERVAL: number = 1;              // 定位间隔（秒）
  static readonly GPS_MIN_DISTANCE: number = 2;          // 最小移动距离（米）
  static readonly GPS_ACCURACY_THRESHOLD: number = 30;   // 精度阈值（米）
  static readonly GPS_ACCURACY_STRICT: number = 12;      // 高置信精度阈值（米）
  static readonly GPS_ACCURACY_MAX: number = 25;         // 可接受最大精度（米）
  static readonly GPS_MIN_DISTANCE_STRICT: number = 4;   // 高精度最小记录距离（米）
  static readonly GPS_MIN_DISTANCE_NORMAL: number = 3;   // 常规最小记录距离（米）
  static readonly GPS_MIN_DISTANCE_POOR: number = 6;     // 低质量定位最小记录距离（米）
  static readonly GPS_MAX_SPEED_KMH: number = 30;        // 步行高精度速度上限（km/h）
  static readonly GPS_IDLE_SPEED_KMH: number = 1.2;      // 近静止速度阈值（km/h）
  static readonly GPS_IDLE_MIN_DISTANCE: number = 6;     // 近静止最小记录距离（米）
  static readonly GPS_HEADING_JUMP_DEG: number = 75;     // 航向突变阈值（度）
}
