import { promptAction, componentSnapshot } from '@kit.ArkUI';
import { MapComponent, mapCommon, map } from '@kit.MapKit';
import { AsyncCallback, BusinessError } from '@kit.BasicServicesKit';
import { common, abilityAccessCtrl } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { image } from '@kit.ImageKit';
import { fileIo } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
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
  @State showShareCover: boolean = false;
  @State shareImagePath: string = '';
  @State isGeneratingShare: boolean = false;
  private trackId: string = '';
  private mapCallback?: AsyncCallback<map.MapComponentController>;
  private mapController?: map.MapComponentController;
  private mapReady: boolean = false;
  private dataReady: boolean = false;
  /** 极小透明图标，替代默认 pin 让信息窗口紧贴坐标点 */
  private tinyMarkerIcon: image.PixelMap | null = null;

  aboutToAppear(): void {
    const params = this.getUIContext().getRouter().getParams() as TrackDetailParams | undefined;
    if (params) {
      this.trackId = params.trackId || '';
      this.isPublicView = params.isPublicView || false;
    }
    this.loadData();
    this.mapCallback = async (err: Error, controller: map.MapComponentController) => {
      if (!err) {
        this.mapController = controller;
        this.mapReady = true;
        // 先将地图移动到已知的起点位置（GCJ02），避免显示默认坐标
        if (this.mapCenterLat !== 23.7275 || this.mapCenterLng !== 108.3426) {
          try {
            const gcj02 = await this.convertToGCJ02(this.mapCenterLat, this.mapCenterLng);
            controller.moveCamera(map.newCameraPosition({
              target: gcj02,
              zoom: 15,
              tilt: 0,
              bearing: 0
            }));
          } catch (_e) {
            hilog.info(LOG_DOMAIN, LOG_TAG, 'init moveCamera: %{public}s', JSON.stringify(_e));
          }
        }
        // 如果数据已加载完，绘制轨迹并适配相机
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
    // 修正 spotCount（可能在记录时未正确保存）
    if (this.track && this.track.spotCount !== this.tombSpots.length) {
      this.track.spotCount = this.tombSpots.length;
      await TrackStore.updateTrack(context, this.trackId, { spotCount: this.tombSpots.length });
    }
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
    // 创建 2x2 透明图标替代默认 pin（仅创建一次）
    if (!this.tinyMarkerIcon) {
      try {
        const buf = new ArrayBuffer(16); // 2x2 RGBA，全零 = 全透明
        const opts: image.InitializationOptions = {
          size: { width: 2, height: 2 },
          pixelFormat: image.PixelMapFormat.RGBA_8888
        };
        this.tinyMarkerIcon = await image.createPixelMap(buf, opts);
      } catch (e) {
        hilog.warn(LOG_DOMAIN, LOG_TAG, 'createTinyIcon: %{public}s', JSON.stringify(e));
      }
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
          color: 0xFF2563EB,
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
            color: 0xFF2563EB,
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

    // ===== 2. 起点标记（小绿色圆点 + 标题，点击显示名称） =====
    if (this.track && this.track.startLat !== 0) {
      try {
        const startP = await this.convertToGCJ02(this.track.startLat, this.track.startLng);
        // 绘制小圆点作为视觉标记
        await this.mapController.addCircle({
          center: startP,
          radius: 8,
          fillColor: 0xFF10B981,
          strokeColor: 0xFFFFFFFF,
          strokeWidth: 3,
          visible: true
        });
        // 添加可点击标记（用于显示名称，使用极小图标替代默认 pin）
        const startMarkerOpts: mapCommon.MarkerOptions = {
          position: startP,
          title: this.track.startName || '起点',
          snippet: '起点',
          visible: true,
          clickable: true,
          anchorU: 0.5,
          anchorV: 0.5
        };
        if (this.tinyMarkerIcon) {
          startMarkerOpts.icon = this.tinyMarkerIcon;
        } else {
          startMarkerOpts.alpha = 0.01;
        }
        await this.mapController.addMarker(startMarkerOpts);
        allLatLngs.push(startP);
      } catch (e) {
        hilog.info(LOG_DOMAIN, LOG_TAG, 'addMarker start: %{public}s', JSON.stringify(e));
      }
    }

    // ===== 3. 终点标记（小红色圆点 + 标题） =====
    if (this.track && this.track.endLat !== 0 && this.track.endName.length > 0) {
      try {
        const endP = await this.convertToGCJ02(this.track.endLat, this.track.endLng);
        await this.mapController.addCircle({
          center: endP,
          radius: 8,
          fillColor: 0xFFEF4444,
          strokeColor: 0xFFFFFFFF,
          strokeWidth: 3,
          visible: true
        });
        const endMarkerOpts: mapCommon.MarkerOptions = {
          position: endP,
          title: this.track.endName || '终点',
          snippet: '终点',
          visible: true,
          clickable: true,
          anchorU: 0.5,
          anchorV: 0.5
        };
        if (this.tinyMarkerIcon) {
          endMarkerOpts.icon = this.tinyMarkerIcon;
        } else {
          endMarkerOpts.alpha = 0.01;
        }
        await this.mapController.addMarker(endMarkerOpts);
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

  /** 在地图上标记所有打卡点（蓝色圆点 + 可点击标记显示名称） */
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
      // 黄色/琥珀色圆点作为视觉标记（打卡点，符合原型）
      try {
        await this.mapController.addCircle({
          center: gcj02,
          radius: 6,
          fillColor: 0xFFF59E0B,
          strokeColor: 0xFFFFFFFF,
          strokeWidth: 3,
          visible: true
        });
      } catch (e) {
        hilog.info(LOG_DOMAIN, LOG_TAG, 'addCircle[%{public}d]: %{public}s', i, JSON.stringify(e));
      }
      // 可点击标记（点击显示名称信息窗口）
      try {
        const spotLabel = (i + 1).toString() + '. ' + spot.name;
        const spotMarkerOpts: mapCommon.MarkerOptions = {
          position: gcj02,
          title: spotLabel,
          snippet: '海拔 ' + spot.altitude.toString() + 'm',
          visible: true,
          clickable: true,
          anchorU: 0.5,
          anchorV: 0.5
        };
        if (this.tinyMarkerIcon) {
          spotMarkerOpts.icon = this.tinyMarkerIcon;
        } else {
          spotMarkerOpts.alpha = 0.01;
        }
        await this.mapController.addMarker(spotMarkerOpts);
      } catch (e) {
        hilog.info(LOG_DOMAIN, LOG_TAG, 'addSpotMarker[%{public}d]: %{public}s', i, JSON.stringify(e));
      }
    }

    // 注册标记点击事件，点击时显示信息窗口
    if (this.mapController) {
      try {
        this.mapController.on('markerClick', (marker: map.Marker) => {
          marker.setInfoWindowVisible(true);
          return true;
        });
      } catch (e) {
        hilog.info(LOG_DOMAIN, LOG_TAG, 'on markerClick: %{public}s', JSON.stringify(e));
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

  /** 分享轨迹：截取地图并展示包含标题/起终点/打卡点等信息的分享卡 */
  private async shareTrackAsImage(): Promise<void> {
    if (!this.mapController) {
      try {
        promptAction.showToast({ message: '请稍候，地图加载完成后重试' });
      } catch (_t) {
      }
      return;
    }

    this.isGeneratingShare = true;
    const context = this.getUIContext().getHostContext() as common.Context;
    const tempDir = context.cacheDir;
    const tempPath = tempDir + '/share_' + this.trackId + '_' + Date.now().toString() + '.jpg';
    try {
      const pixelMap: image.PixelMap = await this.mapController.snapshot();
      const packer = image.createImagePacker();
      const packOpts: image.PackingOption = { format: 'image/jpeg', quality: 90 };
      const data: ArrayBuffer = await packer.packToData(pixelMap, packOpts);
      const f = fileIo.openSync(tempPath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
      fileIo.writeSync(f.fd, data);
      fileIo.closeSync(f);
      packer.release();
      pixelMap.release();
    } catch (e) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'share snapshot: %{public}s', JSON.stringify(e));
      this.isGeneratingShare = false;
      try {
        promptAction.showToast({ message: '生成分享图失败' });
      } catch (_t) {
      }
      return;
    }

    this.isGeneratingShare = false;
    this.shareImagePath = tempPath;
    this.showShareCover = true;
  }

  /** 保存分享卡到系统图库：截取整张卡片后通过 photoAccessHelper 写入图库 */
  private async saveShareCardToGallery(): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.Context;
    let imageData: ArrayBuffer | null = null;

    // 1. 截取分享卡片
    try {
      const pixelMap: image.PixelMap = await componentSnapshot.get('shareCard');
      const packer = image.createImagePacker();
      const packOpts: image.PackingOption = { format: 'image/jpeg', quality: 95 };
      imageData = await packer.packToData(pixelMap, packOpts);
      packer.release();
      pixelMap.release();
    } catch (snapErr) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'componentSnapshot: %{public}s, fallback to map screenshot', JSON.stringify(snapErr));
      // 降级：读取地图截图数据
      try {
        const srcFile = fileIo.openSync(this.shareImagePath, fileIo.OpenMode.READ_ONLY);
        const stat = fileIo.statSync(this.shareImagePath);
        imageData = new ArrayBuffer(stat.size);
        fileIo.readSync(srcFile.fd, imageData);
        fileIo.closeSync(srcFile.fd);
      } catch (_readErr) {
        try {
          promptAction.showToast({ message: '保存失败' });
        } catch (_t) {
        }
        return;
      }
    }

    if (!imageData) {
      try {
        promptAction.showToast({ message: '保存失败' });
      } catch (_t) {
      }
      return;
    }

    // 2. 保存到系统图库
    try {
      const helper = photoAccessHelper.getPhotoAccessHelper(context);
      const assetUri: string = await helper.createAsset(photoAccessHelper.PhotoType.IMAGE, 'jpg');
      const file = fileIo.openSync(assetUri, fileIo.OpenMode.READ_WRITE);
      fileIo.writeSync(file.fd, imageData);
      fileIo.closeSync(file.fd);
      try {
        promptAction.showToast({ message: '已保存到图库' });
      } catch (_t) {
      }
      hilog.info(LOG_DOMAIN, LOG_TAG, 'Share card saved to gallery: %{public}s', assetUri);
    } catch (e) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'saveToGallery: %{public}s', JSON.stringify(e));
      try {
        promptAction.showToast({ message: '保存到图库失败，请检查存储权限' });
      } catch (_t) {
      }
    }

    // 3. 清理临时文件并关闭预览
    try {
      fileIo.unlinkSync(this.shareImagePath);
    } catch (_e) {
    }
    this.showShareCover = false;
    this.shareImagePath = '';
  }

  /** 分享图预览浮层：展示完整分享卡（标题 + 地图 + 起点/打卡点/终点 + 统计），可保存或取消 */
  @Builder
  shareImageCover(): void {
    Column() {
      // 顶部留空（安全区域间距）
      Row()
        .width('100%')
        .height(48);

      Scroll() {
        // 包裹容器，用 padding 留出左右间距
        Column() {
        // ===== 分享卡片 =====
        Column() {
          // 标题
          Text(this.track ? this.track.title : '轨迹分享')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.label_primary'))
            .width('100%')
            .textAlign(TextAlign.Center)
            .padding({ top: 20, bottom: 12 });

          // 地图截图
          Image('file://' + this.shareImagePath)
            .width('100%')
            .height(260)
            .objectFit(ImageFit.Cover)
            .borderRadius(8)
            .padding({ left: 16, right: 16 });

          // 统计数据
          if (this.track) {
            Row() {
              Column({ space: 2 }) {
                Text(TrackModel.formatDistance(this.track.totalDistance))
                  .fontSize(16)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.primary'));
                Text($r('app.string.stat_distance'))
                  .fontSize(11)
                  .fontColor($r('app.color.label_tertiary'));
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Center);

              Column({ space: 2 }) {
                Text(TrackModel.formatDuration(this.track.totalDuration || 0))
                  .fontSize(16)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.primary'));
                Text($r('app.string.stat_duration'))
                  .fontSize(11)
                  .fontColor($r('app.color.label_tertiary'));
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Center);

              Column({ space: 2 }) {
                Text(this.tombSpots.length.toString())
                  .fontSize(16)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.primary'));
                Text($r('app.string.stat_spots'))
                  .fontSize(11)
                  .fontColor($r('app.color.label_tertiary'));
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Center);
            }
            .width('100%')
            .padding({ top: 16, bottom: 12, left: 16, right: 16 });
          }

          // 起点 / 打卡点 / 终点（横向标签流式布局，节省空间）
          Flex({ wrap: FlexWrap.Wrap }) {
            if (this.track && this.track.startName.length > 0) {
              Row({ space: 4 }) {
                Circle({ width: 8, height: 8 }).fill($r('app.color.success'));
                Text(this.track.startName)
                  .fontSize(12)
                  .fontColor($r('app.color.label_primary'));
              }
              .padding({ left: 8, right: 10, top: 4, bottom: 4 })
              .backgroundColor($r('app.color.spot_start_bg'))
              .borderRadius(12)
              .alignItems(VerticalAlign.Center)
              .margin({ right: 6, bottom: 6 });
            }
            ForEach(this.tombSpots, (spot: TrackModel.TombSpot, idx: number) => {
              Row({ space: 4 }) {
                Circle({ width: 8, height: 8 }).fill($r('app.color.primary'));
                Text(spot.name)
                  .fontSize(12)
                  .fontColor($r('app.color.label_primary'));
              }
              .padding({ left: 8, right: 10, top: 4, bottom: 4 })
              .backgroundColor($r('app.color.spot_checkpoint_bg'))
              .borderRadius(12)
              .alignItems(VerticalAlign.Center)
              .margin({ right: 6, bottom: 6 });
            }, (spot: TrackModel.TombSpot) => spot.tombId + '_' + spot.name);
            if (this.track && this.track.endName.length > 0) {
              Row({ space: 4 }) {
                Circle({ width: 8, height: 8 }).fill($r('app.color.destructive'));
                Text(this.track.endName)
                  .fontSize(12)
                  .fontColor($r('app.color.label_primary'));
              }
              .padding({ left: 8, right: 10, top: 4, bottom: 4 })
              .backgroundColor($r('app.color.spot_end_bg'))
              .borderRadius(12)
              .alignItems(VerticalAlign.Center)
              .margin({ right: 6, bottom: 6 });
            }
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 4, bottom: 12 });

          // 品牌标注
          Text($r('app.string.brand_tag'))
            .fontSize(11)
            .fontColor($r('app.color.label_tertiary'))
            .width('100%')
            .textAlign(TextAlign.Center)
            .padding({ bottom: 16 });
        }
        .width('100%')
        .backgroundColor(Color.White)
        .borderRadius(16)
        .id('shareCard');
        }
        .width('100%')
        .padding({ left: 20, right: 20 });
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .width('100%');

      // 底部按钮
      Row({ space: 16 }) {
        Button($r('app.string.dialog_cancel'))
          .layoutWeight(1)
          .height(50)
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.label_primary'))
          .backgroundColor($r('app.color.card_background'))
          .borderRadius(25)
          .onClick(() => {
            try {
              fileIo.unlinkSync(this.shareImagePath);
            } catch (_e) {
            }
            this.showShareCover = false;
            this.shareImagePath = '';
          });
        Column() {
          SaveButton({ icon: SaveIconStyle.FULL_FILLED, text: SaveDescription.SAVE_IMAGE, buttonType: ButtonType.Capsule })
            .fontSize(17)
            .fontColor(Color.White)
            .iconColor(Color.White)
            .backgroundColor($r('app.color.primary'))
            .borderRadius(25)
            .padding({ left: 20, right: 20, top: 14, bottom: 14 })
            .onClick((event: ClickEvent, result: SaveButtonOnClickResult) => {
              if (result === SaveButtonOnClickResult.SUCCESS) {
                this.saveShareCardToGallery();
              } else {
                try {
                  promptAction.showToast({ message: '保存授权失败' });
                } catch (_t) {
                }
              }
            });
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center);
      }
      .width('100%')
      .padding({ left: 20, right: 20, bottom: 32, top: 16 })
      .backgroundColor($r('app.color.overlay_dark_modal'));
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.overlay_dark_modal'));
  }

  /** 删除轨迹 */
  private showDeleteConfirm(): void {
    this.getUIContext().getPromptAction().showDialog({
      message: '确定删除这条轨迹？删除后无法恢复。',
      buttons: [
        { text: $r('app.string.dialog_cancel'), color: $r('app.color.dialog_secondary_text') },
        { text: $r('app.string.dialog_confirm_delete'), color: $r('app.color.destructive') }
      ]
    }).then((result: promptAction.ShowDialogSuccessResponse) => {
      if (result.index === 1) {
        const context = this.getUIContext().getHostContext() as common.Context;
        TrackStore.deleteTrack(context, this.trackId).then(async () => {
          SyncService.deleteCloudTrack(this.trackId).catch((e: Error) => {
            hilog.warn(0x0000, 'TrackDetail', 'Delete cloud track: %{public}s', JSON.stringify(e));
          });
          this.getUIContext().getRouter().back();
        });
      }
    }).catch(() => {});
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
          .height(300)
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
                  Image($r('app.media.ic_edit'))
                    .width(18)
                    .height(18)
                    .fillColor($r('app.color.primary'))
                    .onClick(() => {
                      this.editInputText = this.track ? this.track.title : '';
                      this.showEditTitleDialog = true;
                    });
                }
                if (this.isEditing) {
                  Text($r('app.string.status_editing'))
                    .fontSize(11)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.warning'))
                    .backgroundColor($r('app.color.warning_light'))
                    .padding({ left: 8, right: 8, top: 2, bottom: 2 })
                    .borderRadius(10);
                } else {
                  Text($r('app.string.status_done'))
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
                Image($r('app.media.ic_warning'))
                  .width(20)
                  .height(20)
                  .fillColor($r('app.color.warning'));
                Column({ space: 2 }) {
                  Text($r('app.string.track_not_finished'))
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.warning_text'));
                  Text($r('app.string.track_not_finished_hint'))
                    .fontSize(12)
                    .fontColor($r('app.color.warning_text'));
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
                  Image($r('app.media.ic_lock'))
                    .width(20)
                    .height(20)
                    .fillColor($r('app.color.primary'));
                  Column({ space: 2 }) {
                    Text($r('app.string.visibility_label'))
                      .fontSize(14)
                      .fontWeight(FontWeight.Medium)
                      .fontColor($r('app.color.label_primary'));
                    Text($r('app.string.visibility_hint'))
                      .fontSize(12)
                      .fontColor($r('app.color.label_tertiary'));
                  }
                }
                .layoutWeight(1);

                Row() {
                  Text($r('app.string.visibility_private'))
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
                  Text($r('app.string.visibility_public'))
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
              .shadow({ radius: 4, color: $r('app.color.shadow_light'), offsetX: 0, offsetY: 1 });
            }

            // 路线详情（打卡点时间轴）
            Column() {
              Text($r('app.string.route_detail_with_icon'))
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.label_primary'))
                .margin({ bottom: 12 })
                .width('100%');

              // 起点
              if (this.track && this.track.startName.length > 0) {
                this.TimelineItem(this.track.startName, '起点',
                  TrackModel.formatDate(this.track.createdAt), true, false, '', false);
              }

              // 打卡点（key 包含 name+updatedAt 确保编辑后 ForEach 能重新渲染）
              ForEach(this.tombSpots, (spot: TrackModel.TombSpot, index: number) => {
                this.TimelineItem(
                  (index + 1).toString() + ' ' + spot.name,
                  '',
                  TrackModel.formatDate(spot.createdAt) + ' · 海拔 ' + spot.altitude.toString() + 'm',
                  false, false, spot.tombId, this.isOwner && !this.isPublicView
                );
              }, (spot: TrackModel.TombSpot) => spot.tombId + '_' + spot.name + '_' + spot.updatedAt.toString());

              // 终点或等待
              if (this.isEditing) {
                Row() {
                  Text($r('app.string.wait_continue_record'))
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
                this.TimelineItem(this.track.endName, '终点',
                  '', false, true, '', false);
              }
            }
            .width('100%')
            .padding(16)
            .margin({ top: 8 });

            // 底部操作
            Column({ space: 8 }) {
              if (this.isEditing) {
                Button('继续记录')
                  .width('100%')
                  .height(50)
                  .fontSize(17)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(Color.White)
                  .backgroundColor($r('app.color.accent'))
                  .borderRadius(25)
                  .onClick(() => {
                    this.getUIContext().getRouter().pushUrl({
                      url: 'pages/TrackRecord',
                      params: { trackId: this.trackId, title: this.track ? this.track.title : '' }
                    });
                  });
              } else {
                Button(this.isGeneratingShare ? '生成中…' : '分享轨迹')
                  .width('100%')
                  .height(50)
                  .fontSize(17)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(Color.White)
                  .backgroundColor($r('app.color.primary'))
                  .borderRadius(25)
                  .enabled(!this.isGeneratingShare)
                  .onClick(() => {
                    this.shareTrackAsImage();
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
          Text($r('app.string.edit_track_name'))
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
            Button($r('app.string.track_detail_save'))
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
        .shadow({ radius: 24, color: $r('app.color.shadow_medium'), offsetX: 0, offsetY: 8 });
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.overlay_dark'))
      .justifyContent(FlexAlign.Center)
      .zIndex(100);
    }

    // 编辑打卡点名称弹窗
    if (this.showEditSpotNameDialog) {
      Column() {
        Column() {
          Text($r('app.string.edit_spot_name'))
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
            Button($r('app.string.track_detail_save'))
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
        .shadow({ radius: 24, color: $r('app.color.shadow_medium'), offsetX: 0, offsetY: 8 });
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.overlay_dark'))
      .justifyContent(FlexAlign.Center)
      .zIndex(100);
    }

    // 生成分享图 Loading 遮罩
    if (this.isGeneratingShare) {
      Column() {
        Column({ space: 12 }) {
          LoadingProgress()
            .width(40)
            .height(40)
            .color(Color.White);
          Text($r('app.string.generating_share'))
            .fontSize(14)
            .fontColor(Color.White);
        }
        .padding(24)
        .backgroundColor($r('app.color.overlay_dark_strong'))
        .borderRadius(16);
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .zIndex(200);
    }
    }
    .width('100%')
    .height('100%')
    .bindContentCover(this.showShareCover, this.shareImageCover());
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
    Row({ space: 8 }) {
      // 时间轴图标
      Column() {
        if (isStart) {
          Image($r('app.media.ic_seedling'))
            .width(16)
            .height(16)
            .fillColor($r('app.color.success'));
        } else if (isEnd) {
          Image($r('app.media.ic_flag_finish'))
            .width(16)
            .height(16)
            .fillColor($r('app.color.destructive'));
        } else {
          Circle({ width: 10, height: 10 })
            .fill($r('app.color.primary'));
        }
      }
      .width(16)
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
              .backgroundColor(isStart ? $r('app.color.success_light') : $r('app.color.destructive_light'))
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .borderRadius(4);
          }
          // 编辑打卡点名称图标（仅创建者）
          if (canEditName && tombId.length > 0) {
            Image($r('app.media.ic_edit'))
              .width(16)
              .height(16)
              .fillColor($r('app.color.primary'))
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
      .padding(8)
      .backgroundColor($r('app.color.card_background'))
      .borderRadius(10)
      .shadow({ radius: 2, color: $r('app.color.shadow_light'), offsetX: 0, offsetY: 1 })
      .onClick(() => {
        if (tombId.length > 0) {
          this.getUIContext().getRouter().pushUrl({
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
    .margin({ bottom: 8, left: 8 });
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
