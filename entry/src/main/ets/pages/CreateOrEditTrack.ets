import { router } from '@kit.ArkUI';
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

    router.replaceUrl({
      url: 'pages/TrackRecord',
      params: { trackId: trackId, title: this.title.trim() }
    });
  }

  build() {
    Column() {
      NavBar({ title: '新建轨迹', showBack: true });

      Scroll() {
        Column({ space: 20 }) {
          // 提示
          Row({ space: 8 }) {
            Text('💡')
              .fontSize(16);
            Text('建议填写本次扫墓的地区、主要祖先姓氏、日期等信息，方便日后查找。')
              .fontSize(13)
              .fontColor($r('app.color.primary'))
              .lineHeight(20)
              .layoutWeight(1);
          }
          .width('100%')
          .padding(14)
          .backgroundColor($r('app.color.primary_light'))
          .borderRadius(12);

          // 轨迹名称
          Column({ space: 6 }) {
            Row() {
              Text('轨迹名称')
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.label_secondary'));
              Text(' *')
                .fontSize(13)
                .fontColor($r('app.color.destructive'));
            }
            TextInput({ placeholder: '例如：刘氏家族清明扫墓', text: this.title })
              .onChange((value: string) => {
                this.title = value;
              })
              .width('100%')
              .height(48)
              .fontSize(16)
              .backgroundColor($r('app.color.card_background'))
              .borderRadius(10)
              .padding({ left: 14, right: 14 })
              .borderWidth(1.5)
              .borderColor($r('app.color.separator'));
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start);

          // 轨迹简介
          Column({ space: 6 }) {
            Text('轨迹简介')
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.label_secondary'));
            TextArea({ placeholder: '简要描述本次扫墓的目的、参与人员等', text: this.description })
              .onChange((value: string) => {
                this.description = value;
              })
              .width('100%')
              .height(100)
              .fontSize(16)
              .backgroundColor($r('app.color.card_background'))
              .borderRadius(10)
              .padding(14)
              .borderWidth(1.5)
              .borderColor($r('app.color.separator'));
            Text('建议说明本次扫墓的地区、主要祖先、日期等')
              .fontSize(12)
              .fontColor($r('app.color.label_tertiary'));
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start);
        }
        .width('100%')
        .padding(20);
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)
      .backgroundColor($r('app.color.app_background'));

      // 底部按钮
      Column() {
        Button(this.isSaving ? '保存中…' : '保存并开始记录')
          .width('100%')
          .height(50)
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.White)
          .backgroundColor($r('app.color.primary'))
          .borderRadius(25)
          .enabled(this.title.trim().length > 0 && !this.isSaving)
          .opacity(this.title.trim().length > 0 && !this.isSaving ? 1 : 0.5)
          .onClick(() => {
            this.saveAndStartRecord();
          });
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 12, bottom: 32 })
      .backgroundColor($r('app.color.card_background'))
      .shadow({ radius: 8, color: '#0D000000', offsetX: 0, offsetY: -2 });
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.app_background'));
  }
}
