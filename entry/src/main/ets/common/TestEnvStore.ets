import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Config } from './Config';

const LOG_DOMAIN = 0x0000;
const LOG_TAG = 'TestEnvStore';

const PREF_NAME = 'dev_test_env_prefs';
const KEY_USE_TEST_DATA = 'use_test_data';

/**
 * 测试环境开关持久化
 * - 仅开发者模式生效
 * - 生产模式下始终返回 false
 */
export class TestEnvStore {
  private static useTestDataCache: boolean = false;
  private static initialized: boolean = false;

  static async init(context: common.Context): Promise<void> {
    if (!Config.IS_DEVELOPMENT_MODE) {
      TestEnvStore.useTestDataCache = false;
      TestEnvStore.initialized = true;
      return;
    }
    try {
      const prefs = await preferences.getPreferences(context, PREF_NAME);
      const value = await prefs.get(KEY_USE_TEST_DATA, true) as boolean;
      TestEnvStore.useTestDataCache = value;
    } catch (_e) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'init prefs: %{public}s', JSON.stringify(_e));
      TestEnvStore.useTestDataCache = true;
    } finally {
      TestEnvStore.initialized = true;
    }
  }

  static isUseTestDataSync(): boolean {
    if (!Config.IS_DEVELOPMENT_MODE) {
      return false;
    }
    return TestEnvStore.useTestDataCache;
  }

  static async isUseTestData(context: common.Context): Promise<boolean> {
    if (!TestEnvStore.initialized) {
      await TestEnvStore.init(context);
    }
    return TestEnvStore.isUseTestDataSync();
  }

  static async setUseTestData(context: common.Context, enabled: boolean): Promise<void> {
    if (!Config.IS_DEVELOPMENT_MODE) {
      TestEnvStore.useTestDataCache = false;
      TestEnvStore.initialized = true;
      return;
    }
    TestEnvStore.useTestDataCache = enabled;
    TestEnvStore.initialized = true;
    try {
      const prefs = await preferences.getPreferences(context, PREF_NAME);
      await prefs.put(KEY_USE_TEST_DATA, enabled);
      await prefs.flush();
    } catch (_e) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'setUseTestData persist: %{public}s', JSON.stringify(_e));
    }
  }
}
