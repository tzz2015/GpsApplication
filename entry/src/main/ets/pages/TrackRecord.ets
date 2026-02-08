import { router } from '@kit.ArkUI';
import { MapComponent, mapCommon, map } from '@kit.MapKit';
import { AsyncCallback } from '@kit.BasicServicesKit';
import { geoLocationManager } from '@kit.LocationKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { TrackStore } from '../common/TrackStore';
import { TrackModel } from '../common/TrackModel';

const LOG_DOMAIN = 0x0000;
const LOG_TAG = 'TrackRecord';

/** 路由参数接口 */
interface TrackRecordParams {
  trackId: string;
  title: string;
}

/**
 * P1-3 轨迹记录页
 * 全屏地图 + 实时轨迹 + 起点/打卡点/暂停继续/终点 完整流程
 */
@Entry
@Component
struct TrackRecord {
  // 轨迹基础信息
  private trackId: string = '';
  private trackTitle: string = '';

  // 录制状态
  @State isRecording: boolean = false;
  @State isPaused: boolean = false;
  @State hasStartPoint: boolean = false;
  @State startPointName: string = '';

  // 统计数据
  @State totalDistance: number = 0;
  @State currentAltitude: number = 0;
  @State maxAltitude: number = 0;
  @State elapsedTime: number = 0;
  private recordStartTime: number = 0;
  private pauseStartTime: number = 0;
  private totalPausedTime: number = 0;
  private timerInterval: number = -1;

  // 打卡点
  @State tombSpots: TrackModel.TombSpot[] = [];
  @State showSpotPanel: boolean = false;

  // 弹窗
  @State showStartDialog: boolean = false;
  @State showSpotDialog: boolean = false;
  @State showEndDialog: boolean = false;
  @State showInterruptDialog: boolean = false;
  @State dialogInputText: string = '';

  // 地图
  @State mapCenterLat: number = 23.7275;
  @State mapCenterLng: number = 108.3426;
  private mapOptions?: mapCommon.MapOptions;
  private mapCallback?: AsyncCallback<map.MapComponentController>;
  private mapController?: map.MapComponentController;
  private currentPolyline?: map.MapPolyline;

  // 轨迹点
  private recordPoints: mapCommon.LatLng[] = [];
  private allTrackPoints: TrackModel.TrackPointItem[] = [];
  private lastLat: number = 0;
  private lastLng: number = 0;

  aboutToAppear(): void {
    const params = router.getParams() as TrackRecordParams | undefined;
    if (params) {
      this.trackId = params.trackId || '';
      this.trackTitle = params.title || '';
    }
    this.loadExistingData();
    this.initMap();
  }

  aboutToDisappear(): void {
    this.stopLocationTracking();
    this.stopTimer();
  }

  /** 加载已有数据（继续记录时用） */
  private async loadExistingData(): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.Context;
    const track = await TrackStore.getTrackById(context, this.trackId);
    if (track && track.startName.length > 0) {
      this.hasStartPoint = true;
      this.startPointName = track.startName;
      this.totalDistance = track.totalDistance;
      this.maxAltitude = track.maxAltitude;
      if (track.startLat !== 0) {
        this.mapCenterLat = track.startLat;
        this.mapCenterLng = track.startLng;
      }
    }
    this.tombSpots = await TrackStore.getTombSpotsByTrackId(context, this.trackId);

