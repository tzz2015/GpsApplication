import { abilityAccessCtrl } from '@kit.AbilityKit';
import { geoLocationManager } from '@kit.LocationKit';

import promptAction from '@ohos.promptAction';

const atManager = abilityAccessCtrl.createAtManager();

@Entry
@Component
struct Index {
  @State message: string = 'Hello World';
  @State currentLocation: string = '等待获取位置信息...';
  @State locationStatus: string = '定位状态：准备中';
  @State accuracy: string = '精度：-- 米';
  @State timestamp: string = '时间：--';
  @State speed: string = '速度：-- m/s';
  @State altitude: string = '海拔：-- 米';
  @State isTracking: boolean = false;
  @State locationHistory: Array<string> = [];

  aboutToAppear(): void {
    this.requestLocationPermission();
  }

  aboutToDisappear(): void {
    this.stopLocation()
  }

  // 请求定位权限
  requestLocationPermission(): void {
    // 申请定位权限
    atManager.requestPermissionsFromUser(this.getUIContext().getHostContext(),
      ['ohos.permission.LOCATION', 'ohos.permission.APPROXIMATELY_LOCATION']).catch(() => {
      console.error('Location permission request fail')
      this.locationStatus = '定位状态：权限获取失败'
    })
      .then((data) => {
        /* 处理授权结果 */
        console.info('Location permission granted' + JSON.stringify(data))
        this.locationStatus = '定位状态：权限已获取'
      });
  }

  // 开始持续定位
  startContinuousLocation(): void {
    try {
      let request: geoLocationManager.ContinuousLocationRequest = {
        'interval': 1, // 上报间隔1秒
        'locationScenario': geoLocationManager.UserActivityScenario.NAVIGATION
      };

      geoLocationManager.on('locationChange', request, (location) => {
        console.log(`实时位置: ${JSON.stringify(location)}`);
        this.updateLocationDisplay(location);
        this.recordLocationHistory(location);
      });

      this.isTracking = true;
      this.locationStatus = '定位状态：持续定位中...';
      promptAction.openToast({
        message: '开始持续定位',
        duration: 2000
      });
    } catch (error) {
      console.error('Failed to start location: ' + JSON.stringify(error));
      this.locationStatus = '定位状态：启动失败';
    }
  }

  // 停止定位
  stopLocation(): void {
    try {
      geoLocationManager.off('locationChange');
      this.isTracking = false;
      this.locationStatus = '定位状态：已停止';
    } catch (error) {
    }
  }

  // 更新位置显示
  updateLocationDisplay(location: geoLocationManager.Location): void {
    this.currentLocation = `经度：${location.longitude.toFixed(6)}\n纬度：${location.latitude.toFixed(6)}';
    this.accuracy = '精度：${location.accuracy.toFixed(2)} 米';
    this.altitude = '海拔：${location.altitude ? location.altitude.toFixed(2) : '--'} 米`;
    this.speed = `速度：${location.speed ? location.speed.toFixed(2) : '--'} m/s`;
    this.timestamp = `时间：${this.formatLocationTime(location.timeStamp)}`;
  }

  // 记录位置历史
  recordLocationHistory(location: geoLocationManager.Location): void {
    let record =
      `[${this.formatLocationTime(location.timeStamp)}] 经度${location.longitude.toFixed(6)}, 纬度${location.latitude.toFixed(6)}`;
    this.locationHistory.unshift(record);
    // 只保留最近20条记录
    if (this.locationHistory.length > 20) {
      this.locationHistory = this.locationHistory.slice(0, 20);
    }
  }

  // 格式化时间
  formatLocationTime(timestamp: number): string {
    let date = new Date(timestamp);
    return `${date.getHours().toString().padStart(2, '0')}:${date.getMinutes()
      .toString()
      .padStart(2, '0')}:${date.getSeconds().toString().padStart(2, '0')}`;
  }

  // 获取单次位置
  getCurrentLocation(): void {
    // 配置定位请求参数
    let request: geoLocationManager.SingleLocationRequest = {
      'locatingPriority': geoLocationManager.LocatingPriority.PRIORITY_ACCURACY, // 高精度
      'locatingTimeoutMs': 10000 // 超时时间10秒
    };

    try {
      geoLocationManager.getCurrentLocation(request).then((result) => {
        console.log(`纬度: ${result.latitude}, 经度: ${result.longitude}`);
        this.updateLocationDisplay(result)
      })
    } catch (err) {
      console.error(`异常: ${JSON.stringify(err)}`);
    }
  }

