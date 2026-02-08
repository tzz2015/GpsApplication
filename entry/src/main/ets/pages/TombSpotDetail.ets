import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { picker } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { NavBar } from '../common/NavBar';
import { TrackStore } from '../common/TrackStore';
import { TrackModel } from '../common/TrackModel';

const LOG_DOMAIN = 0x0000;
const LOG_TAG = 'TombSpotDetail';

/** 路由参数接口 */
interface TombSpotDetailParams {
  tombId: string;
  trackId: string;
  trackTitle: string;
  fromRecording: boolean;
}

/**
 * P1-5 打卡点（墓地点）详情页
 * 展示并编辑打卡点信息、人物信息、图文记录
 */
@Entry
@Component
struct TombSpotDetail {
  @State spot: TrackModel.TombSpot | null = null;
  @State isEditing: boolean = false;
  @State spotName: string = '';
  @State contentText: string = '';
  @State personInfo: string = '';
  @State remark: string = '';
  @State imageUris: string[] = [];
  private tombId: string = '';
  private trackId: string = '';
  private trackTitle: string = '';
  private fromRecording: boolean = false;

  aboutToAppear(): void {
    const params = router.getParams() as TombSpotDetailParams | undefined;
    if (params) {
      this.tombId = params.tombId || '';
      this.trackId = params.trackId || '';
      this.trackTitle = params.trackTitle || '';
      this.fromRecording = params.fromRecording || false;
    }
    this.loadData();
    if (this.fromRecording) {
      this.isEditing = true;
    }
  }

