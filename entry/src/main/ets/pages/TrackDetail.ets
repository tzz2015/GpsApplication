import { router } from '@kit.ArkUI';
import { MapComponent, mapCommon, map } from '@kit.MapKit';
import { AsyncCallback } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { TrackStore } from '../common/TrackStore';
import { TrackModel } from '../common/TrackModel';
import { AuthStore } from '../common/AuthStore';
import { NavBar } from '../common/NavBar';
import { SyncService } from '../common/SyncService';

const LOG_DOMAIN = 0x0000;
const LOG_TAG = 'TrackDetail';

/** 路由参数接口 */
interface TrackDetailParams {
  trackId: string;
  title: string;
  isPublicView?: boolean;
}

/**
 * P1-4 轨迹详情页
 * 已完成状态：地图 + 统计 + 可见范围 + 打卡点时间轴 + 分享/删除
 * 编辑中状态：地图 + 统计 + 未完成提示 + 打卡点时间轴 + 继续记录/删除
 */
@Entry
@Component
struct TrackDetail {
  @State track: TrackModel.Track | null = null;
  @State tombSpots: TrackModel.TombSpot[] = [];
  @State isEditing: boolean = false;
  @State isPrivate: boolean = true;
  @State isOwner: boolean = false;
  @State isPublicView: boolean = false;
  @State mapCenterLat: number = 23.7275;
  @State mapCenterLng: number = 108.3426;
  @State showEditTitleDialog: boolean = false;
  @State showEditSpotNameDialog: boolean = false;
  @State editInputText: string = '';
  @State editingSpotId: string = '';
  private trackId: string = '';
  private mapCallback?: AsyncCallback<map.MapComponentController>;
  private mapController?: map.MapComponentController;
  private mapReady: boolean = false;
  private dataReady: boolean = false;

  aboutToAppear(): void {
    const params = router.getParams() as TrackDetailParams | undefined;
    if (params) {
      this.trackId = params.trackId || '';
      this.isPublicView = params.isPublicView || false;
    }
    this.loadData();
    this.mapCallback = async (err: Error, controller: map.MapComponentController) => {
      if (!err) {
        this.mapController = controller;
        this.mapReady = true;
        // 如果数据已加载完，立即绘制轨迹
        if (this.dataReady) {
          this.moveCameraAndDraw();
        }
      }
    };
  }

  onPageShow(): void {
    this.loadData();
    if (this.mapController) {
      this.mapController.show();
      // 重新绘制轨迹和打卡点（从编辑/记录返回时可能有新数据）
      this.moveCameraAndDraw();
    }
  }

  onPageHide(): void {
    if (this.mapController) {
      this.mapController.hide();
    }
  }

  private async loadData(): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.Context;
    const t = await TrackStore.getTrackById(context, this.trackId);
    if (t) {
      this.track = t;
      this.isEditing = t.status === TrackModel.TRACK_STATUS_EDITING;
      this.isPrivate = t.visibility !== TrackModel.VISIBILITY_PUBLIC;
      if (t.startLat !== 0) {
        this.mapCenterLat = t.startLat;
        this.mapCenterLng = t.startLng;
      }
      // 判断当前用户是否为轨迹创建者
      const user = await AuthStore.getCurrentUser(context);
      if (user && t.ownerUserId === user.userId) {
        this.isOwner = true;
      }
    }
    this.tombSpots = await TrackStore.getTombSpotsByTrackId(context, this.trackId);
    this.dataReady = true;

    // 如果地图已就绪，移动相机并绘制轨迹
    if (this.mapReady) {
      this.moveCameraAndDraw();
    }
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

  /** 绘制轨迹 + 打卡点，并自动适配相机让整条轨迹居中 */
  private async moveCameraAndDraw(): Promise<void> {
    if (!this.mapController) {
      return;
    }
    await this.drawTrackOnMap();
    await this.drawSpotMarkers();
  }

