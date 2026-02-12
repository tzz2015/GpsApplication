import { MapComponent, mapCommon, map } from '@kit.MapKit';
import { AsyncCallback } from '@kit.BasicServicesKit';
import { geoLocationManager } from '@kit.LocationKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { image } from '@kit.ImageKit';
import { fileIo } from '@kit.CoreFileKit';
import { TrackStore } from '../common/TrackStore';
import { TrackModel } from '../common/TrackModel';
import { SyncService } from '../common/SyncService';

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
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafeHeight: number = 0;
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
  @State showLayerPanel: boolean = false;
  @State currentMapType: number = 1; // 1=标准, 2=卫星, 3=地形（对应 HMS MapType 枚举值）
  @State is3DMode: boolean = false;
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
    const params = this.getUIContext().getRouter().getParams() as TrackRecordParams | undefined;
    if (params) {
      this.trackId = params.trackId || '';
      this.trackTitle = params.title || '';
    }
    // 先尝试获取最近已知位置，快速定位地图中心
    this.getLastKnownLocation();
    this.loadExistingData();
    this.initMap();
  }

  /** 获取最近已知位置，用于快速初始化地图中心 */
  private getLastKnownLocation(): void {
    try {
      const lastLocation = geoLocationManager.getLastLocation();
      if (lastLocation && lastLocation.latitude !== 0) {
        this.mapCenterLat = lastLocation.latitude;
        this.mapCenterLng = lastLocation.longitude;
        hilog.info(LOG_DOMAIN, LOG_TAG,
          'Last known location: %{public}f, %{public}f',
          lastLocation.latitude, lastLocation.longitude);
      }
    } catch (e) {
      hilog.info(LOG_DOMAIN, LOG_TAG, 'getLastLocation: %{public}s', JSON.stringify(e));
    }
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
      this.elapsedTime = track.totalDuration || 0;
      this.isRecording = true;
      if (track.startLat !== 0) {
        this.mapCenterLat = track.startLat;
        this.mapCenterLng = track.startLng;
      }
      // 继续记录：恢复计时并重新开启定位
      this.startTimer(this.elapsedTime);
      this.startLocationTracking();
    }
    this.tombSpots = await TrackStore.getTombSpotsByTrackId(context, this.trackId);

    // 加载已有轨迹点
    const points = await TrackStore.getTrackPointsByTrackId(context, this.trackId);
    for (let i = 0; i < points.length; i++) {
      const p = points[i];
      this.recordPoints.push({ latitude: p.latitude, longitude: p.longitude });
    }

    // 如果地图已就绪，移动相机并绘制已有轨迹
    if (this.mapController) {
      this.moveCameraTo(this.mapCenterLat, this.mapCenterLng, 16);
      if (this.recordPoints.length >= 2) {
        this.updatePolyline();
      }
    }
  }

  private initMap(): void {
    this.mapOptions = {
      position: {
        target: { latitude: this.mapCenterLat, longitude: this.mapCenterLng },
        zoom: 16
      },
      mapType: 1,
      myLocationControlsEnabled: true,
      scaleControlsEnabled: true
    };
    this.mapCallback = async (err: Error, controller: map.MapComponentController) => {
      if (!err) {
        this.mapController = controller;
        // 启用我的位置图层
        try {
          controller.setMyLocationEnabled(true);
        } catch (e) {
          hilog.info(LOG_DOMAIN, LOG_TAG, 'setMyLocationEnabled: %{public}s', JSON.stringify(e));
        }
        // 默认设置标准图层（1 = STANDARD）
        try {
          controller.setMapType(1);
        } catch (e) {
          hilog.info(LOG_DOMAIN, LOG_TAG, 'setMapType standard: %{public}s', JSON.stringify(e));
        }
        // 定位到当前位置
        this.moveToCurrentLocation();
        // 绘制已有轨迹（若 loadExistingData 已完成）
        if (this.recordPoints.length >= 2) {
          this.updatePolyline();
        }
      }
    };
  }

  /** WGS84 坐标转 GCJ02（华为地图使用 GCJ02） */
  private async convertToGCJ02(lat: number, lng: number): Promise<mapCommon.LatLng> {
    try {
      const wgs84: mapCommon.LatLng = { latitude: lat, longitude: lng };
      const gcj02: mapCommon.LatLng = await map.convertCoordinate(
        mapCommon.CoordinateType.WGS84,
        mapCommon.CoordinateType.GCJ02,
        wgs84
      );
      return gcj02;
    } catch (e) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'convertToGCJ02 error: %{public}s', JSON.stringify(e));
      return { latitude: lat, longitude: lng };
    }
  }

  /** 移动地图相机到指定 WGS84 坐标（自动转换为 GCJ02） */
  private async moveCameraTo(lat: number, lng: number, zoom: number): Promise<void> {
    if (!this.mapController) {
      return;
    }
    try {
      const gcj02 = await this.convertToGCJ02(lat, lng);
      const cameraPosition: mapCommon.CameraPosition = {
        target: gcj02,
        zoom: zoom,
        tilt: 0,
        bearing: 0
      };
      const cameraUpdate: map.CameraUpdate = map.newCameraPosition(cameraPosition);
      this.mapController.moveCamera(cameraUpdate);
    } catch (e) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'moveCameraTo error: %{public}s', JSON.stringify(e));
    }
  }

  /** 获取当前位置并移动地图 */
  private moveToCurrentLocation(): void {
    const request: geoLocationManager.SingleLocationRequest = {
      locatingPriority: geoLocationManager.LocatingPriority.PRIORITY_ACCURACY,
      locatingTimeoutMs: 10000
    };
    geoLocationManager.getCurrentLocation(request).then(async (location: geoLocationManager.Location) => {
      this.mapCenterLat = location.latitude;
      this.mapCenterLng = location.longitude;
      this.currentAltitude = Math.round(location.altitude);
      this.lastLat = location.latitude;
      this.lastLng = location.longitude;

      // 转换坐标并移动地图相机到当前位置
      await this.moveCameraTo(location.latitude, location.longitude, 16);

      // 在地图上显示当前位置标记
      if (this.mapController) {
        try {
          this.mapController.setMyLocationEnabled(true);
          this.mapController.setMyLocation(location);
        } catch (e) {
          hilog.info(LOG_DOMAIN, LOG_TAG, 'setMyLocation: %{public}s', JSON.stringify(e));
        }
      }
    }).catch((e: Error) => {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'getCurrentLocation fail: %{public}s', JSON.stringify(e));
    });
  }

  // 上次有效定位的时间戳，用于速度过滤
  private lastLocationTime: number = 0;

  /** 开始持续定位记录 */
  private startLocationTracking(): void {
    try {
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
      const accuracy = location.accuracy || 0;
      const now = Date.now();

      // ① GPS 精度过滤：精度 > 30m 说明信号差，丢弃
      if (accuracy > 30) {
        hilog.info(LOG_DOMAIN, LOG_TAG, 'Skip low accuracy point: %{public}f m', accuracy);
        return;
      }

      if (this.lastLat !== 0) {
        const dist = TrackModel.calculateDistance(this.lastLat, this.lastLng, lat, lng);

        // ② 距离阈值过滤：至少移动 5 米才记录（避免 GPS 漂移累加）
        if (dist < 5) {
          return;
        }

        // ③ 速度过滤：两点间速度超过 150km/h 视为 GPS 跳点，丢弃
        const timeDiffSec = (now - this.lastLocationTime) / 1000;
        if (timeDiffSec > 0) {
          const speedKmh = (dist / timeDiffSec) * 3.6;
          if (speedKmh > 150) {
            hilog.info(LOG_DOMAIN, LOG_TAG, 'Skip GPS jump: dist=%{public}f speed=%{public}f km/h', dist, speedKmh);
            return;
          }
        }

        this.totalDistance += dist;
      }

      this.lastLat = lat;
      this.lastLng = lng;
      this.lastLocationTime = now;
      this.currentAltitude = alt;
      if (alt > this.maxAltitude) {
        this.maxAltitude = alt;
      }

      // 记录轨迹点
      this.recordPoints.push({ latitude: lat, longitude: lng });
      const point: TrackModel.TrackPointItem = {
        pointId: this.trackId + '_pt_' + now.toString(),
        latitude: lat,
        longitude: lng,
        altitude: alt,
        accuracy: accuracy,
        timestamp: now,
        syncStatus: 'pending'
      };
      this.allTrackPoints.push(point);

      // 更新地图折线
      this.updatePolyline();
    });
    } catch (e) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'startLocationTracking: %{public}s', JSON.stringify(e));
    }
  }

  private stopLocationTracking(): void {
    try {
      geoLocationManager.off('locationChange');
    } catch (e) {
      hilog.info(LOG_DOMAIN, LOG_TAG, 'off locationChange: %{public}s', JSON.stringify(e));
    }
  }

  /** 截取地图当前视图作为轨迹封面图（先适配轨迹范围并放大，再截图） */
  private async captureMapCover(context: common.Context): Promise<string> {
    if (!this.mapController) {
      return '';
    }
    try {
      // 先将相机适配到轨迹范围并额外放大 2 级，让轨迹在截图中更突出
      if (this.recordPoints.length >= 2) {
        const gcj02Points: mapCommon.LatLng[] = [];
        for (let i = 0; i < this.recordPoints.length; i++) {
          const converted = await this.convertToGCJ02(
            this.recordPoints[i].latitude,
            this.recordPoints[i].longitude
          );
          gcj02Points.push(converted);
        }
        let minLat = gcj02Points[0].latitude;
        let maxLat = gcj02Points[0].latitude;
        let minLng = gcj02Points[0].longitude;
        let maxLng = gcj02Points[0].longitude;
        for (let i = 1; i < gcj02Points.length; i++) {
          const p = gcj02Points[i];
          if (p.latitude < minLat) { minLat = p.latitude; }
          if (p.latitude > maxLat) { maxLat = p.latitude; }
          if (p.longitude < minLng) { minLng = p.longitude; }
          if (p.longitude > maxLng) { maxLng = p.longitude; }
        }
        const centerLat = (minLat + maxLat) / 2;
        const centerLng = (minLng + maxLng) / 2;
        const latDiff = maxLat - minLat;
        const lngDiff = maxLng - minLng;
        const maxDiff = Math.max(latDiff, lngDiff);
        let zoom = 16;
        if (maxDiff > 0.1) { zoom = 11; }
        else if (maxDiff > 0.05) { zoom = 12; }
        else if (maxDiff > 0.02) { zoom = 13; }
        else if (maxDiff > 0.01) { zoom = 14; }
        else if (maxDiff > 0.005) { zoom = 15; }
        else if (maxDiff > 0.002) { zoom = 16; }
        else { zoom = 17; }
        // 再额外放大 1 级
        zoom = Math.min(zoom + 1, 20);
        this.mapController.moveCamera(map.newCameraPosition({
          target: { latitude: centerLat, longitude: centerLng },
          zoom: zoom,
          tilt: 0,
          bearing: 0
        }));
        // 等待地图渲染
        await new Promise<void>((resolve: Function) => {
          setTimeout(() => { resolve(); }, 600);
        });
      }
      const pixelMap: image.PixelMap = await this.mapController.snapshot();
      // 保存为本地文件
      const dir = context.filesDir;
      const fileName = 'cover_' + this.trackId + '.jpg';
      const filePath = dir + '/' + fileName;
      const packer = image.createImagePacker();
      const packOpts: image.PackingOption = { format: 'image/jpeg', quality: 80 };
      const data: ArrayBuffer = await packer.packToData(pixelMap, packOpts);
      const file = fileIo.openSync(filePath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY);
      fileIo.writeSync(file.fd, data);
      fileIo.closeSync(file.fd);
      packer.release();
      pixelMap.release();
      hilog.info(LOG_DOMAIN, LOG_TAG, 'Map cover saved: %{public}s', filePath);
      return filePath;
    } catch (e) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'captureMapCover: %{public}s', JSON.stringify(e));
      return '';
    }
  }

  /** 更新地图上的轨迹折线（WGS84 → GCJ02 转换后绘制） */
  private async updatePolyline(): Promise<void> {
    if (!this.mapController || this.recordPoints.length < 2) {
      return;
    }
    try {
      if (this.currentPolyline) {
        await this.currentPolyline.remove();
      }
      // 将 WGS84 轨迹点转换为 GCJ02
      const gcj02Points: mapCommon.LatLng[] = [];
      for (let i = 0; i < this.recordPoints.length; i++) {
        const converted = await this.convertToGCJ02(
          this.recordPoints[i].latitude,
          this.recordPoints[i].longitude
        );
        gcj02Points.push(converted);
      }
      const polylineOption: mapCommon.MapPolylineOptions = {
        points: gcj02Points,
        color: 0xFF2563EB,
        width: 14,
        visible: true
      };
      this.currentPolyline = await this.mapController.addPolyline(polylineOption);
    } catch (e) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'updatePolyline: %{public}s', JSON.stringify(e));
    }
  }

  /** 计时器 */
  /** @param baseElapsedMs 已有时长（毫秒），继续记录时传入，计时从该值累加 */
  private startTimer(baseElapsedMs?: number): void {
    if (baseElapsedMs !== undefined && baseElapsedMs > 0) {
      this.recordStartTime = Date.now() - baseElapsedMs;
    } else {
      this.recordStartTime = Date.now();
    }
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

  /** 添加打卡点（尽量使用当前高精度定位，减少误差） */
  private async confirmAddSpot(): Promise<void> {
    const name = this.dialogInputText.trim() || '打卡点';
    this.showSpotDialog = false;
    this.dialogInputText = '';

    let lat = this.lastLat;
    let lng = this.lastLng;
    let alt = this.currentAltitude;
    try {
      const request: geoLocationManager.SingleLocationRequest = {
        locatingPriority: geoLocationManager.LocatingPriority.PRIORITY_ACCURACY,
        locatingTimeoutMs: 5000
      };
      const loc = await geoLocationManager.getCurrentLocation(request);
      if (loc && loc.latitude !== 0) {
        lat = loc.latitude;
        lng = loc.longitude;
        alt = Math.round(loc.altitude);
      }
    } catch (_e) {
    }

    const context = this.getUIContext().getHostContext() as common.Context;
    const spot: TrackModel.TombSpot = {
      tombId: TrackModel.generateId('tomb'),
      trackId: this.trackId,
      orderIndex: this.tombSpots.length,
      name: name,
      personInfo: '',
      remark: '',
      latitude: lat,
      longitude: lng,
      altitude: alt,
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

    // 保存轨迹统计（含打卡点数量）
    await TrackStore.updateTrack(context, this.trackId, {
      totalDistance: this.totalDistance,
      maxAltitude: this.maxAltitude,
      totalDuration: this.elapsedTime,
      spotCount: this.tombSpots.length
    });

    // 跳到打卡点详情页填写图文
    try {
      this.getUIContext().getRouter().pushUrl({
        url: 'pages/TombSpotDetail',
        params: {
          tombId: spot.tombId,
          trackId: this.trackId,
          trackTitle: this.trackTitle,
          fromRecording: true
        }
      });
    } catch (e) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'router.push TombSpotDetail: %{public}s', JSON.stringify(e));
    }
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

    // 先尝试截取地图作为封面图
    const coverPath = await this.captureMapCover(context);

    // 更新轨迹为已完成（含最终打卡点数量）
    await TrackStore.updateTrack(context, this.trackId, {
      status: TrackModel.TRACK_STATUS_DONE,
      endName: name,
      endLat: this.lastLat,
      endLng: this.lastLng,
      totalDistance: this.totalDistance,
      totalDuration: this.elapsedTime,
      maxAltitude: this.maxAltitude,
      spotCount: this.tombSpots.length,
      coverImageUrl: coverPath
    });

    // 结束轨迹后，后台同步到云端
    SyncService.syncTrack(context, this.trackId).catch((e: Error) => {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'Sync track after end: %{public}s', JSON.stringify(e));
    });

    // 跳转到轨迹详情页
    try {
      this.getUIContext().getRouter().replaceUrl({
        url: 'pages/TrackDetail',
        params: { trackId: this.trackId, title: this.trackTitle }
      });
    } catch (e) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'router.replace TrackDetail: %{public}s', JSON.stringify(e));
    }
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
      maxAltitude: this.maxAltitude,
      spotCount: this.tombSpots.length
    });

    this.getUIContext().getRouter().back();
  }

  onPageShow(): void {
    // 从打卡点详情返回后刷新打卡点列表
    const context = this.getUIContext().getHostContext() as common.Context;
    TrackStore.getTombSpotsByTrackId(context, this.trackId).then((spots: TrackModel.TombSpot[]) => {
      this.tombSpots = spots;
    });
    if (this.mapController) {
      this.mapController.show();
      // 恢复后重新绘制已有轨迹
      if (this.recordPoints.length >= 2) {
        this.updatePolyline();
      }
    }
  }

  onPageHide(): void {
    if (this.mapController) {
      this.mapController.hide();
    }
  }

  build() {
    Stack() {
    Column() {
      // 地图区域（占据底部面板以上的全部空间）
      Stack() {
        MapComponent({
          mapOptions: this.mapOptions,
          mapCallback: this.mapCallback
        })
          .width('100%')
          .height('100%');

        // 返回按钮（左上角，考虑状态栏高度）
        Row() {
          Button() {
            Image($r('app.media.icon_back'))
              .width(14)
              .height(14)
              .objectFit(ImageFit.Contain)
              .fillColor($r('app.color.primary'))
          }
          .width(40)
          .height(40)
          .backgroundColor($r('app.color.card_background'))
          .borderRadius(12)
          .shadow({ radius: 8, color: $r('app.color.shadow_large'), offsetX: 0, offsetY: 2 })
          .onClick(() => {
            if (this.isRecording) {
              this.showInterruptDialog = true;
            } else {
              this.getUIContext().getRouter().back();
            }
          });
        }
        .position({ x: 12, y: 12 + this.statusBarHeight })
        .zIndex(10);

        // 地图控制按钮（右上角，仅保留图层切换与 2D/3D；定位使用地图右下角系统按钮）
        Column({ space: 10 }) {
          // 图层切换（图标+文字，便于识别）
          Button() {
            Row({ space: 4 }) {
              Image($r('app.media.ic_globe'))
                .width(16)
                .height(16)
                .fillColor(this.showLayerPanel ? Color.White : $r('app.color.label_primary'));
              Text($r('app.string.record_layer'))
                .fontSize(12)
                .fontColor(this.showLayerPanel ? Color.White : $r('app.color.label_primary'));
            }
          }
          .width(56)
          .height(40)
          .backgroundColor(this.showLayerPanel ? $r('app.color.primary') : $r('app.color.card_background'))
          .borderRadius(12)
          .shadow({ radius: 8, color: $r('app.color.shadow_large'), offsetX: 0, offsetY: 2 })
          .onClick(() => {
            this.showLayerPanel = !this.showLayerPanel;
          });

          // 3D 模式切换
          Button() {
            Text(this.is3DMode ? '3D' : '2D')
              .fontSize(13)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.is3DMode ? Color.White : $r('app.color.label_primary'));
          }
          .width(40)
          .height(40)
          .backgroundColor(this.is3DMode ? $r('app.color.primary') : $r('app.color.card_background'))
          .borderRadius(12)
          .shadow({ radius: 8, color: $r('app.color.shadow_large'), offsetX: 0, offsetY: 2 })
          .onClick(async () => {
            this.is3DMode = !this.is3DMode;
            if (this.mapController) {
              try {
                const tilt = this.is3DMode ? 45 : 0;
                const lat = this.lastLat !== 0 ? this.lastLat : this.mapCenterLat;
                const lng = this.lastLng !== 0 ? this.lastLng : this.mapCenterLng;
                const gcj02 = await this.convertToGCJ02(lat, lng);
                const cameraPosition: mapCommon.CameraPosition = {
                  target: gcj02,
                  zoom: 16,
                  tilt: tilt,
                  bearing: 0
                };
                const cameraUpdate: map.CameraUpdate = map.newCameraPosition(cameraPosition);
                this.mapController.moveCamera(cameraUpdate);
              } catch (e) {
                hilog.error(LOG_DOMAIN, LOG_TAG, 'moveCamera tilt error: %{public}s', JSON.stringify(e));
              }
            }
          });
        }
        .position({ x: '100%', y: 12 + this.statusBarHeight })
        .translate({ x: -60 })
        .zIndex(10);

        // 图层选择面板
        if (this.showLayerPanel) {
          Column() {
            Row({ space: 12 }) {
              this.LayerOption($r('app.string.map_type_standard'), $r('app.color.primary'), 1);
              this.LayerOption($r('app.string.map_type_satellite'), $r('app.color.success'), 2);
              this.LayerOption($r('app.string.map_type_terrain'), $r('app.color.warning'), 3);
            }
            .padding(16)
            .backgroundColor($r('app.color.card_background'))
            .borderRadius(12)
            .shadow({ radius: 12, color: $r('app.color.shadow_large'), offsetX: 0, offsetY: 4 });
          }
          .position({ x: '100%', y: 160 + this.statusBarHeight })
          .translate({ x: -220 })
          .zIndex(15);
        }
      }
      .width('100%')
      .layoutWeight(1);

      // 底部录制面板（固定在底部）
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
            Text($r('app.string.record_distance'))
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
            Text($r('app.string.record_duration'))
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
            Text($r('app.string.record_altitude'))
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
            Image($r('app.media.ic_location_pin'))
              .width(16)
              .height(16)
              .fillColor($r('app.color.primary'));
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
            Image($r('app.media.ic_arrow_right'))
              .width(14)
              .height(14)
              .fillColor($r('app.color.label_tertiary'));
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
                Image($r('app.media.ic_location_pin'))
                  .width(22)
                  .height(22)
                  .fillColor($r('app.color.primary'));
                Text($r('app.string.record_spot'))
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
              Image(this.isPaused ? $r('app.media.ic_play') : $r('app.media.ic_pause'))
                .width(28)
                .height(28)
                .fillColor(Color.White);
            }
            .width(64)
            .height(64)
            .backgroundColor($r('app.color.accent'))
            .borderRadius(32)
            .shadow({ radius: 12, color: $r('app.color.accent_alpha'), offsetX: 0, offsetY: 4 })
            .onClick(() => {
              this.togglePause();
            });

            // 终点按钮
            Button() {
              Column({ space: 4 }) {
                Image($r('app.media.ic_stop'))
                  .width(22)
                  .height(22)
                  .fillColor(Color.White);
                Text($r('app.string.record_end'))
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
      .padding({ left: 20, right: 20, top: 16, bottom: 16 + this.bottomSafeHeight })
      .backgroundColor($r('app.color.card_background'))
      .borderRadius({ topLeft: 20, topRight: 20 })
      .shadow({ radius: 16, color: $r('app.color.shadow_large'), offsetX: 0, offsetY: -4 });

    }
    .width('100%')
    .height('100%');

    // ========== 弹窗们（全屏覆盖） ==========

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
          Text($r('app.string.interrupt_title'))
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.label_primary'))
            .margin({ bottom: 8 });
          Text($r('app.string.interrupt_message'))
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
        .shadow({ radius: 24, color: $r('app.color.shadow_medium'), offsetX: 0, offsetY: 8 });
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.overlay_dark'))
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
  LayerOption(label: string | Resource, dotColor: string | Resource, mapType: number) {
    Column({ space: 6 }) {
      Column() {
        Circle({ width: 24, height: 24 })
          .fill(dotColor);
      }
      .width(52)
      .height(52)
      .borderRadius(10)
      .backgroundColor(this.currentMapType === mapType ? $r('app.color.menu_selected_bg') : $r('app.color.layer_inactive_bg'))
      .borderWidth(this.currentMapType === mapType ? 2 : 0)
      .borderColor($r('app.color.primary'))
      .justifyContent(FlexAlign.Center);
      Text(label)
        .fontSize(12)
        .fontColor(this.currentMapType === mapType ? $r('app.color.primary') : $r('app.color.label_secondary'));
    }
    .alignItems(HorizontalAlign.Center)
    .onClick(() => {
      this.currentMapType = mapType;
      this.showLayerPanel = false;
      if (this.mapController) {
        try {
          this.mapController.setMapType(mapType);
        } catch (e) {
          hilog.error(LOG_DOMAIN, LOG_TAG, 'setMapType error: %{public}s', JSON.stringify(e));
        }
      }
    });
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
      .shadow({ radius: 24, color: $r('app.color.shadow_medium'), offsetX: 0, offsetY: 8 });
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.overlay_dark'))
    .justifyContent(FlexAlign.Center)
    .zIndex(100);
  }
}
