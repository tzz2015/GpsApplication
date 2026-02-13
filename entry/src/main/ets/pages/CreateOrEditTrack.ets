import { common } from '@kit.AbilityKit';
import { NavBar } from '../common/NavBar';
import { TrackStore } from '../common/TrackStore';
import { TrackModel } from '../common/TrackModel';
import { AuthStore } from '../common/AuthStore';

/**
 * P1-2 新建轨迹基础信息页
 * 填写名称和简介，保存后跳转到轨迹记录页
 */
@Entry
@Component
struct CreateOrEditTrack {
  @State title: string = '';
  @State description: string = '';
  @State isSaving: boolean = false;

  private async saveAndStartRecord(): Promise<void> {
    if (this.title.trim().length === 0 || this.isSaving) {
      return;
    }
    this.isSaving = true;

    const context = this.getUIContext().getHostContext() as common.Context;
    const user = await AuthStore.getCurrentUser(context);
    const userId = user ? user.userId : '';

    const trackId = TrackModel.generateId('track');
    const now = Date.now();
    const displayName = user ? user.displayName : '';
    const track: TrackModel.Track = {
      trackId: trackId,
      ownerUserId: userId,
      ownerDisplayName: displayName,
      title: this.title.trim(),
      description: this.description.trim(),
      visibility: TrackModel.VISIBILITY_PRIVATE,
      status: TrackModel.TRACK_STATUS_EDITING,
      startName: '',
      endName: '',
      startLat: 0,
      startLng: 0,
      endLat: 0,
      endLng: 0,
      totalDistance: 0,
      totalDuration: 0,
      maxAltitude: 0,
      spotCount: 0,
      coverImageUrl: '',
      createdAt: now,
      updatedAt: now
    };

    await TrackStore.saveTrack(context, track);

    try {
      this.getUIContext().getRouter().replaceUrl({
        url: 'pages/TrackRecord',
        params: { trackId: trackId, title: this.title.trim() }
      });
    } catch (_e) {
      console.error('CreateOrEditTrack router.replace failed: ' + JSON.stringify(_e));
    }
  }

  build() {
    Column() {
      NavBar({ title: '新建轨迹', showBack: true });

      Scroll() {
        Column() {
          // ===== 顶部引导区 =====
          Column({ space: 8 }) {
            Image($r('app.media.ic_location_pin'))
              .width(44)
              .height(44)
              .fillColor($r('app.color.primary'));
            Text('开始一段新旅程')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.label_primary'));
            Text('填写基本信息后即可开始记录轨迹')
              .fontSize(13)
              .fontColor($r('app.color.label_tertiary'));
          }
          .width('100%')
          .padding({ top: 24, bottom: 20 })
          .alignItems(HorizontalAlign.Center);

          // ===== 表单卡片 =====
          Column({ space: 20 }) {
            // 轨迹名称
            Column({ space: 8 }) {
              Row({ space: 4 }) {
                Text('轨迹名称')
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.label_primary'));
                Text('*')
                  .fontSize(14)
                  .fontColor($r('app.color.destructive'));
              }
              TextInput({ placeholder: '例如：刘氏家族清明扫墓', text: this.title })
                .onChange((value: string) => {
                  this.title = value;
                })
                .maxLength(30)
                .width('100%')
                .height(46)
                .fontSize(15)
                .backgroundColor($r('app.color.app_background'))
                .borderRadius(12)
                .padding({ left: 14, right: 14 });
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start);

            // 轨迹简介
            Column({ space: 8 }) {
              Text('轨迹简介（选填）')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.label_primary'));
              TextArea({ placeholder: '简要描述本次出行的目的、参与人员等', text: this.description })
                .onChange((value: string) => {
                  this.description = value;
                })
                .maxLength(200)
                .showCounter(true)
                .width('100%')
                .height(100)
                .fontSize(15)
                .backgroundColor($r('app.color.app_background'))
                .borderRadius(12)
                .padding(14);
              Text('简介将展示在轨迹详情页')
                .fontSize(12)
                .fontColor($r('app.color.label_tertiary'));
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start);

            // 保存按钮
            Button(this.isSaving ? '保存中…' : '保存并开始记录')
              .width('100%')
              .height(46)
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(Color.White)
              .backgroundColor($r('app.color.primary'))
              .borderRadius(23)
              .enabled(this.title.trim().length > 0 && !this.isSaving)
              .opacity(this.title.trim().length > 0 && !this.isSaving ? 1 : 0.5)
              .margin({ top: 4 })
              .onClick(() => {
                this.saveAndStartRecord();
              });
          }
          .padding(20)
          .backgroundColor($r('app.color.card_background'))
          .borderRadius(16)
          .margin({ left: 20, right: 20 })
          .shadow({ radius: 8, color: $r('app.color.shadow_light'), offsetX: 0, offsetY: 2 });

          // ===== 提示信息 =====
          Row({ space: 8 }) {
            Image($r('app.media.ic_info'))
              .width(16)
              .height(16)
              .fillColor($r('app.color.primary'));
            Text('保存后将自动进入轨迹记录页面，可随时设置起点和打卡点')
              .fontSize(12)
              .fontColor($r('app.color.label_tertiary'))
              .layoutWeight(1)
              .lineHeight(18);
          }
          .padding({ left: 12, right: 12, top: 10, bottom: 10 })
          .margin({ left: 20, right: 20, top: 16 })
          .backgroundColor($r('app.color.primary_lighter'))
          .borderRadius(10);

          // 底部留白
          Column()
            .height(40);
        }
        .width('100%');
      }
      .layoutWeight(1)
      .width('100%')
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .backgroundColor($r('app.color.app_background'));
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.app_background'));
  }
}
