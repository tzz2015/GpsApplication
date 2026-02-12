import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window, display } from '@kit.ArkUI';
import { buffer } from '@kit.ArkTS';
import auth from '@hw-agconnect/auth';
import { CloudDBService } from '../common/CloudDBService';
import { SyncService } from '../common/SyncService';

const DOMAIN = 0x0000;
const TAG = 'EntryAbility';

export default class EntryAbility extends UIAbility {
  /** Auth 就绪 Promise，确保 onForeground 等生命周期等待 auth 完成后再 sync */
  private authReadyPromise: Promise<boolean> | null = null;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to set colorMode: %{public}s', JSON.stringify(err));
    }

    // ★ 初始化 AGC Auth SDK（读取 rawfile 中的 agconnect-services.json）
    try {
      const file = this.context.resourceManager.getRawFileContentSync('agconnect-services.json');
      const json: string = buffer.from(file.buffer).toString();
      auth.init(this.context, json);
      hilog.info(DOMAIN, TAG, '[OK] AGC Auth SDK initialized');
    } catch (err) {
      hilog.error(DOMAIN, TAG, '[ERR] AGC Auth init failed: %{public}s', JSON.stringify(err));
    }

    // ★ 立即启动 Auth 登录 + AuthProvider 注册（不等 loadContent）
    this.authReadyPromise = CloudDBService.ensureAuth();
    this.authReadyPromise.then((ok: boolean) => {
      hilog.info(DOMAIN, TAG, 'Auth ensureAuth result: %{public}s', ok ? 'SUCCESS' : 'FAILED');
    });

    hilog.info(DOMAIN, TAG, 'Ability onCreate');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, TAG, 'Ability onWindowStageCreate');

    // 设置沉浸式状态栏
    windowStage.getMainWindow().then((windowClass: window.Window) => {
      windowClass.setWindowLayoutFullScreen(true).catch((e: Error) => {
        hilog.error(DOMAIN, TAG, 'setWindowLayoutFullScreen fail: %{public}s', JSON.stringify(e));
      });

      try {
        const avoidTop = windowClass.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
        const avoidBottom = windowClass.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
        const screenDensity = display.getDefaultDisplaySync().densityPixels;
        const statusBarH = avoidTop.topRect.height / screenDensity;
        const bottomNavH = avoidBottom.bottomRect.height / screenDensity;

        AppStorage.setOrCreate<number>('statusBarHeight', statusBarH);
        AppStorage.setOrCreate<number>('bottomSafeHeight', bottomNavH);

        hilog.info(DOMAIN, TAG,
          'Safe areas: statusBar=%{public}f, bottomNav=%{public}f',
          statusBarH, bottomNavH);
      } catch (e) {
        hilog.error(DOMAIN, TAG, 'getWindowAvoidArea fail: %{public}s', JSON.stringify(e));
        AppStorage.setOrCreate<number>('statusBarHeight', 36);
        AppStorage.setOrCreate<number>('bottomSafeHeight', 28);
      }
    }).catch((e: Error) => {
      hilog.error(DOMAIN, TAG, 'getMainWindow fail: %{public}s', JSON.stringify(e));
    });

    // 加载启动页
    windowStage.loadContent('pages/Splash', (err: Error) => {
      if (err && err.message) {
        hilog.error(DOMAIN, TAG, 'Failed to load Splash: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, TAG, 'Splash page loaded');
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, TAG, 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(DOMAIN, TAG, 'Ability onForeground');
    // ★ 等待 ensureAuth 完成后再触发同步（ensureAuth 现在始终返回 true）
    if (this.authReadyPromise) {
      this.authReadyPromise.then(() => {
        SyncService.syncAll(this.context).catch((e: Error) => {
          hilog.warn(DOMAIN, TAG, 'Background sync failed: %{public}s', JSON.stringify(e));
        });
      });
    }
  }

  onBackground(): void {
    hilog.info(DOMAIN, TAG, 'Ability onBackground');
  }
}
