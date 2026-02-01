
import { router } from '@kit.ArkUI';
import { MapComponent, mapCommon, map } from '@kit.MapKit';
import { AsyncCallback } from '@kit.BasicServicesKit';
import { geoLocationManager } from '@kit.LocationKit';
import { common } from '@kit.AbilityKit';
import { NavBar } from '../common/NavBar';
import { TrackStore } from '../common/TrackStore';
import { TrackModel } from '../common/TrackModel';

/**
 * P1-3 轨迹记录页：地图显示当前位置与实时轨迹线，设置起点、结束本段、结束整条轨迹。
 */
@Entry
@Component
struct TrackRecord {
  @State segmentIndex: number = 1;
  @State isRecording: boolean = false;
  @State startName: string = '';
  @State mapCenterLat: number = 30.2988;
  @State mapCenterLng: number = 120.1203;
  private trackId: string = '';
  private trackTitle: string = '';
  private mapOptions?: mapCommon.MapOptions;
  private mapCallback?: AsyncCallback<map.MapComponentController>;
  private mapController?: map.MapComponentController;
  private recordPoints: Array<mapCommon.LatLng> = [];
  private currentPolyline?: map.MapPolyline;

  aboutToAppear(): void {
    const params = router.getParams() as Record<string, string | number> | undefined;
    if (params) {
      this.trackId = (params['trackId'] as string) ?? '';
      this.trackTitle = (params['title'] as string) ?? '';
      const seg = params['segmentIndex'];
      if (seg !== undefined && seg !== null) {
        this.segmentIndex = Number(seg);
      }
    }
    this.initMap();
  }

  aboutToDisappear(): void {
    this.stopContinuousLocation();
  }

  private initMap(): void {
    this.mapOptions = {
      position: {
        target: {
          latitude: this.mapCenterLat,
          longitude: this.mapCenterLng
        },
        zoom: 15
      },
      myLocationControlsEnabled: true,
      sphereEnabled: true
    };
    this.mapCallback = async (err: Error, controller: map.MapComponentController) => {
      if (!err) {
        this.mapController = controller;
        this.moveToCurrentLocation();
      } else {
        console.error('Map init failed: ' + JSON.stringify(err));
      }
    };
  }

  /** 获取当前位置并移动地图到该位置、显示我的位置 */
  private moveToCurrentLocation(): void {
    const request: geoLocationManager.SingleLocationRequest = {
      locatingPriority: geoLocationManager.LocatingPriority.PRIORITY_ACCURACY,
      locatingTimeoutMs: 10000
    };
    geoLocationManager.getCurrentLocation(request).then((location: geoLocationManager.Location) => {
      this.mapCenterLat = location.latitude;
      this.mapCenterLng = location.longitude;
      if (this.mapController) {
        try {
          // 使用更安全的方法调用，避免类型转换
          if (this.mapController && typeof (this.mapController['setMyLocation']) === 'function') {
            this.mapController['setMyLocation'](location);
          }
          if (this.mapController && typeof (this.mapController['setMyLocationEnabled']) === 'function') {
            this.mapController['setMyLocationEnabled'](true);
          }
        } catch (e) {
          console.info('setMyLocation not available: ' + JSON.stringify(e));
        }
      }
    }).catch((e: Error) => {
      console.error('getCurrentLocation fail: ' + JSON.stringify(e));
    });
  }

  private startContinuousLocation(): void {
    const request: geoLocationManager.ContinuousLocationRequest = {
      interval: 2,
      locationScenario: geoLocationManager.UserActivityScenario.NAVIGATION
    };
    geoLocationManager.on('locationChange', request, (location: geoLocationManager.Location) => {
      const latLng: mapCommon.LatLng = { latitude: location.latitude, longitude: location.longitude };
      this.recordPoints.push(latLng);
      this.updatePolyline();
    });
  }

  private stopContinuousLocation(): void {
    try {
      geoLocationManager.off('locationChange');
    } catch (e) {
      console.info('off locationChange: ' + JSON.stringify(e));
    }
  }

