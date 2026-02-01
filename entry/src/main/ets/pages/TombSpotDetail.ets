import { router } from '@kit.ArkUI';
import { NavBar } from '../common/NavBar';

/**
 * P1-5 墓地点详情页：iOS 风格，终点名称、基本信息、图文区、编辑/删除（含确认）。
 */
@Entry
@Component
struct TombSpotDetail {
  @State endName: string = '墓地点';
  @State contentText: string = '';
  private segmentIndex: number = 1;
  private trackId: string = '';
  private trackTitle: string = '';

  aboutToAppear(): void {
    const params = router.getParams() as Record<string, string | number> | undefined;
    if (params) {
      this.endName = (params['endName'] as string) ?? this.endName;
      this.segmentIndex = (params['segmentIndex'] as number) ?? 1;
      this.trackId = (params['trackId'] as string) ?? '';
      this.trackTitle = (params['trackTitle'] as string) ?? '';
    }
  }

  /** 返回轨迹记录页，继续录制下一段 */
  goBackToRecordNextSegment(): void {
    router.replaceUrl({
      url: 'pages/TrackRecord',
      params: {
        trackId: this.trackId,
        title: this.trackTitle,
        segmentIndex: this.segmentIndex + 1
      }
    });
  }

  showDeleteConfirm(): void {
    AlertDialog.show({
      title: '删除图文',
      message: '确定删除该图文内容？',
      primaryButton: {
        value: '取消',
        action: () => {}
      },
      secondaryButton: {
        value: '确定',
        fontColor: $r('app.color.destructive'),
        action: () => {}
      }
    });
  }

  build() {
    Column() {
      NavBar({ title: this.endName, showBack: true });

      Scroll() {
        Column({ space: 20 }) {
          Column({ space: 8 }) {
            Text(`所属轨迹 · 第 ${this.segmentIndex} 段`)
              .fontSize(13)
              .fontColor($r('app.color.label_tertiary'));
            Text('经纬度、海拔（可折叠）')
              .fontSize(13)
              .fontColor($r('app.color.label_tertiary'));
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding(16)
          .backgroundColor($r('app.color.card_background'))
          .borderRadius(12);

          Column({ space: 12 }) {
            Text($r('app.string.tomb_spot_content'))
              .fontSize(17)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.label_primary'));
            TextArea({ placeholder: $r('app.string.tomb_spot_content_hint'), text: this.contentText })
              .onChange((value: string) => {
                this.contentText = value;
              })
              .width('100%')
              .height(100)
              .fontSize(15)
              .backgroundColor($r('app.color.app_background'))
              .borderRadius(10)
              .padding(12);
            Text('照片网格（多张图片，点击放大）')
              .fontSize(13)
              .fontColor($r('app.color.label_tertiary'));
          }
          .width('100%')
          .padding(16)
          .alignItems(HorizontalAlign.Start)
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

      Row({ space: 12 }) {
        Button('返回继续记录')
          .fontSize(17)
          .fontColor($r('app.color.button_primary_text'))
          .backgroundColor($r('app.color.primary'))
          .layoutWeight(1)
          .height(50)
          .borderRadius(12)
          .onClick(() => {
            this.goBackToRecordNextSegment();
          });
        Button($r('app.string.tomb_spot_edit'))
          .fontSize(17)
          .fontColor($r('app.color.primary'))
          .backgroundColor($r('app.color.card_background'))
          .layoutWeight(1)
          .height(50)
          .borderRadius(12)
          .onClick(() => {});
        Button($r('app.string.tomb_spot_delete'))
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
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.app_background'));
  }
}
