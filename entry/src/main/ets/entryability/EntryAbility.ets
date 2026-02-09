import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window, display } from '@kit.ArkUI';
import { AuthStore } from '../common/AuthStore';
import { SyncService } from '../common/SyncService';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    
    // Cloud Foundation Kit 无需手动初始化 AGC，系统 Kit 自动处理

    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    // 设置沉浸式状态栏
    windowStage.getMainWindow().then((windowClass: window.Window) => {
      // 全屏布局（内容延伸到状态栏和导航条区域）
      windowClass.setWindowLayoutFullScreen(true).catch((e: Error) => {
        hilog.error(DOMAIN, 'testTag', 'setWindowLayoutFullScreen fail: %{public}s', JSON.stringify(e));
      });

      // 获取安全区域高度并存入 AppStorage
      try {
        const avoidTop = windowClass.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
        const avoidBottom = windowClass.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
        const screenDensity = display.getDefaultDisplaySync().densityPixels;
        const statusBarH = avoidTop.topRect.height / screenDensity;
        const bottomNavH = avoidBottom.bottomRect.height / screenDensity;

        AppStorage.setOrCreate<number>('statusBarHeight', statusBarH);
        AppStorage.setOrCreate<number>('bottomSafeHeight', bottomNavH);

        hilog.info(DOMAIN, 'testTag',
          'Safe areas: statusBar=%{public}f, bottomNav=%{public}f',
          statusBarH, bottomNavH);
      } catch (e) {
        hilog.error(DOMAIN, 'testTag', 'getWindowAvoidArea fail: %{public}s', JSON.stringify(e));
        AppStorage.setOrCreate<number>('statusBarHeight', 36);
        AppStorage.setOrCreate<number>('bottomSafeHeight', 28);
      }
    }).catch((e: Error) => {
      hilog.error(DOMAIN, 'testTag', 'getMainWindow fail: %{public}s', JSON.stringify(e));
    });

    // 始终先加载启动页，由启动页检查登录态后跳转
    windowStage.loadContent('pages/Splash', (err: Error) => {
      if (err && err.message) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load Splash. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading Splash page.');
    });
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');

    // 回到前台时，触发后台同步（有网时将本地数据同步到云端）
    SyncService.syncAll(this.context).catch((e: Error) => {
      hilog.warn(DOMAIN, 'testTag', 'Background sync failed: %{public}s', JSON.stringify(e));
    });
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }
}