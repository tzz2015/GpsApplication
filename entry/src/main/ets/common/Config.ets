/**
 * 应用配置管理
 */

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

  /**
   * GPS 采集配置
   */
  static readonly GPS_INTERVAL: number = 1;
  static readonly GPS_MIN_DISTANCE: number = 2;
  static readonly GPS_ACCURACY_THRESHOLD: number = 30;
  static readonly GPS_ACCURACY_STRICT: number = 12;
  static readonly GPS_ACCURACY_MAX: number = 25;
  static readonly GPS_MIN_DISTANCE_STRICT: number = 4;
  static readonly GPS_MIN_DISTANCE_NORMAL: number = 3;
  static readonly GPS_MIN_DISTANCE_POOR: number = 6;
  static readonly GPS_MAX_SPEED_KMH: number = 30;
  static readonly GPS_IDLE_SPEED_KMH: number = 1.2;
  static readonly GPS_IDLE_MIN_DISTANCE: number = 6;
  static readonly GPS_HEADING_JUMP_DEG: number = 75;
}