  /** 绘制轨迹折线 + 起终点标记，并自动将相机适配到轨迹范围 */
  private async drawTrackOnMap(): Promise<void> {
    if (!this.mapController) {
      return;
    }
    const context = this.getUIContext().getHostContext() as common.Context;
    const points = await TrackStore.getTrackPointsByTrackId(context, this.trackId);

    hilog.info(LOG_DOMAIN, LOG_TAG, 'drawTrackOnMap start: GPS pts=%{public}d, spots=%{public}d',
      points.length, this.tombSpots.length);

    // 收集所有需要显示在地图上的坐标，用于包围盒计算
    const allLatLngs: mapCommon.LatLng[] = [];

    // ===== 1. 绘制轨迹折线 =====
    if (points.length >= 2) {
      // 方案 A：GPS 轨迹点充足，画精确折线
      const gcj02Points: mapCommon.LatLng[] = [];
      for (let i = 0; i < points.length; i++) {
        const converted = await this.convertToGCJ02(points[i].latitude, points[i].longitude);
        gcj02Points.push(converted);
        allLatLngs.push(converted);
      }
      try {
        await this.mapController.addPolyline({
          points: gcj02Points,
          color: 0xFFFF6B35,
          width: 12,
          visible: true
        });
        hilog.info(LOG_DOMAIN, LOG_TAG, 'addPolyline GPS: %{public}d points drawn', gcj02Points.length);
      } catch (e) {
        hilog.error(LOG_DOMAIN, LOG_TAG, 'addPolyline GPS error: %{public}s', JSON.stringify(e));
      }
    } else {
      // 方案 B：GPS 轨迹点不足，用 起点→打卡点→终点 的坐标连线作为回退路线
      hilog.info(LOG_DOMAIN, LOG_TAG, 'GPS pts < 2, fallback to waypoints route');
      const waypoints: mapCommon.LatLng[] = [];

      // 起点坐标
      if (this.track && this.track.startLat !== 0) {
        const p = await this.convertToGCJ02(this.track.startLat, this.track.startLng);
        waypoints.push(p);
      }
      // 打卡点坐标（按 orderIndex 排序）
      const sortedSpots: TrackModel.TombSpot[] = [];
      for (let i = 0; i < this.tombSpots.length; i++) {
        sortedSpots.push(this.tombSpots[i]);
      }
      sortedSpots.sort((a: TrackModel.TombSpot, b: TrackModel.TombSpot): number => a.orderIndex - b.orderIndex);
      for (let i = 0; i < sortedSpots.length; i++) {
        if (sortedSpots[i].latitude !== 0) {
          const p = await this.convertToGCJ02(sortedSpots[i].latitude, sortedSpots[i].longitude);
          waypoints.push(p);
        }
      }
      // 终点坐标
      if (this.track && this.track.endLat !== 0 && this.track.endName.length > 0) {
        const p = await this.convertToGCJ02(this.track.endLat, this.track.endLng);
        waypoints.push(p);
      }

      // 有至少 2 个航点才能画线
      if (waypoints.length >= 2) {
        try {
          await this.mapController.addPolyline({
            points: waypoints,
            color: 0xFFFF6B35,
            width: 10,
            visible: true
          });
          hilog.info(LOG_DOMAIN, LOG_TAG, 'addPolyline waypoints: %{public}d waypoints drawn', waypoints.length);
        } catch (e) {
          hilog.error(LOG_DOMAIN, LOG_TAG, 'addPolyline waypoints error: %{public}s', JSON.stringify(e));
        }
      }
      for (let i = 0; i < waypoints.length; i++) {
        allLatLngs.push(waypoints[i]);
      }
    }

    // ===== 2. 起点标记（始终绘制） =====
    if (this.track && this.track.startLat !== 0) {
      try {
        const startP = await this.convertToGCJ02(this.track.startLat, this.track.startLng);
        await this.mapController.addMarker({
          position: startP,
          title: this.track.startName || '起点',
          visible: true
        });
        allLatLngs.push(startP);
      } catch (e) {
        hilog.info(LOG_DOMAIN, LOG_TAG, 'addMarker start: %{public}s', JSON.stringify(e));
      }
    }

    // ===== 3. 终点标记（轨迹已完成时绘制） =====
    if (this.track && this.track.endLat !== 0 && this.track.endName.length > 0) {
      try {
        const endP = await this.convertToGCJ02(this.track.endLat, this.track.endLng);
        await this.mapController.addMarker({
          position: endP,
          title: this.track.endName || '终点',
          visible: true
        });
        allLatLngs.push(endP);
      } catch (e) {
        hilog.info(LOG_DOMAIN, LOG_TAG, 'addMarker end: %{public}s', JSON.stringify(e));
      }
    }

    // ===== 4. 打卡点坐标加入包围盒 =====
    for (let i = 0; i < this.tombSpots.length; i++) {
      if (this.tombSpots[i].latitude !== 0) {
        const spotP = await this.convertToGCJ02(this.tombSpots[i].latitude, this.tombSpots[i].longitude);
        allLatLngs.push(spotP);
      }
    }

    // ===== 5. 计算包围盒并适配相机，让轨迹居中 =====
    if (allLatLngs.length > 0) {
      this.fitCameraToBounds(allLatLngs);
    } else {
      // 无任何坐标，回退到默认起点
      try {
        const gcj02 = await this.convertToGCJ02(this.mapCenterLat, this.mapCenterLng);
        const cameraPosition: mapCommon.CameraPosition = {
          target: gcj02,
          zoom: 15,
          tilt: 0,
          bearing: 0
        };
        this.mapController.moveCamera(map.newCameraPosition(cameraPosition));
      } catch (e) {
        hilog.error(LOG_DOMAIN, LOG_TAG, 'moveCamera fallback: %{public}s', JSON.stringify(e));
      }
    }

    hilog.info(LOG_DOMAIN, LOG_TAG, 'drawTrackOnMap done: GPS=%{public}d, spots=%{public}d, bounds=%{public}d',
      points.length, this.tombSpots.length, allLatLngs.length);
  }

