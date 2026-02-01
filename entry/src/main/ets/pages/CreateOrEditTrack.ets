
import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { NavBar } from '../common/NavBar';
import { TrackStore } from '../common/TrackStore';
import { TrackModel } from '../common/TrackModel';

/**
 * P1-2 新建/编辑轨迹基础信息页：保存轨迹到本地并跳转轨迹记录页。
 */
@Entry
@Component
struct CreateOrEditTrack {
  @State title: string = '';
  @State description: string = '';
  private trackId: string = '';

  private async saveAndStartRecord(): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.Context;
    const id = this.trackId || ('track_' + Date.now() + '_' + Math.random().toString(36).slice(2, 9));
    const track: TrackModel.Track = {
      trackId: id,
      title: this.title.trim(),
      description: this.description.trim(),
      status: TrackModel.TRACK_STATUS_EDITING,
      segmentCount: 0,
      createdAt: Date.now()
    };
    await TrackStore.saveTrack(context, track);
    router.replaceUrl({
      url: 'pages/TrackRecord',
      params: { trackId: id, title: this.title.trim() }
    });
  }

  build() {
    Column() {
      NavBar({ title: $r('app.string.home_new_track'), showBack: true });

      Scroll() {
        Column({ space: 20 }) {
          Column({ space: 8 }) {
            Text($r('app.string.create_track_title_hint'))
              .fontSize(13)
              .fontColor($r('app.color.label_tertiary'));
            TextInput({ placeholder: $r('app.string.create_track_title_hint'), text: this.title })
              .onChange((value: string) => {
                this.title = value;
              })
              .width('100%')
              .height(44)
              .fontSize(17)
              .backgroundColor($r('app.color.card_background'))
              .borderRadius(10)
              .padding({ left: 12, right: 12 });
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start);

          Column({ space: 8 }) {
            Text($r('app.string.create_track_desc_hint'))
              .fontSize(13)
              .fontColor($r('app.color.label_tertiary'));
            TextArea({ placeholder: $r('app.string.create_track_desc_hint'), text: this.description })
              .onChange((value: string) => {
                this.description = value;
              })
              .width('100%')
              .height(100)
              .fontSize(17)
              .backgroundColor($r('app.color.card_background'))
              .borderRadius(10)
              .padding(12);
            Text($r('app.string.create_track_desc_tip'))
              .fontSize(13)
              .fontColor($r('app.color.label_tertiary'));
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start);
        }
        .width('100%')
        .padding(16);
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)
      .backgroundColor($r('app.color.app_background'));

      Button($r('app.string.create_track_save'))
        .width('90%')
        .height(50)
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.button_primary_text'))
        .backgroundColor($r('app.color.button_primary_bg'))
        .borderRadius(12)
        .enabled(this.title.trim().length > 0)
        .opacity(this.title.trim().length > 0 ? 1 : 0.5)
        .margin({ bottom: 24 })
        .onClick(() => {
          this.saveAndStartRecord();
        });
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.app_background'));
  }
}