    // 加载已有轨迹点
    const points = await TrackStore.getTrackPointsByTrackId(context, this.trackId);
    for (let i = 0; i < points.length; i++) {
      const p = points[i];
      this.recordPoints.push({ latitude: p.latitude, longitude: p.longitude });
    }
  }

  private initMap(): void {
    this.mapOptions = {
      position: {
        target: { latitude: this.mapCenterLat, longitude: this.mapCenterLng },
        zoom: 16
      },
      myLocationControlsEnabled: true,
      scaleControlsEnabled: true
    };
    this.mapCallback = async (err: Error, controller: map.MapComponentController) => {
      if (!err) {
        this.mapController = controller;
        this.moveToCurrentLocation();
        if (this.recordPoints.length >= 2) {
          this.updatePolyline();
        }
      }
    };
  }

  /** 获取当前位置并移动地图 */
  private moveToCurrentLocation(): void {
    const request: geoLocationManager.SingleLocationRequest = {
      locatingPriority: geoLocationManager.LocatingPriority.PRIORITY_ACCURACY,
      locatingTimeoutMs: 10000
    };
    geoLocationManager.getCurrentLocation(request).then((location: geoLocationManager.Location) => {
      this.mapCenterLat = location.latitude;
      this.mapCenterLng = location.longitude;
      this.currentAltitude = Math.round(location.altitude);
      this.lastLat = location.latitude;
      this.lastLng = location.longitude;
    }).catch((e: Error) => {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'getCurrentLocation fail: %{public}s', JSON.stringify(e));
    });
  }

  /** 开始持续定位记录 */
  private startLocationTracking(): void {
    const request: geoLocationManager.ContinuousLocationRequest = {
      interval: 3,
      locationScenario: geoLocationManager.UserActivityScenario.NAVIGATION
    };
    geoLocationManager.on('locationChange', request, (location: geoLocationManager.Location) => {
      if (this.isPaused) {
        return;
      }
      const lat = location.latitude;
      const lng = location.longitude;
      const alt = Math.round(location.altitude);

      // 距离阈值过滤：至少移动3米才记录
      if (this.lastLat !== 0) {
        const dist = TrackModel.calculateDistance(this.lastLat, this.lastLng, lat, lng);
        if (dist < 3) {
          return;
        }
        this.totalDistance += dist;
      }

      this.lastLat = lat;
      this.lastLng = lng;
      this.currentAltitude = alt;
      if (alt > this.maxAltitude) {
        this.maxAltitude = alt;
      }

      // 记录轨迹点
      this.recordPoints.push({ latitude: lat, longitude: lng });
      const point: TrackModel.TrackPointItem = {
        pointId: this.trackId + '_pt_' + Date.now(),
        latitude: lat,
        longitude: lng,
        altitude: alt,
        accuracy: location.accuracy || 0,
        timestamp: Date.now(),
        syncStatus: 'pending'
      };
      this.allTrackPoints.push(point);

      // 更新地图折线
      this.updatePolyline();
    });
  }

  private stopLocationTracking(): void {
    try {
      geoLocationManager.off('locationChange');
    } catch (e) {
      hilog.info(LOG_DOMAIN, LOG_TAG, 'off locationChange: %{public}s', JSON.stringify(e));
    }
  }

  /** 更新地图上的轨迹折线 */
  private async updatePolyline(): Promise<void> {
    if (!this.mapController || this.recordPoints.length < 2) {
      return;
    }
    try {
      if (this.currentPolyline) {
        await this.currentPolyline.remove();
      }
      const polylineOption: mapCommon.MapPolylineOptions = {
        points: this.recordPoints,
        color: 0xFFFF6B35, // 橙色轨迹线
        width: 14,
        visible: true
      };
      this.currentPolyline = await this.mapController.addPolyline(polylineOption);
    } catch (e) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'updatePolyline: %{public}s', JSON.stringify(e));
    }
  }

  /** 计时器 */
  private startTimer(): void {
    this.recordStartTime = Date.now();
    this.timerInterval = setInterval(() => {
      if (!this.isPaused) {
        this.elapsedTime = Date.now() - this.recordStartTime - this.totalPausedTime;
      }
    }, 1000);
  }

  private stopTimer(): void {
    if (this.timerInterval !== -1) {
      clearInterval(this.timerInterval);
      this.timerInterval = -1;
    }
  }

  // ==================== 用户操作 ====================

  /** 设置起点 */
  private async confirmSetStart(): Promise<void> {
    const name = this.dialogInputText.trim() || '起点';
    this.startPointName = name;
    this.hasStartPoint = true;
    this.isRecording = true;
    this.isPaused = false;
    this.showStartDialog = false;
    this.dialogInputText = '';

    // 保存起点信息到轨迹
    const context = this.getUIContext().getHostContext() as common.Context;
    await TrackStore.updateTrack(context, this.trackId, {
      startName: name,
      startLat: this.mapCenterLat,
      startLng: this.mapCenterLng
    });

    // 开始定位和计时
    this.startLocationTracking();
    this.startTimer();
  }

  /** 暂停/继续 */
  private togglePause(): void {
    if (this.isPaused) {
      // 继续
      this.totalPausedTime += Date.now() - this.pauseStartTime;
      this.isPaused = false;
    } else {
      // 暂停
      this.pauseStartTime = Date.now();
      this.isPaused = true;
    }
  }

  /** 添加打卡点 */
  private async confirmAddSpot(): Promise<void> {
    const name = this.dialogInputText.trim() || '打卡点';
    this.showSpotDialog = false;
    this.dialogInputText = '';

    const context = this.getUIContext().getHostContext() as common.Context;
    const spot: TrackModel.TombSpot = {
      tombId: TrackModel.generateId('tomb'),
      trackId: this.trackId,
      orderIndex: this.tombSpots.length,
      name: name,
      personInfo: '',
      remark: '',
      latitude: this.lastLat,
      longitude: this.lastLng,
      altitude: this.currentAltitude,
      contentText: '',
      imageUris: '[]',
      createdAt: Date.now(),
      updatedAt: Date.now()
    };

    await TrackStore.saveTombSpot(context, spot);
    this.tombSpots.push(spot);

    // 保存已采集的轨迹点到本地
    if (this.allTrackPoints.length > 0) {
      await TrackStore.saveTrackPoints(context, this.trackId, this.allTrackPoints);
      this.allTrackPoints = [];
    }

    // 保存轨迹统计
    await TrackStore.updateTrack(context, this.trackId, {
      totalDistance: this.totalDistance,
      maxAltitude: this.maxAltitude,
      totalDuration: this.elapsedTime
    });

    // 跳到打卡点详情页填写图文
    router.pushUrl({
      url: 'pages/TombSpotDetail',
      params: {
        tombId: spot.tombId,
        trackId: this.trackId,
        trackTitle: this.trackTitle,
        fromRecording: true
      }
    });
  }

  /** 设置终点并结束轨迹 */
  private async confirmSetEnd(): Promise<void> {
    const name = this.dialogInputText.trim() || '终点';
    this.showEndDialog = false;
    this.dialogInputText = '';

    this.stopLocationTracking();
    this.stopTimer();

    const context = this.getUIContext().getHostContext() as common.Context;

    // 保存剩余轨迹点
    if (this.allTrackPoints.length > 0) {
      await TrackStore.saveTrackPoints(context, this.trackId, this.allTrackPoints);
      this.allTrackPoints = [];
    }

    // 更新轨迹为已完成
    await TrackStore.updateTrack(context, this.trackId, {
      status: TrackModel.TRACK_STATUS_DONE,
      endName: name,
      endLat: this.lastLat,
      endLng: this.lastLng,
      totalDistance: this.totalDistance,
      totalDuration: this.elapsedTime,
      maxAltitude: this.maxAltitude
    });

    // 跳转到轨迹详情页
    router.replaceUrl({
      url: 'pages/TrackDetail',
      params: { trackId: this.trackId, title: this.trackTitle }
    });
  }

  /** 中断记录 */
  private async confirmInterrupt(): Promise<void> {
    this.showInterruptDialog = false;
    this.stopLocationTracking();
    this.stopTimer();

    // 保存当前进度
    const context = this.getUIContext().getHostContext() as common.Context;
    if (this.allTrackPoints.length > 0) {
      await TrackStore.saveTrackPoints(context, this.trackId, this.allTrackPoints);
    }
    await TrackStore.updateTrack(context, this.trackId, {
      totalDistance: this.totalDistance,
      totalDuration: this.elapsedTime,
      maxAltitude: this.maxAltitude
    });

    router.back();
  }

  onPageShow(): void {
    // 从打卡点详情返回后刷新打卡点列表
    const context = this.getUIContext().getHostContext() as common.Context;
    TrackStore.getTombSpotsByTrackId(context, this.trackId).then((spots: TrackModel.TombSpot[]) => {
      this.tombSpots = spots;
    });
    if (this.mapController) {
      this.mapController.show();
    }
  }

  onPageHide(): void {
    if (this.mapController) {
      this.mapController.hide();
    }
  }

  build() {
    Stack() {
      // 地图
      Column() {
        MapComponent({
          mapOptions: this.mapOptions,
          mapCallback: this.mapCallback
        })
          .width('100%')
          .height('100%');
      }
      .width('100%')
      .height('100%');

      // 返回按钮（左上角）
      Row() {
        Button() {
          Text('‹')
            .fontSize(24)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.label_primary'));
        }
        .width(40)
        .height(40)
        .backgroundColor($r('app.color.card_background'))
        .borderRadius(12)
        .shadow({ radius: 8, color: '#1A000000', offsetX: 0, offsetY: 2 })
        .onClick(() => {
          if (this.isRecording) {
            this.showInterruptDialog = true;
          } else {
            router.back();
          }
        });
      }
      .position({ x: 12, y: 52 })
      .zIndex(10);

      // 底部录制面板
      Column() {
        // 录制状态
        if (this.isRecording) {
          Row({ space: 6 }) {
            Circle({ width: 8, height: 8 })
              .fill(this.isPaused ? $r('app.color.warning') : $r('app.color.destructive'));
            Text(this.isPaused ? '已暂停' : '录制中')
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.isPaused ? $r('app.color.warning') : $r('app.color.destructive'));
          }
          .justifyContent(FlexAlign.Center)
          .width('100%')
          .margin({ bottom: 12 });
        }

        // 统计数据
        Row() {
          Column() {
            Text(TrackModel.formatDistance(this.totalDistance))
              .fontSize(24)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.label_primary'));
            Text('距离')
              .fontSize(11)
              .fontColor($r('app.color.label_tertiary'));
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Center);

          Column() {
            Text(TrackModel.formatDuration(this.elapsedTime))
              .fontSize(24)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.label_primary'));
            Text('时长')
              .fontSize(11)
              .fontColor($r('app.color.label_tertiary'));
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Center);

          Column() {
            Text(this.currentAltitude.toString() + 'm')
              .fontSize(24)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.label_primary'));
            Text('海拔')
              .fontSize(11)
              .fontColor($r('app.color.label_tertiary'));
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Center);
        }
        .width('100%')
        .margin({ bottom: 16 });

        // 已打卡点快捷入口
        if (this.tombSpots.length > 0) {
          Row() {
            Text('📍')
              .fontSize(16);
            Text(`已添加 ${this.tombSpots.length} 个打卡点`)
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.label_primary'));
            if (this.tombSpots.length > 0) {
              Text(' · ' + this.tombSpots[this.tombSpots.length - 1].name)
                .fontSize(13)
                .fontColor($r('app.color.label_tertiary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1);
            }
            Blank();
            Text('›')
              .fontSize(16)
              .fontColor($r('app.color.label_tertiary'));
          }
          .width('100%')
          .padding(12)
          .backgroundColor($r('app.color.app_background'))
          .borderRadius(10)
          .margin({ bottom: 14 })
          .onClick(() => {
            this.showSpotPanel = !this.showSpotPanel;
          });
        }

        // 操作按钮
        if (!this.hasStartPoint) {
          // 未设置起点
          Button('设置起点开始记录')
            .width('100%')
            .height(50)
            .fontSize(17)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.button_primary_text'))
            .backgroundColor($r('app.color.accent'))
            .borderRadius(25)
            .onClick(() => {
              this.showStartDialog = true;
            });
        } else {
          // 已设置起点：打卡点 / 暂停继续 / 终点
          Row({ space: 16 }) {
            // 打卡点按钮
            Button() {
              Column({ space: 4 }) {
                Text('📍')
                  .fontSize(20);
                Text('打卡')
                  .fontSize(10)
                  .fontColor($r('app.color.label_secondary'));
              }
            }
            .width(56)
            .height(56)
            .backgroundColor($r('app.color.app_background'))
            .borderRadius(28)
            .onClick(() => {
              this.showSpotDialog = true;
            });

            // 暂停/继续按钮
            Button() {
              Text(this.isPaused ? '▶' : '⏸')
                .fontSize(24)
                .fontColor(Color.White);
            }
            .width(64)
            .height(64)
            .backgroundColor($r('app.color.accent'))
            .borderRadius(32)
            .shadow({ radius: 12, color: '#33FF6B35', offsetX: 0, offsetY: 4 })
            .onClick(() => {
              this.togglePause();
            });

            // 终点按钮
            Button() {
              Column({ space: 4 }) {
                Text('⏹')
                  .fontSize(20);
                Text('终点')
                  .fontSize(10)
                  .fontColor(Color.White);
              }
            }
            .width(56)
            .height(56)
            .backgroundColor($r('app.color.destructive'))
            .borderRadius(28)
            .onClick(() => {
              this.showEndDialog = true;
            });
          }
          .justifyContent(FlexAlign.Center)
          .width('100%');
        }
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 16, bottom: 40 })
      .backgroundColor($r('app.color.card_background'))
      .borderRadius({ topLeft: 20, topRight: 20 })
      .shadow({ radius: 16, color: '#1A000000', offsetX: 0, offsetY: -4 })
      .position({ x: 0, y: '100%' })
      .translate({ y: this.hasStartPoint ? -260 : -180 })
      .zIndex(20);

      // ========== 弹窗们 ==========

      // 设置起点弹窗
      if (this.showStartDialog) {
        this.DialogOverlay('设置起点', '确认当前位置为扫墓起点', '例如：山脚入口', () => {
          this.confirmSetStart();
        }, () => {
          this.showStartDialog = false;
          this.dialogInputText = '';
        });
      }

      // 设置打卡点弹窗
      if (this.showSpotDialog) {
        this.DialogOverlay('设置打卡点', '已记录当前位置，请为此墓地点命名', '例如：祖父某某之墓', () => {
          this.confirmAddSpot();
        }, () => {
          this.showSpotDialog = false;
          this.dialogInputText = '';
        });
      }

      // 设置终点弹窗
      if (this.showEndDialog) {
        this.DialogOverlay('设置终点', '确认结束轨迹记录？', '例如：山脚出口', () => {
          this.confirmSetEnd();
        }, () => {
          this.showEndDialog = false;
          this.dialogInputText = '';
        });
      }

      // 中断确认弹窗
      if (this.showInterruptDialog) {
        Column() {
          Column() {
            Text('中断记录')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.label_primary'))
              .margin({ bottom: 8 });
            Text('当前轨迹正在记录中，是否暂时退出？\n退出后可在轨迹详情页继续记录。')
              .fontSize(14)
              .fontColor($r('app.color.label_secondary'))
              .textAlign(TextAlign.Center)
              .lineHeight(22)
              .margin({ bottom: 20 });
            Row({ space: 12 }) {
              Button('继续录制')
                .layoutWeight(1)
                .height(44)
                .fontSize(15)
                .fontColor($r('app.color.primary'))
                .backgroundColor($r('app.color.primary_light'))
                .borderRadius(22)
                .onClick(() => {
                  this.showInterruptDialog = false;
                });
              Button('暂时退出')
                .layoutWeight(1)
                .height(44)
                .fontSize(15)
                .fontColor($r('app.color.button_primary_text'))
                .backgroundColor($r('app.color.primary'))
                .borderRadius(22)
                .onClick(() => {
                  this.confirmInterrupt();
                });
            }
            .width('100%');
          }
          .width(300)
          .padding(24)
          .backgroundColor($r('app.color.card_background'))
          .borderRadius(20)
          .shadow({ radius: 24, color: '#33000000', offsetX: 0, offsetY: 8 });
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')
        .justifyContent(FlexAlign.Center)
        .zIndex(100)
        .onClick(() => {
          this.showInterruptDialog = false;
        });
      }
    }
    .width('100%')
    .height('100%');
  }

  @Builder
  DialogOverlay(
    title: string,
    desc: string,
    placeholder: string,
    onConfirm: () => void,
    onCancel: () => void
  ) {
    Column() {
      Column() {
        Text(title)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.label_primary'))
          .margin({ bottom: 8 });
        Text(desc)
          .fontSize(14)
          .fontColor($r('app.color.label_secondary'))
          .textAlign(TextAlign.Center)
          .margin({ bottom: 16 });
        TextInput({ placeholder: placeholder, text: this.dialogInputText })
          .onChange((value: string) => {
            this.dialogInputText = value;
          })
          .width('100%')
          .height(44)
          .fontSize(15)
          .backgroundColor($r('app.color.app_background'))
          .borderRadius(10)
          .padding({ left: 12, right: 12 })
          .margin({ bottom: 16 });
        Row({ space: 12 }) {
          Button('取消')
            .layoutWeight(1)
            .height(44)
            .fontSize(15)
            .fontColor($r('app.color.primary'))
            .backgroundColor($r('app.color.primary_light'))
            .borderRadius(22)
            .onClick(onCancel);
          Button('确认')
            .layoutWeight(1)
            .height(44)
            .fontSize(15)
            .fontColor($r('app.color.button_primary_text'))
            .backgroundColor($r('app.color.primary'))
            .borderRadius(22)
            .onClick(onConfirm);
        }
        .width('100%');
      }
      .width(300)
      .padding(24)
      .backgroundColor($r('app.color.card_background'))
      .borderRadius(20)
      .shadow({ radius: 24, color: '#33000000', offsetX: 0, offsetY: 8 });
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#66000000')
    .justifyContent(FlexAlign.Center)
    .zIndex(100);
  }
}