  /** 在地图上标记所有打卡点（优先用小圆圈，回退到半透明标记） */
  private async drawSpotMarkers(): Promise<void> {
    if (!this.mapController) {
      return;
    }
    for (let i = 0; i < this.tombSpots.length; i++) {
      const spot = this.tombSpots[i];
      if (spot.latitude === 0 && spot.longitude === 0) {
        continue;
      }
      const gcj02 = await this.convertToGCJ02(spot.latitude, spot.longitude);
      let circleOk = false;
      // 优先用小圆圈标记打卡点（比默认大图钉更精致）
      try {
        await this.mapController.addCircle({
          center: gcj02,
          radius: 6,
          fillColor: 0xCC4A90D9,
          strokeColor: 0xFFFFFFFF,
          strokeWidth: 3,
          visible: true
        });
        circleOk = true;
      } catch (e) {
        hilog.info(LOG_DOMAIN, LOG_TAG, 'addCircle[%{public}d] fallback to marker: %{public}s', i, JSON.stringify(e));
      }
      // 添加标记：圆圈成功则几乎隐藏图钉（仅保留可点击标题），否则用半透明图钉
      try {
        await this.mapController.addMarker({
          position: gcj02,
          title: spot.name,
          visible: true,
          alpha: circleOk ? 0.01 : 0.7
        });
      } catch (e) {
        hilog.info(LOG_DOMAIN, LOG_TAG, 'addSpotMarker[%{public}d]: %{public}s', i, JSON.stringify(e));
      }
    }
  }

