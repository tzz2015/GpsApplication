import { router } from '@kit.ArkUI';
import { MapComponent, mapCommon, map } from '@kit.MapKit';
import { AsyncCallback } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { TrackStore } from '../common/TrackStore';
import { TrackModel } from '../common/TrackModel';
import { NavBar } from '../common/NavBar';

/** 路由参数接口 */
interface TrackDetailParams {
  trackId: string;
  title: string;
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
  @State mapCenterLat: number = 23.7275;
  @State mapCenterLng: number = 108.3426;
  private trackId: string = '';
  private mapCallback?: AsyncCallback<map.MapComponentController>;
  private mapController?: map.MapComponentController;

  aboutToAppear(): void {
    const params = router.getParams() as TrackDetailParams | undefined;
    if (params) {
      this.trackId = params.trackId || '';
    }
    this.loadData();
    this.mapCallback = async (err: Error, controller: map.MapComponentController) => {
      if (!err) {
        this.mapController = controller;
        this.drawTrackOnMap();
      }
    };
  }

  onPageShow(): void {
    this.loadData();
    if (this.mapController) {
      this.mapController.show();
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
    }
    this.tombSpots = await TrackStore.getTombSpotsByTrackId(context, this.trackId);
  }

  private async drawTrackOnMap(): Promise<void> {
    if (!this.mapController) {
      return;
    }
    const context = this.getUIContext().getHostContext() as common.Context;
    const points = await TrackStore.getTrackPointsByTrackId(context, this.trackId);
    if (points.length < 2) {
      return;
    }
    try {
      const latLngs: mapCommon.LatLng[] = points.map((p: TrackModel.TrackPointItem): mapCommon.LatLng => ({
        latitude: p.latitude,
        longitude: p.longitude
      }));
      await this.mapController.addPolyline({
        points: latLngs,
        color: 0xFFFF6B35,
        width: 12,
        visible: true
      });
    } catch (e) {
      console.error('drawTrackOnMap: ' + JSON.stringify(e));
    }
  }

  /** 切换可见范围 */
  private async toggleVisibility(): Promise<void> {
    this.isPrivate = !this.isPrivate;
    const context = this.getUIContext().getHostContext() as common.Context;
    await TrackStore.updateTrack(context, this.trackId, {
      visibility: this.isPrivate ? TrackModel.VISIBILITY_PRIVATE : TrackModel.VISIBILITY_PUBLIC
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
          router.back();
        }
      }
    });
  }

  build() {
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
                  TrackModel.formatDate(this.track.createdAt), true, false, '');
              }

              // 打卡点
              ForEach(this.tombSpots, (spot: TrackModel.TombSpot, index: number) => {
                this.TimelineItem(
                  '① '.slice(0, 0) + (index + 1).toString() + ' ' + spot.name,
                  '',
                  TrackModel.formatDate(spot.createdAt) + ' · 海拔 ' + spot.altitude.toString() + 'm',
                  false, false, spot.tombId
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
                  '', false, true, '');
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
  TimelineItem(name: string, tag: string, meta: string, isStart: boolean, isEnd: boolean, tombId: string) {
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
            .fontColor($r('app.color.label_primary'));
          if (tag.length > 0) {
            Text(tag)
              .fontSize(10)
              .fontWeight(FontWeight.Medium)
              .fontColor(isStart ? $r('app.color.success') : $r('app.color.destructive'))
              .backgroundColor(isStart ? $r('app.color.success_light') : '#FFE8E6')
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .borderRadius(4);
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
}
