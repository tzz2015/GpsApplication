import { promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { NavBar } from '../common/NavBar';
import { Config } from '../common/Config';
import { TestEnvStore } from '../common/TestEnvStore';
import { CloudDBService } from '../common/CloudDBService';

/**
 * 开发测试入口页
 * - 仅在开发者模式下可进入
 * - 控制测试数据开关（Cloud DB Zone + Cloud Storage 路径前缀）
 * - 提供 Cloud DB 诊断入口
 */
@Entry
@Component
struct TestLab {
  @State useTestData: boolean = false;
  @State isLoaded: boolean = false;
  @State isDiagnosing: boolean = false;
  @State diagResult: string = '';

  aboutToAppear(): void {
    this.loadState();
  }

  private async loadState(): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.Context;
    await TestEnvStore.init(context);
    this.useTestData = await TestEnvStore.isUseTestData(context);
    this.isLoaded = true;
  }

  private getCurrentZoneName(): string {
    return this.useTestData ? Config.CLOUD_DB_ZONE_TEST : Config.CLOUD_DB_ZONE_PROD;
  }

  private getStoragePathRule(): string {
    return this.useTestData ? 'test/tracks/... | test/users/...' : 'tracks/... | users/...';
  }

  private async onToggleTestData(enable: boolean): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.Context;
    await TestEnvStore.setUseTestData(context, enable);
    CloudDBService.resetZoneCache();
    this.useTestData = enable;
    try {
      promptAction.showToast({
        message: enable ? '已切换到测试数据' : '已切换到正式数据'
      });
    } catch (_e) {
    }
  }

  private runDiagnosis(): void {
    this.isDiagnosing = true;
    this.diagResult = '';
    CloudDBService.diagnose().then((result: string) => {
      this.diagResult = result;
      this.isDiagnosing = false;
    }).catch((e: Error) => {
      this.diagResult = '诊断异常: ' + JSON.stringify(e);
      this.isDiagnosing = false;
    });
  }

  build() {
    Column() {
      NavBar({ title: '测试入口', showBack: true });

      if (!Config.IS_DEVELOPMENT_MODE) {
        Column({ space: 12 }) {
          Text('当前不是开发者模式，测试入口不可用')
            .fontSize(15)
            .fontColor($r('app.color.label_secondary'));
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center);
      } else {
        Scroll() {
          Column({ space: 12 }) {
            Column({ space: 12 }) {
              Text('数据环境')
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.label_primary'))
                .width('100%');

              Row() {
                Column({ space: 4 }) {
                  Text('使用测试数据')
                    .fontSize(15)
                    .fontColor($r('app.color.label_primary'));
                  Text(this.useTestData ? '开启后使用测试存储区与路径前缀' : '关闭后使用正式存储区')
                    .fontSize(12)
                    .fontColor($r('app.color.label_tertiary'));
                }
                .layoutWeight(1)
                Toggle({ type: ToggleType.Switch, isOn: this.useTestData })
                  .onChange((on: boolean) => {
                    this.onToggleTestData(on);
                  });
              }
              .width('100%');

              Column({ space: 6 }) {
                Text('Cloud DB Zone: ' + this.getCurrentZoneName())
                  .fontSize(13)
                  .fontColor($r('app.color.label_secondary'))
                  .width('100%');
                Text('Cloud Storage 路径: ' + this.getStoragePathRule())
                  .fontSize(13)
                  .fontColor($r('app.color.label_secondary'))
                  .width('100%');
              }
              .width('100%')
              .padding(12)
              .backgroundColor($r('app.color.app_background'))
              .borderRadius(10);
            }
            .width('100%')
            .padding(16)
            .backgroundColor($r('app.color.card_background'))
            .borderRadius(12);

            Column({ space: 8 }) {
              Text('连通性诊断')
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.label_primary'))
                .width('100%');

              Button(this.isDiagnosing ? '诊断中...' : '诊断 Cloud DB 连通性')
                .width('100%')
                .height(46)
                .fontSize(14)
                .fontColor($r('app.color.primary'))
                .backgroundColor($r('app.color.app_background'))
                .borderRadius(10)
                .enabled(!this.isDiagnosing && this.isLoaded)
                .onClick(() => {
                  this.runDiagnosis();
                });

              if (this.diagResult.length > 0) {
                Text(this.diagResult)
                  .fontSize(12)
                  .fontColor($r('app.color.label_secondary'))
                  .lineHeight(18)
                  .width('100%')
                  .padding(12)
                  .backgroundColor($r('app.color.app_background'))
                  .borderRadius(10);
              }
            }
            .width('100%')
            .padding(16)
            .backgroundColor($r('app.color.card_background'))
            .borderRadius(12);
          }
          .width('100%')
          .padding(16);
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .backgroundColor($r('app.color.app_background'));
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.app_background'));
  }
}