  /** 根据坐标集合计算包围盒，移动相机使所有点居中可见 */
  private fitCameraToBounds(points: mapCommon.LatLng[]): void {
    if (!this.mapController || points.length === 0) {
      return;
    }
    try {
      let minLat = points[0].latitude;
      let maxLat = points[0].latitude;
      let minLng = points[0].longitude;
      let maxLng = points[0].longitude;
      for (let i = 1; i < points.length; i++) {
        const p = points[i];
        if (p.latitude < minLat) {
          minLat = p.latitude;
        }
        if (p.latitude > maxLat) {
          maxLat = p.latitude;
        }
        if (p.longitude < minLng) {
          minLng = p.longitude;
        }
        if (p.longitude > maxLng) {
          maxLng = p.longitude;
        }
      }
      // 计算中心点
      const centerLat = (minLat + maxLat) / 2;
      const centerLng = (minLng + maxLng) / 2;
      // 根据范围计算合适的缩放等级
      const latDiff = maxLat - minLat;
      const lngDiff = maxLng - minLng;
      const maxDiff = Math.max(latDiff, lngDiff);
      let zoom = 16;
      if (maxDiff > 0.1) {
        zoom = 10;
      } else if (maxDiff > 0.05) {
        zoom = 11;
      } else if (maxDiff > 0.02) {
        zoom = 12;
      } else if (maxDiff > 0.01) {
        zoom = 13;
      } else if (maxDiff > 0.005) {
        zoom = 14;
      } else if (maxDiff > 0.002) {
        zoom = 15;
      } else {
        zoom = 16;
      }
      const cameraPosition: mapCommon.CameraPosition = {
        target: { latitude: centerLat, longitude: centerLng },
        zoom: zoom,
        tilt: 0,
        bearing: 0
      };
      this.mapController.moveCamera(map.newCameraPosition(cameraPosition));
    } catch (e) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'fitCameraToBounds error: %{public}s', JSON.stringify(e));
    }
  }

  /** 切换可见范围 */
  private async toggleVisibility(): Promise<void> {
    this.isPrivate = !this.isPrivate;
    const context = this.getUIContext().getHostContext() as common.Context;
    await TrackStore.updateTrack(context, this.trackId, {
      visibility: this.isPrivate ? TrackModel.VISIBILITY_PRIVATE : TrackModel.VISIBILITY_PUBLIC
    });
    // 同步可见性变更到云端
    SyncService.syncTrack(context, this.trackId).catch((e: Error) => {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'Sync visibility change: %{public}s', JSON.stringify(e));
    });
  }

  /** 删除轨迹 */
  private showDeleteConfirm(): void {
    AlertDialog.show({
      title: '删除轨迹',
      message: '确定删除这条轨迹？删除后无法恢复。',
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: {
        value: '确定删除',
        fontColor: $r('app.color.destructive'),
        action: async () => {
          const context = this.getUIContext().getHostContext() as common.Context;
          await TrackStore.deleteTrack(context, this.trackId);
          // 同时删除云端数据
          SyncService.deleteCloudTrack(this.trackId).catch((e: Error) => {
            hilog.warn(0x0000, 'TrackDetail', 'Delete cloud track: %{public}s', JSON.stringify(e));
          });
          router.back();
        }
      }
    });
  }

  build() {
    Stack() {
    Column() {
      NavBar({ title: this.track ? this.track.title : '轨迹详情', showBack: true });

      Scroll() {
        Column() {
          // 地图区域
          Stack() {
            MapComponent({
              mapOptions: {
                position: {
                  target: { latitude: this.mapCenterLat, longitude: this.mapCenterLng },
                  zoom: 15
                },
                myLocationControlsEnabled: false
              },
              mapCallback: this.mapCallback
            })
              .width('100%')
              .height('100%');
          }
          .width('100%')
          .height(200)
          .margin({ left: 16, right: 16, top: 8 })
          .borderRadius(12)
          .clip(true);

          // 轨迹信息
          if (this.track) {
            Column({ space: 8 }) {
              Row({ space: 8 }) {
                Text(this.track.title)
                  .fontSize(20)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.label_primary'))
                  .layoutWeight(1);
                // 编辑图标（仅创建者可见）
                if (this.isOwner && !this.isPublicView) {
                  Text('✏️')
                    .fontSize(16)
                    .onClick(() => {
                      this.editInputText = this.track ? this.track.title : '';
                      this.showEditTitleDialog = true;
                    });
                }
                if (this.isEditing) {
                  Text('编辑中')
                    .fontSize(11)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.warning'))
                    .backgroundColor($r('app.color.warning_light'))
                    .padding({ left: 8, right: 8, top: 2, bottom: 2 })
                    .borderRadius(10);
                } else {
                  Text('已完成')
                    .fontSize(11)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.success'))
                    .backgroundColor($r('app.color.success_light'))
                    .padding({ left: 8, right: 8, top: 2, bottom: 2 })
                    .borderRadius(10);
                }
              }
              .width('100%');

              if (this.track.description.length > 0) {
                Text(this.track.description)
                  .fontSize(13)
                  .fontColor($r('app.color.label_secondary'))
                  .lineHeight(20)
                  .width('100%');
              }

              Text(TrackModel.formatDate(this.track.createdAt))
                .fontSize(12)
                .fontColor($r('app.color.label_tertiary'));

              // 统计数据
              Row() {
                this.StatItem(TrackModel.formatDistance(this.track.totalDistance), '总里程');
                Divider().vertical(true).height(30).color($r('app.color.separator'));
                this.StatItem(TrackModel.formatDuration(this.track.totalDuration), '用时');
                Divider().vertical(true).height(30).color($r('app.color.separator'));
                this.StatItem(this.track.maxAltitude.toString() + 'm', '最高海拔');
                Divider().vertical(true).height(30).color($r('app.color.separator'));
                this.StatItem(this.tombSpots.length.toString(), '打卡点');
              }
              .width('100%')
              .padding(12)
              .backgroundColor($r('app.color.app_background'))
              .borderRadius(12)
              .margin({ top: 8 });
            }
            .width('100%')
            .padding(16)
            .backgroundColor($r('app.color.card_background'));

            // 编辑中状态提示
            if (this.isEditing) {
              Row({ space: 10 }) {
                Text('⚠')
                  .fontSize(18);
                Column({ space: 2 }) {
                  Text('轨迹尚未完成')
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .fontColor('#B45309');
                  Text('请继续记录并设置终点来完成此轨迹')
                    .fontSize(12)
                    .fontColor('#B45309');
                }
              }
              .width('100%')
              .padding(14)
              .margin({ left: 16, right: 16, top: 12 })
              .backgroundColor($r('app.color.warning_light'))
              .borderRadius(12);
            }

            // 可见范围（仅已完成状态）
            if (!this.isEditing) {
              Row() {
                Row({ space: 10 }) {
                  Text('🔒')
                    .fontSize(18);
                  Column({ space: 2 }) {
                    Text('可见范围')
                      .fontSize(14)
                      .fontWeight(FontWeight.Medium)
                      .fontColor($r('app.color.label_primary'));
                    Text('设置轨迹对其他人是否可见')
                      .fontSize(12)
                      .fontColor($r('app.color.label_tertiary'));
                  }
                }
                .layoutWeight(1);

                Row() {
                  Text('私有')
                    .fontSize(12)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(this.isPrivate ? Color.White : $r('app.color.label_tertiary'))
                    .padding({ left: 14, right: 14, top: 6, bottom: 6 })
                    .backgroundColor(this.isPrivate ? $r('app.color.primary') : Color.Transparent)
                    .borderRadius(20)
                    .onClick(() => {
                      if (!this.isPrivate) {
                        this.toggleVisibility();
                      }
                    });
                  Text('公开')
                    .fontSize(12)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(!this.isPrivate ? Color.White : $r('app.color.label_tertiary'))
                    .padding({ left: 14, right: 14, top: 6, bottom: 6 })
                    .backgroundColor(!this.isPrivate ? $r('app.color.primary') : Color.Transparent)
                    .borderRadius(20)
                    .onClick(() => {
                      if (this.isPrivate) {
                        this.toggleVisibility();
                      }
                    });
                }
                .padding(3)
                .backgroundColor($r('app.color.app_background'))
                .borderRadius(20);
              }
              .width('100%')
              .padding(14)
              .margin({ left: 16, right: 16, top: 12 })
              .backgroundColor($r('app.color.card_background'))
              .borderRadius(12)
              .shadow({ radius: 4, color: '#0D000000', offsetX: 0, offsetY: 1 });
            }

            // 路线详情（打卡点时间轴）
            Column() {
              Text('📍 路线详情')
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.label_primary'))
                .margin({ bottom: 12 })
                .width('100%');

              // 起点
              if (this.track && this.track.startName.length > 0) {
                this.TimelineItem('🌱 ' + this.track.startName, '起点',
                  TrackModel.formatDate(this.track.createdAt), true, false, '', false);
              }

              // 打卡点
              ForEach(this.tombSpots, (spot: TrackModel.TombSpot, index: number) => {
                this.TimelineItem(
                  (index + 1).toString() + ' ' + spot.name,
                  '',
                  TrackModel.formatDate(spot.createdAt) + ' · 海拔 ' + spot.altitude.toString() + 'm',
                  false, false, spot.tombId, this.isOwner && !this.isPublicView
                );
              }, (spot: TrackModel.TombSpot) => spot.tombId);

              // 终点或等待
              if (this.isEditing) {
                Row() {
                  Text('⏳ 等待继续记录...')
                    .fontSize(14)
                    .fontColor($r('app.color.label_tertiary'));
                }
                .width('100%')
                .padding(12)
                .margin({ left: 28 })
                .backgroundColor($r('app.color.app_background'))
                .borderRadius(10)
                .borderWidth(1.5)
                .borderColor($r('app.color.separator'))
                .borderStyle(BorderStyle.Dashed);
              } else if (this.track && this.track.endName.length > 0) {
                this.TimelineItem('🏁 ' + this.track.endName, '终点',
                  '', false, true, '', false);
              }
            }
            .width('100%')
            .padding(16)
            .margin({ top: 8 });

            // 底部操作
            Column({ space: 8 }) {
              if (this.isEditing) {
                Button('▶ 继续记录')
                  .width('100%')
                  .height(50)
                  .fontSize(17)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(Color.White)
                  .backgroundColor($r('app.color.accent'))
                  .borderRadius(25)
                  .onClick(() => {
                    router.pushUrl({
                      url: 'pages/TrackRecord',
                      params: { trackId: this.trackId, title: this.track ? this.track.title : '' }
                    });
                  });
              } else {
                Button('分享轨迹')
                  .width('100%')
                  .height(50)
                  .fontSize(17)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(Color.White)
                  .backgroundColor($r('app.color.primary'))
                  .borderRadius(25)
                  .onClick(() => {
                    // TODO: 分享功能
                  });
              }
              Button('删除轨迹')
                .width('100%')
                .height(44)
                .fontSize(15)
                .fontColor($r('app.color.destructive'))
                .backgroundColor(Color.Transparent)
                .borderWidth(1.5)
                .borderColor($r('app.color.destructive'))
                .borderRadius(22)
                .onClick(() => {
                  this.showDeleteConfirm();
                });
            }
            .width('100%')
            .padding({ left: 16, right: 16, bottom: 40 });
          }
        }
        .width('100%');
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .backgroundColor($r('app.color.app_background'));
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.app_background'));

    // 编辑标题弹窗
    if (this.showEditTitleDialog) {
      Column() {
        Column() {
          Text('编辑轨迹名称')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.label_primary'))
            .margin({ bottom: 16 });
          TextInput({ placeholder: '轨迹名称', text: this.editInputText })
            .onChange((value: string) => {
              this.editInputText = value;
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
              .onClick(() => {
                this.showEditTitleDialog = false;
                this.editInputText = '';
              });
            Button('保存')
              .layoutWeight(1)
              .height(44)
              .fontSize(15)
              .fontColor(Color.White)
              .backgroundColor($r('app.color.primary'))
              .borderRadius(22)
              .onClick(() => {
                this.saveEditedTitle();
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
      .zIndex(100);
    }

    // 编辑打卡点名称弹窗
    if (this.showEditSpotNameDialog) {
      Column() {
        Column() {
          Text('编辑打卡点名称')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.label_primary'))
            .margin({ bottom: 16 });
          TextInput({ placeholder: '打卡点名称', text: this.editInputText })
            .onChange((value: string) => {
              this.editInputText = value;
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
              .onClick(() => {
                this.showEditSpotNameDialog = false;
                this.editInputText = '';
                this.editingSpotId = '';
              });
            Button('保存')
              .layoutWeight(1)
              .height(44)
              .fontSize(15)
              .fontColor(Color.White)
              .backgroundColor($r('app.color.primary'))
              .borderRadius(22)
              .onClick(() => {
                this.saveEditedSpotName();
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
      .zIndex(100);
    }
    }
    .width('100%')
    .height('100%');
  }

  @Builder
  StatItem(value: string, label: string) {
    Column({ space: 4 }) {
      Text(value)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.label_primary'));
      Text(label)
        .fontSize(11)
        .fontColor($r('app.color.label_tertiary'));
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center);
  }

  @Builder
  TimelineItem(name: string, tag: string, meta: string, isStart: boolean, isEnd: boolean, tombId: string, canEditName: boolean) {
    Row({ space: 12 }) {
      // 时间轴圆点
      Column() {
        Circle({ width: 10, height: 10 })
          .fill(isStart ? $r('app.color.success') : (isEnd ? $r('app.color.destructive') : $r('app.color.primary')));
      }
      .width(10)
      .margin({ top: 4 });

      // 内容
      Column({ space: 4 }) {
        Row({ space: 6 }) {
          Text(name)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.label_primary'))
            .layoutWeight(1);
          if (tag.length > 0) {
            Text(tag)
              .fontSize(10)
              .fontWeight(FontWeight.Medium)
              .fontColor(isStart ? $r('app.color.success') : $r('app.color.destructive'))
              .backgroundColor(isStart ? $r('app.color.success_light') : '#FFE8E6')
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .borderRadius(4);
          }
          // 编辑打卡点名称图标（仅创建者）
          if (canEditName && tombId.length > 0) {
            Text('✏️')
              .fontSize(14)
              .onClick(() => {
                // 从打卡点列表中找到对应名称
                for (let i = 0; i < this.tombSpots.length; i++) {
                  if (this.tombSpots[i].tombId === tombId) {
                    this.editInputText = this.tombSpots[i].name;
                    break;
                  }
                }
                this.editingSpotId = tombId;
                this.showEditSpotNameDialog = true;
              });
          }
        }
        if (meta.length > 0) {
          Text(meta)
            .fontSize(12)
            .fontColor($r('app.color.label_tertiary'));
        }
      }
      .layoutWeight(1)
      .padding(12)
      .backgroundColor($r('app.color.card_background'))
      .borderRadius(10)
      .shadow({ radius: 2, color: '#0A000000', offsetX: 0, offsetY: 1 })
      .onClick(() => {
        if (tombId.length > 0) {
          router.pushUrl({
            url: 'pages/TombSpotDetail',
            params: {
              tombId: tombId,
              trackId: this.trackId,
              trackTitle: this.track ? this.track.title : '',
              fromRecording: false
            }
          });
        }
      });
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .margin({ bottom: 8, left: 12 });
  }

  /** 保存编辑后的标题 */
  private async saveEditedTitle(): Promise<void> {
    const newTitle = this.editInputText.trim();
    if (newTitle.length === 0 || !this.track) {
      return;
    }
    this.showEditTitleDialog = false;
    const context = this.getUIContext().getHostContext() as common.Context;
    await TrackStore.updateTrack(context, this.trackId, { title: newTitle });
    await this.loadData();
  }

  /** 保存编辑后的打卡点名称 */
  private async saveEditedSpotName(): Promise<void> {
    const newName = this.editInputText.trim();
    if (newName.length === 0 || this.editingSpotId.length === 0) {
      return;
    }
    this.showEditSpotNameDialog = false;
    const context = this.getUIContext().getHostContext() as common.Context;
    await TrackStore.updateTombSpot(context, this.editingSpotId, { name: newName });
    this.editingSpotId = '';
    await this.loadData();
  }
}
