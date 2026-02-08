import { relationalStore } from '@kit.RelationalStoreKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { common } from '@kit.AbilityKit';

const LOG_DOMAIN = 0x0000;
const LOG_TAG = 'DataStore';

/**
 * 数据库管理类 - 解决 RDBStoreManager 错误
 */
export class DataStore {
  private static rdbStore: relationalStore.RdbStore | null = null;
  private static isInitialized: boolean = false;

  /**
   * 初始化数据库
   */
  static async initialize(context: common.Context): Promise<void> {
    if (this.isInitialized && this.rdbStore) {
      return;
    }

    try {
      const STORE_CONFIG: relationalStore.StoreConfig = {
        name: 'aoyou.db',
        securityLevel: relationalStore.SecurityLevel.S1
      };

      this.rdbStore = await relationalStore.getRdbStore(context, STORE_CONFIG);
      this.isInitialized = true;
      
      hilog.info(LOG_DOMAIN, LOG_TAG, 'RDB Store initialized successfully');
      
      // 创建必要的表
      await this.createTables();
    } catch (error) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Failed to initialize RDB Store: %{public}s', JSON.stringify(error));
      throw error;
    }
  }

  /**
   * 创建数据库表
   */
  private static async createTables(): Promise<void> {
    if (!this.rdbStore) {
      throw new Error('RDB Store not initialized');
    }

    try {
      // 用户表
      const userTableSql = `CREATE TABLE IF NOT EXISTS users (
        user_id TEXT PRIMARY KEY,
        display_name TEXT,
        avatar_url TEXT,
        family_name TEXT,
        signature TEXT,
        created_at INTEGER,
        updated_at INTEGER,
        sync_status TEXT DEFAULT 'synced'
      )`;

      // 轨迹表
      const trackTableSql = `CREATE TABLE IF NOT EXISTS tracks (
        track_id TEXT PRIMARY KEY,
        owner_user_id TEXT,
        title TEXT,
        description TEXT,
        start_name TEXT,
        end_name TEXT,
        visibility TEXT DEFAULT 'PRIVATE',
        status TEXT DEFAULT 'editing',
        cover_image_url TEXT,
        created_at INTEGER,
        updated_at INTEGER,
        sync_status TEXT DEFAULT 'pending'
      )`;

      // 轨迹点表
      const trackPointTableSql = `CREATE TABLE IF NOT EXISTS track_points (
        point_id TEXT PRIMARY KEY,
        track_id TEXT,
        order_index INTEGER,
        lat REAL,
        lng REAL,
        altitude REAL,
        accuracy REAL,
        timestamp INTEGER,
        created_at INTEGER,
        sync_status TEXT DEFAULT 'pending'
      )`;

      // 打卡点表
      const tombSpotTableSql = `CREATE TABLE IF NOT EXISTS tomb_spots (
        tomb_id TEXT PRIMARY KEY,
        track_id TEXT,
        order_index INTEGER,
        name TEXT,
        person_info TEXT,
        remark TEXT,
        lat REAL,
        lng REAL,
        altitude REAL,
        created_at INTEGER,
        updated_at INTEGER,
        sync_status TEXT DEFAULT 'pending'
      )`;

      // 图文表
      const postTableSql = `CREATE TABLE IF NOT EXISTS posts (
        post_id TEXT PRIMARY KEY,
        tomb_id TEXT,
        track_id TEXT,
        author_user_id TEXT,
        content_text TEXT,
        image_urls TEXT,
        is_pinned INTEGER DEFAULT 0,
        created_at INTEGER,
        updated_at INTEGER,
        sync_status TEXT DEFAULT 'pending'
      )`;

      await this.rdbStore.executeSql(userTableSql);
      await this.rdbStore.executeSql(trackTableSql);
      await this.rdbStore.executeSql(trackPointTableSql);
      await this.rdbStore.executeSql(tombSpotTableSql);
      await this.rdbStore.executeSql(postTableSql);

      hilog.info(LOG_DOMAIN, LOG_TAG, 'All database tables created successfully');
    } catch (error) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Failed to create tables: %{public}s', JSON.stringify(error));
      throw error;
    }
  }

  /**
   * 获取数据库实例
   */
  static getStore(): relationalStore.RdbStore {
    if (!this.rdbStore) {
      throw new Error('RDB Store not initialized');
    }
    return this.rdbStore;
  }

  /**
   * 关闭数据库连接
   */
  static async close(): Promise<void> {
    if (this.rdbStore) {
      try {
        await this.rdbStore.close();
        this.rdbStore = null;
        this.isInitialized = false;
        hilog.info(LOG_DOMAIN, LOG_TAG, 'RDB Store closed successfully');
      } catch (error) {
        hilog.error(LOG_DOMAIN, LOG_TAG, 'Failed to close RDB Store: %{public}s', JSON.stringify(error));
      }
    }
  }
}