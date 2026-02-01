
import { router } from '@kit.ArkUI';
import { MapComponent, mapCommon, map } from '@kit.MapKit';
import { AsyncCallback } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { NavBar } from '../common/NavBar';
import { TrackStore } from '../common/TrackStore';
import { TrackModel } from '../common/TrackModel';

/**
 * P1-4 轨迹详情页：地图展示轨迹线，分段列表，分享/删除。
 */
@Entry
@Component
struct TrackDetail {
  @State trackTitle: string = '轨迹详情';
  @State track: TrackModel.Track | null = null;
  @State mapCenterLat: number = 30.2988;
  @State mapCenterLng: number = 120.1203;
  private trackId: string = '';
  private readOnly: boolean = false;
  private mapCallback?: AsyncCallback<map.MapComponentController>;
  private mapController?: map.MapComponentController;

  aboutToAppear(): void {
    const params = router.getParams() as Record<string, string | boolean> | undefined;
    if (params) {
      this.trackId = (params['trackId'] as string) ?? '';
      this.trackTitle = (params['title'] as string) ?? this.trackTitle;
      this.readOnly = (params['readOnly'] as boolean) ?? false;
    }
    this.loadTrack();
    this.mapCallback = async (err: Error, controller: map.MapComponentController) => {
      if (!err) {
        this.mapController = controller;
        this.drawPolylineIfNeeded();
      }
    };
  }

  private async loadTrack(): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.Context;
    const t = await TrackStore.getTrackById(context, this.trackId);
    this.track = t;
    if (t?.trackPoints?.[0]) {
      this.mapCenterLat = t.trackPoints[0].latitude;
      this.mapCenterLng = t.trackPoints[0].longitude;
    }
  }

  private async drawPolylineIfNeeded(): Promise<void> {
    if (!this.mapController || !this.track?.trackPoints || this.track.trackPoints.length < 2) {
      return;
    }
    try {
      const points: mapCommon.LatLng[] = this.track.trackPoints.map((p: TrackModel.TrackPointItem): mapCommon.LatLng => ({
        latitude: p.latitude,
        longitude: p.longitude
      }));
      const polylineOption: mapCommon.MapPolylineOptions = {
        points: points,
        color: 0xff007AFF,
        width: 12,
        visible: true
      };
      await this.mapController.addPolyline(polylineOption);
    } catch (e) {
      console.error('TrackDetail addPolyline: ' + JSON.stringify(e));
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

  showDeleteConfirm(): void {
    AlertDialog.show({
      title: '删除轨迹',
      message: '确定删除这条轨迹？删除后无法恢复。',
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: {
        value: '确定',
        fontColor: $r('app.color.destructive'),
        action: () => {
          router.back();
        }
      }
    });
  }

  build() {
    Column() {
      NavBar({ title: this.trackTitle, showBack: true });

      Scroll() {
        Column({ space: 16 }) {
          Stack() {
            MapComponent({
              mapOptions: {
                position: {
                  target: { latitude: this.mapCenterLat, longitude: this.mapCenterLng },
                  zoom: 15
                },
                myLocationControlsEnabled: false,
                sphereEnabled: true
              },
              mapCallback: this.mapCallback
            })
              .width('100%')
              .height('100%');
          }
          .width('100%')
          .height(200)
          .borderRadius(12)
          .clip(true);

          Column({ space: 0 }) {
            List() {
              ListItem() {
                Row() {
                  Text('第 1 段')
                    .fontSize(17)
                    .fontColor($r('app.color.label_primary'));
                  Blank();
                  Text('›')
                    .fontSize(20)
                    .fontColor($r('app.color.label_tertiary'));
                }
                .width('100%')
                .height(56)
                .padding({ left: 16, right: 16 })
                .onClick(() => {
                  router.pushUrl({ url: 'pages/TombSpotDetail', params: { segmentIndex: 1 } });
                });
              }
            }
            .width('100%')
            .divider({ strokeWidth: 1, color: $r('app.color.separator') })
            .scrollBar(BarState.Off);
          }
          .width('100%')
          .backgroundColor($r('app.color.card_background'))
          .borderRadius(12);
        }
        .width('100%')
        .padding(16);
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)
      .backgroundColor($r('app.color.app_background'));

      if (!this.readOnly) {
        Row({ space: 12 }) {
          Button($r('app.string.track_detail_share'))
            .fontSize(17)
            .fontColor($r('app.color.primary'))
            .backgroundColor($r('app.color.card_background'))
            .layoutWeight(1)
            .height(50)
            .borderRadius(12)
            .onClick(() => {});
          Button($r('app.string.track_detail_delete'))
            .fontSize(17)
            .fontColor($r('app.color.button_primary_text'))
            .backgroundColor($r('app.color.destructive'))
            .layoutWeight(1)
            .height(50)
            .borderRadius(12)
            .onClick(() => {
              this.showDeleteConfirm();
            });
        }
        .width('100%')
        .padding(16)
        .backgroundColor($r('app.color.app_background'));
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.app_background'));
  }
}