  private async loadData(): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.Context;
    const s = await TrackStore.getTombSpotById(context, this.tombId);
    if (s) {
      this.spot = s;
      this.spotName = s.name;
      this.contentText = s.contentText;
      this.personInfo = s.personInfo;
      this.remark = s.remark;
      try {
        this.imageUris = JSON.parse(s.imageUris) as string[];
      } catch (e) {
        this.imageUris = [];
      }
    }
  }

  /** 保存打卡点信息 */
  private async saveSpotData(): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.Context;
    await TrackStore.updateTombSpot(context, this.tombId, {
      name: this.spotName,
      contentText: this.contentText,
      personInfo: this.personInfo,
      remark: this.remark,
      imageUris: JSON.stringify(this.imageUris)
    });
    this.isEditing = false;

    // 重新加载数据
    await this.loadData();
  }

  /** 选择图片 */
  private async pickImages(): Promise<void> {
    try {
      const photoPicker = new picker.PhotoViewPicker();
      const result = await photoPicker.select({
        MIMEType: picker.PhotoViewMIMETypes.IMAGE_TYPE,
        maxSelectNumber: 9
      });
      if (result && result.photoUris && result.photoUris.length > 0) {
        this.imageUris = this.imageUris.concat(result.photoUris);
      }
    } catch (e) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'pickImages error: %{public}s', JSON.stringify(e));
    }
  }

  /** 删除打卡点 */
  private showDeleteConfirm(): void {
    AlertDialog.show({
      title: '删除打卡点',
      message: '确定删除该打卡点及其图文内容？',
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: {
        value: '确定删除',
        fontColor: $r('app.color.destructive'),
        action: async () => {
          const context = this.getUIContext().getHostContext() as common.Context;
          await TrackStore.deleteTombSpot(context, this.tombId);
          router.back();
        }
      }
    });
  }

  build() {
    Column() {
      NavBar({ title: this.spotName || '打卡点详情', showBack: true });

      Scroll() {
        Column() {
          // 打卡点头部
          Column({ space: 8 }) {
            // 名称（可编辑）
            if (this.isEditing) {
              TextInput({ placeholder: '打卡点名称', text: this.spotName })
                .onChange((value: string) => {
                  this.spotName = value;
                })
                .width('100%')
                .height(44)
                .fontSize(20)
                .fontWeight(FontWeight.Bold)
                .backgroundColor($r('app.color.app_background'))
                .borderRadius(10)
                .padding({ left: 12, right: 12 });
            } else {
              Row({ space: 8 }) {
                Text(this.spotName)
                  .fontSize(22)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.label_primary'))
                  .layoutWeight(1);
                Button() {
                  Text('✏')
                    .fontSize(14);
                }
                .width(28)
                .height(28)
                .backgroundColor($r('app.color.primary_light'))
                .borderRadius(14)
                .onClick(() => {
                  this.isEditing = true;
                });
              }
              .width('100%');
            }

            // 所属轨迹
            Text(this.trackTitle + ' · 打卡点 #' + ((this.spot ? this.spot.orderIndex : 0) + 1).toString())
              .fontSize(12)
              .fontColor($r('app.color.label_tertiary'));

            // 位置信息
            if (this.spot) {
              Row({ space: 8 }) {
                Text('📍 ' + this.spot.latitude.toFixed(4) + '°N ' + this.spot.longitude.toFixed(4) + '°E')
                  .fontSize(12)
                  .fontColor($r('app.color.label_secondary'))
                  .padding({ left: 10, right: 10, top: 4, bottom: 4 })
                  .backgroundColor($r('app.color.app_background'))
                  .borderRadius(20);
                Text('⛰ 海拔 ' + this.spot.altitude.toString() + 'm')
                  .fontSize(12)
                  .fontColor($r('app.color.label_secondary'))
                  .padding({ left: 10, right: 10, top: 4, bottom: 4 })
                  .backgroundColor($r('app.color.app_background'))
                  .borderRadius(20);
              }
              .width('100%');

              Text('📅 ' + TrackModel.formatDate(this.spot.createdAt))
                .fontSize(12)
                .fontColor($r('app.color.label_tertiary'));
            }
          }
          .width('100%')
          .padding(16)
          .backgroundColor($r('app.color.card_background'));

          // 分隔
          Column().width('100%').height(8).backgroundColor($r('app.color.app_background'));

          // 图文记录区
          Column({ space: 12 }) {
            Text('📝 图文记录')
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.label_primary'))
              .width('100%');

            if (this.isEditing) {
              TextArea({ placeholder: '记录墓地相关的人物信息、故事、文字说明…', text: this.contentText })
                .onChange((value: string) => {
                  this.contentText = value;
                })
                .width('100%')
                .height(120)
                .fontSize(15)
                .backgroundColor($r('app.color.app_background'))
                .borderRadius(10)
                .padding(12);
            } else {
              if (this.contentText.length > 0) {
                Text(this.contentText)
                  .fontSize(14)
                  .fontColor($r('app.color.label_primary'))
                  .lineHeight(24)
                  .width('100%');
              } else {
                Text('暂无图文记录，点击编辑添加')
                  .fontSize(14)
                  .fontColor($r('app.color.label_tertiary'))
                  .fontStyle(FontStyle.Italic)
                  .width('100%');
              }
            }

            // 照片区域
            if (this.imageUris.length > 0 || this.isEditing) {
              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(this.imageUris, (uri: string, index: number) => {
                  Stack() {
                    Image(uri)
                      .width(100)
                      .height(100)
                      .objectFit(ImageFit.Cover)
                      .borderRadius(8);
                    if (this.isEditing) {
                      Button() {
                        Text('✕')
                          .fontSize(12)
                          .fontColor(Color.White);
                      }
                      .width(20)
                      .height(20)
                      .backgroundColor($r('app.color.destructive'))
                      .borderRadius(10)
                      .position({ x: 76, y: 2 })
                      .onClick(() => {
                        this.imageUris.splice(index, 1);
                        this.imageUris = this.imageUris.slice(0);
                      });
                    }
                  }
                  .width(104)
                  .height(104)
                  .margin(4);
                }, (uri: string, index: number) => uri + index.toString());

                if (this.isEditing) {
                  Column() {
                    Text('+')
                      .fontSize(28)
                      .fontColor($r('app.color.label_tertiary'));
                    Text('添加照片')
                      .fontSize(11)
                      .fontColor($r('app.color.label_tertiary'));
                  }
                  .width(100)
                  .height(100)
                  .margin(4)
                  .justifyContent(FlexAlign.Center)
                  .backgroundColor($r('app.color.app_background'))
                  .borderRadius(8)
                  .borderWidth(1)
                  .borderColor($r('app.color.separator'))
                  .borderStyle(BorderStyle.Dashed)
                  .onClick(() => {
                    this.pickImages();
                  });
                }
              }
              .width('100%');
            }
          }
          .width('100%')
          .padding(16)
          .backgroundColor($r('app.color.card_background'));

          // 分隔
          Column().width('100%').height(8).backgroundColor($r('app.color.app_background'));

          // 人物信息
          Column({ space: 12 }) {
            Text('👤 人物信息')
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.label_primary'))
              .width('100%');

            if (this.isEditing) {
              TextArea({ placeholder: '姓氏、辈分、称呼、年代等信息…', text: this.personInfo })
                .onChange((value: string) => {
                  this.personInfo = value;
                })
                .width('100%')
                .height(80)
                .fontSize(15)
                .backgroundColor($r('app.color.app_background'))
                .borderRadius(10)
                .padding(12);

              TextArea({ placeholder: '备注信息…', text: this.remark })
                .onChange((value: string) => {
                  this.remark = value;
                })
                .width('100%')
                .height(60)
                .fontSize(15)
                .backgroundColor($r('app.color.app_background'))
                .borderRadius(10)
                .padding(12);
            } else {
              if (this.personInfo.length > 0) {
                Text(this.personInfo)
                  .fontSize(14)
                  .fontColor($r('app.color.label_primary'))
                  .lineHeight(22)
                  .width('100%');
              }
              if (this.remark.length > 0) {
                Text('备注：' + this.remark)
                  .fontSize(13)
                  .fontColor($r('app.color.label_secondary'))
                  .lineHeight(20)
                  .width('100%');
              }
              if (this.personInfo.length === 0 && this.remark.length === 0) {
                Text('暂无人物信息')
                  .fontSize(14)
                  .fontColor($r('app.color.label_tertiary'))
                  .fontStyle(FontStyle.Italic)
                  .width('100%');
              }
            }
          }
          .width('100%')
          .padding(16)
          .backgroundColor($r('app.color.card_background'));

          // 底部操作
          Column({ space: 8 }) {
            if (this.isEditing) {
              Button('保存')
                .width('100%')
                .height(50)
                .fontSize(17)
                .fontWeight(FontWeight.Medium)
                .fontColor(Color.White)
                .backgroundColor($r('app.color.primary'))
                .borderRadius(25)
                .onClick(() => {
                  this.saveSpotData();
                });
              if (this.fromRecording) {
                Button('保存并返回继续记录')
                  .width('100%')
                  .height(44)
                  .fontSize(15)
                  .fontColor($r('app.color.accent'))
                  .backgroundColor($r('app.color.accent_light'))
                  .borderRadius(22)
                  .onClick(async () => {
                    await this.saveSpotData();
                    router.back();
                  });
              }
            } else {
              Row({ space: 12 }) {
                Button('编辑图文')
                  .layoutWeight(1)
                  .height(50)
                  .fontSize(17)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(Color.White)
                  .backgroundColor($r('app.color.primary'))
                  .borderRadius(25)
                  .onClick(() => {
                    this.isEditing = true;
                  });
                Button('删除')
                  .width(80)
                  .height(50)
                  .fontSize(15)
                  .fontColor($r('app.color.destructive'))
                  .backgroundColor(Color.Transparent)
                  .borderWidth(1.5)
                  .borderColor($r('app.color.destructive'))
                  .borderRadius(25)
                  .onClick(() => {
                    this.showDeleteConfirm();
                  });
              }
              .width('100%');
            }
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 16, bottom: 40 });
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
}