  // 清空位置历史
  clearLocationHistory(): void {
    this.locationHistory = [];
    try {
      promptAction.openToast({
        message: '位置历史已清空',
        duration: 1500
      });
    } catch (_e) {
      // 忽略 Toast 调用异常
    }
  }

  build() {
    Column({ space: 20 }) {
      // 标题
      Text('鸿蒙持续定位应用')
        .fontSize(24)
        .fontColor('#1E90FF')
        .fontWeight(FontWeight.Bold)
        .margin({ top: 20 });

      // 定位状态显示
      Text(this.locationStatus)
        .fontSize(16)
        .fontColor(this.isTracking ? '#32CD32' : '#FF4500')
        .padding(10)
        .backgroundColor('#F0F8FF')
        .borderRadius(8)
        .width('90%');

      // 位置信息卡片
      Column({ space: 12 }) {
        Text('当前位置信息')
          .fontSize(18)
          .fontColor('#2F4F4F')
          .fontWeight(FontWeight.Medium);

        Text(this.currentLocation)
          .fontSize(14)
          .fontColor('#696969')
          .textAlign(TextAlign.Start)
          .padding(16)
          .backgroundColor('#FFFFFF')
          .borderRadius(12)
          .border({ width: 1, color: '#E6E6FA' })
          .width('90%');

        // 详细信息行
        Row({ space: 15 }) {
          Text(this.accuracy)
            .fontSize(12)
            .fontColor('#808080')
            .layoutWeight(1);

          Text(this.altitude)
            .fontSize(12)
            .fontColor('#808080')
            .layoutWeight(1);
        }
        .width('90%');

        Row({ space: 15 }) {
          Text(this.speed)
            .fontSize(12)
            .fontColor('#808080')
            .layoutWeight(1);

          Text(this.timestamp)
            .fontSize(12)
            .fontColor('#808080')
            .layoutWeight(1);
        }
        .width('90%');
      }
      .width('100%');

      // 控制按钮区域
      Row({ space: 20 }) {
        Button(this.isTracking ? '停止定位' : '开始持续定位')
          .fontSize(14)
          .fontColor('#FFFFFF')
          .backgroundColor(this.isTracking ? '#FF6347' : '#32CD32')
          .borderRadius(20)
          .padding(12)
          .layoutWeight(1)
          .onClick(() => {
            if (this.isTracking) {
              this.stopLocation();
            } else {
              this.startContinuousLocation();
            }
          });

        Button('获取当前位置')
          .fontSize(14)
          .fontColor('#FFFFFF')
          .backgroundColor('#1E90FF')
          .borderRadius(20)
          .padding(12)
          .layoutWeight(1)
          .onClick(() => {
            this.getCurrentLocation();
          });
      }
      .width('90%')
      .margin({ top: 10 });

      // 位置历史记录
      Column({ space: 10 }) {
        Text('位置历史记录')
          .fontSize(16)
          .fontColor('#2F4F4F')
          .fontWeight(FontWeight.Medium);

        if (this.locationHistory.length > 0) {
          List({ space: 8 }) {
            ForEach(this.locationHistory, (item: string) => {
              ListItem() {
                Text(item)
                  .fontSize(12)
                  .fontColor('#696969')
                  .padding(8)
                  .backgroundColor('#F8F8FF')
                  .borderRadius(6)
                  .width('90%');
              }
            })
          }
          .height(200)
          .width('90%')

        } else {
          Text('暂无位置记录')
            .fontSize(14)
            .fontColor('#A9A9A9')
            .padding(20);
        }

        Button('清空历史记录')
          .fontSize(12)
          .fontColor('#FFFFFF')
          .backgroundColor('#B0C4DE')
          .borderRadius(15)
          .padding(8)
          .onClick(() => {
            this.clearLocationHistory();
          });
      }
      .width('90%')
      .margin({ bottom: 20 });
    }
    .width('100%')
    .height('100%')
    .padding(16)
    .backgroundColor('#F5F5F5');
  }
}