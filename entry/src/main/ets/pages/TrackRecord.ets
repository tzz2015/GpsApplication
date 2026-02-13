import { MapComponent, mapCommon, map } from '@kit.MapKit';
import { AsyncCallback, BusinessError } from '@kit.BasicServicesKit';
import { geoLocationManager } from '@kit.LocationKit';
import { common, abilityAccessCtrl, wantAgent } from '@kit.AbilityKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { image } from '@kit.ImageKit';
import { fileIo } from '@kit.CoreFileKit';
import { TrackStore } from '../common/TrackStore';
import { TrackModel } from '../common/TrackModel';
import { SyncService } from '../common/SyncService';
import { Config } from '../common/Config';

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
  // 弹窗打开时预取的精确定位（消除确认时的 GPS 等待）
  private pendingDialogLat: number = 0;
  private pendingDialogLng: number = 0;
  private pendingDialogAlt: number = 0;

  // 地图
  @State mapCenterLat: number = 23.7275;
  @State mapCenterLng: number = 108.3426;
  @State showLayerPanel: boolean = false;
  @State currentMapType: mapCommon.MapType = mapCommon.MapType.STANDARD;
  @State is3DMode: boolean = false;
  private mapOptions?: mapCommon.MapOptions;
  private mapCallback?: AsyncCallback<map.MapComponentController>;
  private mapController?: map.MapComponentController;
  private currentPolyline?: map.MapPolyline;
  // 精确定位坐标（进入页面时获取）
  @State currentPreciseLat: number = 0;
  @State currentPreciseLng: number = 0;
  @State currentPreciseAlt: number = 0;
  @State isGettingLocation: boolean = false;
  // 后台定位任务
  private isBackgroundRunning: boolean = false;

  // 轨迹点
  private recordPoints: mapCommon.LatLng[] = [];
  private allTrackPoints: TrackModel.TrackPointItem[] = [];
  private lastLat: number = 0;
  private lastLng: number = 0;
  // 上一个有效运动向量（用于航向突变过滤）
  private lastVectorLat: number = 0;
  private lastVectorLng: number = 0;
  // 连续丢点计数（仅日志观测）
  private droppedAccuracyCount: number = 0;
  private droppedSpeedCount: number = 0;
  private droppedDistanceCount: number = 0;
  private droppedHeadingCount: number = 0;
  private acceptedPointCount: number = 0;

  aboutToAppear(): void {
    const params = this.getUIContext().getRouter().getParams() as TrackRecordParams | undefined;
    if (params) {
      this.trackId = params.trackId || '';
      this.trackTitle = params.title || '';
    }
    // 先检查/请求定位权限
    this.ensureLocationPermission();
    // 先尝试获取最近已知位置，快速定位地图中心
    this.getLastKnownLocation();
    // 立即开始获取精确定位（进入页面就获取，不等用户操作）
    this.getPreciseLocation();
    this.loadExistingData();
    this.initMap();
  }

  /** 检查并请求定位权限 */
  private ensureLocationPermission(): void {
    try {
      const atManager = abilityAccessCtrl.createAtManager();
      const context = this.getUIContext().getHostContext() as common.Context;
      atManager.requestPermissionsFromUser(context, [
        'ohos.permission.LOCATION',
        'ohos.permission.APPROXIMATELY_LOCATION'
      ]).then(() => {
        hilog.info(LOG_DOMAIN, LOG_TAG, 'Location permissions granted');
      }).catch((err: BusinessError) => {
        hilog.error(LOG_DOMAIN, LOG_TAG, 'Request permissions fail: %{public}s', JSON.stringify(err));
      });
    } catch (e) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'ensureLocationPermission: %{public}s', JSON.stringify(e));
    }
  }

  /** 弹窗打开时立即预取精确定位（用户输入时后台获取，确认时直接使用） */
  private prefetchDialogLocation(): void {
    // 先用已有最佳坐标作为兜底
    this.pendingDialogLat = this.lastLat !== 0 ? this.lastLat : this.mapCenterLat;
    this.pendingDialogLng = this.lastLng !== 0 ? this.lastLng : this.mapCenterLng;
    this.pendingDialogAlt = this.currentAltitude;
    const request: geoLocationManager.SingleLocationRequest = {
      locatingPriority: geoLocationManager.LocatingPriority.PRIORITY_ACCURACY,
      locatingTimeoutMs: 8000
    };
    geoLocationManager.getCurrentLocation(request).then((loc: geoLocationManager.Location) => {
      if (loc && loc.latitude !== 0) {
        this.pendingDialogLat = loc.latitude;
        this.pendingDialogLng = loc.longitude;
        this.pendingDialogAlt = Math.round(loc.altitude);
        // 同步更新当前海拔显示
        this.currentAltitude = this.pendingDialogAlt;
        hilog.info(LOG_DOMAIN, LOG_TAG,
          'Dialog prefetch location: %{public}f, %{public}f, alt=%{public}d',
          loc.latitude, loc.longitude, this.pendingDialogAlt);
      }
    }).catch((_e: Error) => {
      hilog.info(LOG_DOMAIN, LOG_TAG, 'Dialog prefetch fallback to last known');
    });
  }

  /** 进入页面立即获取精确定位坐标 */
  private getPreciseLocation(): void {
    this.isGettingLocation = true;
    const request: geoLocationManager.SingleLocationRequest = {
      locatingPriority: geoLocationManager.LocatingPriority.PRIORITY_ACCURACY,
      locatingTimeoutMs: 15000
    };
    geoLocationManager.getCurrentLocation(request).then((location: geoLocationManager.Location) => {
      this.currentPreciseLat = location.latitude;
      this.currentPreciseLng = location.longitude;
      this.currentPreciseAlt = Math.round(location.altitude);
      this.currentAltitude = this.currentPreciseAlt;
      this.mapCenterLat = location.latitude;
      this.mapCenterLng = location.longitude;
      this.lastLat = location.latitude;
      this.lastLng = location.longitude;
      this.lastLocationTime = Date.now();
      this.isGettingLocation = false;
      hilog.info(LOG_DOMAIN, LOG_TAG,
        'Precise location acquired: %{public}f, %{public}f, alt=%{public}d',
        location.latitude, location.longitude, this.currentPreciseAlt);
      // 地图已就绪则立即移动到精确位置
      if (this.mapController) {
        this.moveCameraTo(location.latitude, location.longitude, 16);
        try {
          this.mapController.setMyLocation(location);
        } catch (_e) {
          // 忽略
        }
      }
    }).catch((e: Error) => {
      this.isGettingLocation = false;
      hilog.error(LOG_DOMAIN, LOG_TAG, 'getPreciseLocation fail: %{public}s', JSON.stringify(e));
    });
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
    this.stopBackgroundTask();
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
      mapType: mapCommon.MapType.STANDARD,
      myLocationControlsEnabled: true,
      scaleControlsEnabled: true
    };
    this.mapCallback = async (err: Error, controller: map.MapComponentController) => {
      if (!err) {
        this.mapController = controller;
        hilog.info(LOG_DOMAIN, LOG_TAG, 'Map controller ready');
        // 启用我的位置图层
        try {
          controller.setMyLocationEnabled(true);
          hilog.info(LOG_DOMAIN, LOG_TAG, 'setMyLocationEnabled OK');
        } catch (e) {
          hilog.error(LOG_DOMAIN, LOG_TAG, 'setMyLocationEnabled: %{public}s', JSON.stringify(e));
        }
        // 使用枚举设置标准图层
        try {
          controller.setMapType(mapCommon.MapType.STANDARD);
          this.currentMapType = mapCommon.MapType.STANDARD;
          hilog.info(LOG_DOMAIN, LOG_TAG, 'setMapType STANDARD OK');
        } catch (e) {
          hilog.error(LOG_DOMAIN, LOG_TAG, 'setMapType error: %{public}s', JSON.stringify(e));
        }
        // 用当前已知最佳坐标立即定位地图（不再重复发起 GPS 请求）
        if (this.currentPreciseLat !== 0) {
          await this.moveCameraTo(this.currentPreciseLat, this.currentPreciseLng, 16);
        } else if (this.mapCenterLat !== 23.7275) {
          await this.moveCameraTo(this.mapCenterLat, this.mapCenterLng, 16);
        }
        // 绘制已有轨迹（若 loadExistingData 已完成）
        if (this.recordPoints.length >= 2) {
          this.updatePolyline();
        }
      } else {
        hilog.error(LOG_DOMAIN, LOG_TAG, 'Map init error: %{public}s', JSON.stringify(err));
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

  // 上次有效定位的时间戳，用于速度过滤
  private lastLocationTime: number = 0;

  /** 根据精度和运动状态，动态选择最小记录距离 */
  private selectDynamicMinDistance(accuracy: number, speedKmh: number): number {
    let base = Config.GPS_MIN_DISTANCE_POOR;
    if (accuracy <= Config.GPS_ACCURACY_STRICT) {
      base = Config.GPS_MIN_DISTANCE_STRICT;
    } else if (accuracy <= Config.GPS_ACCURACY_THRESHOLD) {
      base = Config.GPS_MIN_DISTANCE_NORMAL;
    }
    if (speedKmh <= Config.GPS_IDLE_SPEED_KMH) {
      return Math.max(base, Config.GPS_IDLE_MIN_DISTANCE);
    }
    return base;
  }

  /** 低速且短位移时，若航向突变过大，视为漂移跳点 */
  private isHeadingJump(prevVectorLat: number, prevVectorLng: number, nextVectorLat: number, nextVectorLng: number): boolean {
    const prevLen = Math.sqrt(prevVectorLat * prevVectorLat + prevVectorLng * prevVectorLng);
    const nextLen = Math.sqrt(nextVectorLat * nextVectorLat + nextVectorLng * nextVectorLng);
    if (prevLen === 0 || nextLen === 0) {
      return false;
    }
    const dot = prevVectorLat * nextVectorLat + prevVectorLng * nextVectorLng;
    let cosTheta = dot / (prevLen * nextLen);
    if (cosTheta > 1) {
      cosTheta = 1;
    }
    if (cosTheta < -1) {
      cosTheta = -1;
    }
    const angleDeg = Math.acos(cosTheta) * 180 / Math.PI;
    return angleDeg >= Config.GPS_HEADING_JUMP_DEG;
  }

  private reportDropStats(): void {
    const totalDropped = this.droppedAccuracyCount + this.droppedSpeedCount + this.droppedDistanceCount + this.droppedHeadingCount;
    const totalSeen = totalDropped + this.acceptedPointCount;
    if (totalSeen <= 0) {
      return;
    }
    if (totalSeen % 20 !== 0) {
      return;
    }
    hilog.info(
      LOG_DOMAIN,
      LOG_TAG,
      'Point filter stats: accepted=%{public}d dropped=%{public}d (acc=%{public}d speed=%{public}d dist=%{public}d heading=%{public}d)',
      this.acceptedPointCount,
      totalDropped,
      this.droppedAccuracyCount,
      this.droppedSpeedCount,
      this.droppedDistanceCount,
      this.droppedHeadingCount
    );
  }

  /** 开始持续定位记录 */
  private startLocationTracking(): void {
    // 初始化 lastLocationTime，避免速度计算异常
    if (this.lastLocationTime === 0) {
      this.lastLocationTime = Date.now();
    }
    // 启动后台定位任务
    this.startBackgroundTask();
    try {
      const request: geoLocationManager.ContinuousLocationRequest = {
        interval: Config.GPS_INTERVAL,
        locationScenario: geoLocationManager.UserActivityScenario.NAVIGATION
      };
      geoLocationManager.on('locationChange', request, (location: geoLocationManager.Location) => {
        const lat = location.latitude;
        const lng = location.longitude;
        const rawAlt: number = location.altitude;
        const alt = (!isNaN(rawAlt) && isFinite(rawAlt)) ? Math.round(rawAlt) : this.currentAltitude;
        const accuracy = location.accuracy || 0;
        const now = Date.now();

        // 始终更新海拔（不再过滤 0，因为低海拔地区 alt=0 是合法值）
        this.currentAltitude = alt;
        if (alt > this.maxAltitude) {
          this.maxAltitude = alt;
        }

        // 更新地图上的当前位置（即使暂停也显示蓝点）
        if (this.mapController) {
          try {
            this.mapController.setMyLocation(location);
          } catch (_e) {
            // 忽略
          }
        }

        // 暂停时只更新位置显示，不记录轨迹点
        if (this.isPaused) {
          return;
        }

        // 0) 基础合法性过滤
        if (lat === 0 || lng === 0 || !isFinite(lat) || !isFinite(lng) || !isFinite(accuracy)) {
          return;
        }

        // ① GPS 精度硬门槛
        if (accuracy > Config.GPS_ACCURACY_MAX) {
          this.droppedAccuracyCount += 1;
          this.reportDropStats();
          hilog.info(LOG_DOMAIN, LOG_TAG, 'Skip low accuracy point: %{public}f m', accuracy);
          return;
        }

        if (this.lastLat !== 0) {
          const dist = TrackModel.calculateDistance(this.lastLat, this.lastLng, lat, lng);
          const timeDiffSec = (now - this.lastLocationTime) / 1000;
          let speedKmh = 0;
          if (timeDiffSec > 0) {
            speedKmh = (dist / timeDiffSec) * 3.6;
          }

          // ② 高速跳点过滤（步行高精度模式）
          if (speedKmh > Config.GPS_MAX_SPEED_KMH) {
            this.droppedSpeedCount += 1;
            this.reportDropStats();
            hilog.info(LOG_DOMAIN, LOG_TAG, 'Skip high speed point: dist=%{public}f speed=%{public}f km/h', dist, speedKmh);
            return;
          }

          // ③ 动态最小距离阈值
          const minDistance = this.selectDynamicMinDistance(accuracy, speedKmh);
          if (dist < minDistance) {
            this.droppedDistanceCount += 1;
            this.reportDropStats();
            return;
          }

          // ④ 低速航向突变过滤（短距离突刺）
          if (speedKmh <= 10 && dist <= 15) {
            const nextVectorLat = lat - this.lastLat;
            const nextVectorLng = lng - this.lastLng;
            if (this.isHeadingJump(this.lastVectorLat, this.lastVectorLng, nextVectorLat, nextVectorLng)) {
              this.droppedHeadingCount += 1;
              this.reportDropStats();
              hilog.info(LOG_DOMAIN, LOG_TAG, 'Skip heading jump point');
              return;
            }
          }

          this.totalDistance += dist;
          this.lastVectorLat = lat - this.lastLat;
          this.lastVectorLng = lng - this.lastLng;
          hilog.debug(LOG_DOMAIN, LOG_TAG,
            'Track point: dist=%{public}f, total=%{public}f, acc=%{public}f',
            dist, this.totalDistance, accuracy);
        }

        this.lastLat = lat;
        this.lastLng = lng;
        this.lastLocationTime = now;

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
        this.acceptedPointCount += 1;
        this.reportDropStats();

        // 更新地图折线
        this.updatePolyline();
      });
      hilog.info(LOG_DOMAIN, LOG_TAG, 'Location tracking started');
    } catch (e) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'startLocationTracking: %{public}s', JSON.stringify(e));
    }
  }

  private stopLocationTracking(): void {
    try {
      geoLocationManager.off('locationChange');
      hilog.info(LOG_DOMAIN, LOG_TAG, 'Location tracking stopped');
    } catch (e) {
      hilog.info(LOG_DOMAIN, LOG_TAG, 'off locationChange: %{public}s', JSON.stringify(e));
    }
    this.stopBackgroundTask();
  }

  /** 启动后台长时任务（保持切后台继续定位） */
  private startBackgroundTask(): void {
    if (this.isBackgroundRunning) {
      return;
    }
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const wantAgentInfo: wantAgent.WantAgentInfo = {
        wants: [
          {
            bundleName: context.abilityInfo.bundleName,
            abilityName: context.abilityInfo.name
          }
        ],
        actionType: wantAgent.OperationType.START_ABILITY,
        requestCode: 0,
        actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      };
      wantAgent.getWantAgent(wantAgentInfo).then((agent: object) => {
        backgroundTaskManager.startBackgroundRunning(context, backgroundTaskManager.BackgroundMode.LOCATION, agent)
          .then(() => {
            this.isBackgroundRunning = true;
            hilog.info(LOG_DOMAIN, LOG_TAG, 'Background location task started');
          })
          .catch((e: BusinessError) => {
            hilog.error(LOG_DOMAIN, LOG_TAG, 'startBackgroundRunning fail: %{public}s', JSON.stringify(e));
          });
      }).catch((e: BusinessError) => {
        hilog.error(LOG_DOMAIN, LOG_TAG, 'getWantAgent fail: %{public}s', JSON.stringify(e));
      });
    } catch (e) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'startBackgroundTask: %{public}s', JSON.stringify(e));
    }
  }

  /** 停止后台长时任务 */
  private stopBackgroundTask(): void {
    if (!this.isBackgroundRunning) {
      return;
    }
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      backgroundTaskManager.stopBackgroundRunning(context).then(() => {
        this.isBackgroundRunning = false;
        hilog.info(LOG_DOMAIN, LOG_TAG, 'Background location task stopped');
      }).catch((e: BusinessError) => {
        hilog.error(LOG_DOMAIN, LOG_TAG, 'stopBackgroundRunning fail: %{public}s', JSON.stringify(e));
      });
    } catch (e) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'stopBackgroundTask: %{public}s', JSON.stringify(e));
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

  /** 设置起点（使用弹窗打开时预取的精确定位，不再阻塞等待 GPS） */
  private confirmSetStart(): void {
    const name = this.dialogInputText.trim() || '起点';
    this.showStartDialog = false;
    this.dialogInputText = '';

    // 使用弹窗打开时预取的精确坐标
    let startLat = this.pendingDialogLat;
    let startLng = this.pendingDialogLng;
    let startAlt = this.pendingDialogAlt;

    // 如果预取坐标仍为 0，退化使用已知最佳坐标
    if (startLat === 0) {
      startLat = this.currentPreciseLat !== 0 ? this.currentPreciseLat : this.mapCenterLat;
      startLng = this.currentPreciseLng !== 0 ? this.currentPreciseLng : this.mapCenterLng;
      startAlt = this.currentPreciseAlt;
    }

    hilog.info(LOG_DOMAIN, LOG_TAG,
      'Start point: %{public}f, %{public}f, alt=%{public}d', startLat, startLng, startAlt);

    this.startPointName = name;
    this.hasStartPoint = true;
    this.isRecording = true;
    this.isPaused = false;
    this.lastLat = startLat;
    this.lastLng = startLng;
    this.lastLocationTime = Date.now();
    this.lastVectorLat = 0;
    this.lastVectorLng = 0;
    this.droppedAccuracyCount = 0;
    this.droppedSpeedCount = 0;
    this.droppedDistanceCount = 0;
    this.droppedHeadingCount = 0;
    this.acceptedPointCount = 0;
    this.currentAltitude = startAlt;
    this.currentPreciseLat = startLat;
    this.currentPreciseLng = startLng;
    this.currentPreciseAlt = startAlt;

    // 后台保存起点信息（不阻塞 UI）
    const context = this.getUIContext().getHostContext() as common.Context;
    TrackStore.updateTrack(context, this.trackId, {
      startName: name,
      startLat: startLat,
      startLng: startLng
    }).catch((e: Error) => {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Save start point: %{public}s', JSON.stringify(e));
    });

    // 立即开始定位和计时
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

  /** 添加打卡点（使用预取定位，先跳转再后台保存，避免卡顿） */
  private confirmAddSpot(): void {
    const name = this.dialogInputText.trim() || '打卡点';
    this.showSpotDialog = false;
    this.dialogInputText = '';

    // 使用弹窗打开时预取的精确坐标
    const lat = this.pendingDialogLat !== 0 ? this.pendingDialogLat : this.lastLat;
    const lng = this.pendingDialogLng !== 0 ? this.pendingDialogLng : this.lastLng;
    const alt = this.pendingDialogAlt !== 0 ? this.pendingDialogAlt : this.currentAltitude;

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

    // 先更新内存状态
    this.tombSpots.push(spot);

    // 先跳转到打卡点详情页（传入名称，不等数据库写入完成）
    try {
      this.getUIContext().getRouter().pushUrl({
        url: 'pages/TombSpotDetail',
        params: {
          tombId: spot.tombId,
          trackId: this.trackId,
          trackTitle: this.trackTitle,
          fromRecording: true,
          spotName: name
        }
      });
    } catch (e) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'router.push TombSpotDetail: %{public}s', JSON.stringify(e));
    }

    // 后台异步保存数据（不阻塞导航）
    const context = this.getUIContext().getHostContext() as common.Context;
    this.saveSpotDataInBackground(context, spot);
  }

  /** 后台保存打卡点数据 */
  private async saveSpotDataInBackground(context: common.Context, spot: TrackModel.TombSpot): Promise<void> {
    try {
      await TrackStore.saveTombSpot(context, spot);
    } catch (e) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'saveTombSpot: %{public}s', JSON.stringify(e));
    }
    try {
      if (this.allTrackPoints.length > 0) {
        const pointsToSave = this.allTrackPoints.slice(0);
        this.allTrackPoints = [];
        await TrackStore.saveTrackPoints(context, this.trackId, pointsToSave);
      }
    } catch (e) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'saveTrackPoints: %{public}s', JSON.stringify(e));
    }
    try {
      await TrackStore.updateTrack(context, this.trackId, {
        totalDistance: this.totalDistance,
        maxAltitude: this.maxAltitude,
        totalDuration: this.elapsedTime,
        spotCount: this.tombSpots.length
      });
    } catch (e) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'updateTrack: %{public}s', JSON.stringify(e));
    }
  }

  /** 设置终点并结束轨迹（使用预取定位，不再阻塞等待 GPS） */
  private async confirmSetEnd(): Promise<void> {
    const name = this.dialogInputText.trim() || '终点';
    this.showEndDialog = false;
    this.dialogInputText = '';

    // 使用弹窗打开时预取的精确坐标
    let endLat = this.pendingDialogLat !== 0 ? this.pendingDialogLat : this.lastLat;
    let endLng = this.pendingDialogLng !== 0 ? this.pendingDialogLng : this.lastLng;
    hilog.info(LOG_DOMAIN, LOG_TAG,
      'End point: %{public}f, %{public}f', endLat, endLng);

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
      endLat: endLat,
      endLng: endLng,
      totalDistance: this.totalDistance,
      totalDuration: this.elapsedTime,
      maxAltitude: this.maxAltitude,
      spotCount: this.tombSpots.length,
      coverImageUrl: coverPath
    });

    // 结束轨迹后，后台同步到云端，同步完成发通知
    const uiContext = this.getUIContext();
    SyncService.syncTrack(context, this.trackId).then(() => {
      hilog.info(LOG_DOMAIN, LOG_TAG, 'Track sync completed for: %{public}s', this.trackId);
    }).catch((e: Error) => {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'Sync track after end: %{public}s', JSON.stringify(e));
    });

    // 跳转到轨迹详情页
    try {
      uiContext.getRouter().replaceUrl({
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
                const tilt: number = this.is3DMode ? 45 : 0;
                const lat: number = this.lastLat !== 0 ? this.lastLat : this.mapCenterLat;
                const lng: number = this.lastLng !== 0 ? this.lastLng : this.mapCenterLng;
                const gcj02: mapCommon.LatLng = await this.convertToGCJ02(lat, lng);
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
              this.LayerOption($r('app.string.map_type_standard'), $r('app.color.primary'), mapCommon.MapType.STANDARD);
              this.LayerOption($r('app.string.map_type_satellite'), $r('app.color.warning'), mapCommon.MapType.SATELLITE);
            }
            .padding(16)
            .backgroundColor($r('app.color.card_background'))
            .borderRadius(12)
            .shadow({ radius: 12, color: $r('app.color.shadow_large'), offsetX: 0, offsetY: 4 });
          }
          .position({ x: '100%', y: 160 + this.statusBarHeight })
          .translate({ x: -180 })
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
              this.prefetchDialogLocation();
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
              this.prefetchDialogLocation();
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
              this.prefetchDialogLocation();
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
  LayerOption(label: string | Resource, dotColor: string | Resource, mapType: mapCommon.MapType) {
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
      if (this.mapController) {
        try {
          this.mapController.setMapType(mapType);
          this.currentMapType = mapType;
          hilog.info(LOG_DOMAIN, LOG_TAG, 'Map type changed to: %{public}d', mapType);
        } catch (e) {
          hilog.error(LOG_DOMAIN, LOG_TAG, 'setMapType error: %{public}s', JSON.stringify(e));
        }
      }
      this.showLayerPanel = false;
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