  private async updatePolyline(): Promise<void> {
    if (!this.mapController || this.recordPoints.length < 2) {
      return;
    }
    try {
      if (this.currentPolyline && typeof (this.currentPolyline['remove']) === 'function') {
        this.currentPolyline['remove']();
      }
      const polylineOption: mapCommon.MapPolylineOptions = {
        points: this.recordPoints,
        color: 0xff007AFF,
        width: 12,
        visible: true
      };
      this.currentPolyline = await this.mapController.addPolyline(polylineOption);
    } catch (e) {
      console.error('addPolyline fail: ' + JSON.stringify(e));
    }
  }

  onPageShow(): void {
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
    Column() {
      NavBar({ title: this.trackTitle || '轨迹记录', showBack: true });

      Stack() {
        MapComponent({
          mapOptions: this.mapOptions,
          mapCallback: this.mapCallback
        })
          .width('100%')
          .height('100%');
      }
      .width('100%')
      .layoutWeight(1)
      .margin({ left: 16, right: 16, top: 12 })
      .borderRadius(12)
      .clip(true);

      Column({ space: 16 }) {
        Row({ space: 4 }) {
          Text(`第 ${this.segmentIndex} 段 · `)
            .fontSize(15)
            .fontColor($r('app.color.label_primary'));
          Text(this.isRecording ? '录制中' : '未开始')
            .fontSize(15)
            .fontColor($r('app.color.label_primary'));
        }
        if (this.startName) {
          Text(`起点：${this.startName}`)
            .fontSize(13)
            .fontColor($r('app.color.label_tertiary'));
        }

        Row({ space: 12 }) {
          Button(this.startName ? $r('app.string.track_record_reset_start') : $r('app.string.track_record_set_start'))
            .fontSize(15)
            .fontColor($r('app.color.primary'))
            .backgroundColor($r('app.color.card_background'))
            .layoutWeight(1)
            .height(44)
            .borderRadius(10)
            .onClick(() => {
              this.startName = this.startName || '山脚入口';
              if (!this.isRecording) {
                if (this.segmentIndex === 1) {
                  this.recordPoints = [];
                }
                this.startContinuousLocation();
              }
              this.isRecording = true;
            });

          Button($r('app.string.track_record_end_segment'))
            .fontSize(15)
            .fontColor($r('app.color.button_primary_text'))
            .backgroundColor($r('app.color.primary'))
            .layoutWeight(1)
            .height(44)
            .borderRadius(10)
            .enabled(this.isRecording)
            .opacity(this.isRecording ? 1 : 0.5)
            .onClick(() => {
              router.pushUrl({
                url: 'pages/TombSpotDetail',
                params: {
                  trackId: this.trackId,
                  title: this.trackTitle,
                  segmentIndex: this.segmentIndex,
                  endName: '墓地点'
                }
              });
            });

          Button($r('app.string.track_record_end_track'))
            .fontSize(15)
            .fontColor($r('app.color.button_primary_text'))
            .backgroundColor($r('app.color.primary'))
            .layoutWeight(1)
            .height(44)
            .borderRadius(10)
            .onClick(async () => {
              this.stopContinuousLocation();
              const context = this.getUIContext().getHostContext() as common.Context;
              const points: TrackModel.TrackPointItem[] = this.recordPoints.map((p: mapCommon.LatLng): TrackModel.TrackPointItem => ({
                latitude: p.latitude,
                longitude: p.longitude
              }));
              await TrackStore.updateTrack(context, this.trackId, {
                status: TrackModel.TRACK_STATUS_DONE,
                segmentCount: this.segmentIndex,
                trackPoints: points,
                updatedAt: Date.now()
              });
              router.replaceUrl({
                url: 'pages/TrackDetail',
                params: { trackId: this.trackId, title: this.trackTitle }
              });
            });
        }
        .width('100%');
      }
      .width('100%')
      .padding(16)
      .backgroundColor($r('app.color.card_background'))
      .margin({ left: 16, right: 16, top: 12, bottom: 24 })
      .borderRadius(12);
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.app_background'));
  }
}
