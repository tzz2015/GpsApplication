import { promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { picker } from '@kit.CoreFileKit';
import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { NavBar } from '../common/NavBar';
import { TrackStore } from '../common/TrackStore';
import { TrackModel } from '../common/TrackModel';
import { CloudStorageService } from '../common/CloudStorageService';
import { SyncService } from '../common/SyncService';

const LOG_DOMAIN = 0x0000;
const LOG_TAG = 'TombSpotDetail';

/** 路由参数接口 */
interface TombSpotDetailParams {
  tombId: string;
  trackId: string;
  trackTitle: string;
  fromRecording: boolean;
}

/** 捏合手势回调中事件对象带有的 scale 字段（ArkTS 禁止对象字面量作类型） */
interface PinchEventLike {
  scale?: number;
}

/** 拖拽手势回调中事件对象带有的 offset 字段（ArkTS 禁止对象字面量作类型） */
interface PanEventLike {
  offsetX?: number;
  offsetY?: number;
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
  /** 图片查看器：打开大图、缩放、下载 */
  @State showImageViewer: boolean = false;
  @State selectedImageIndex: number = 0;
  @State viewerScale: number = 1;
  @State viewerOffsetX: number = 0;
  @State viewerOffsetY: number = 0;
  @State isDownloading: boolean = false;
  private tombId: string = '';
  private pinchStartScale: number = 1;
  private panStartX: number = 0;
  private panStartY: number = 0;
  private trackId: string = '';
  private trackTitle: string = '';
  private fromRecording: boolean = false;

  aboutToAppear(): void {
    const params = this.getUIContext().getRouter().getParams() as TombSpotDetailParams | undefined;
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

  /** 保存打卡点信息（含同步到 Cloud DB，重装后可恢复） */
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

    // 同步到云端（等待完成，确保 contentText/imageUris 写入 Cloud DB）
    try {
      await SyncService.syncTrack(context, this.trackId);
    } catch (e) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'Sync after save: %{public}s', JSON.stringify(e));
    }

    // 重新加载数据
    await this.loadData();
  }

  /** 选择图片：先展示缩略图（本地 URI），再在后台上传并替换为云端 URL */
  private async pickImages(): Promise<void> {
    try {
      const photoPicker = new picker.PhotoViewPicker();
      const result = await photoPicker.select({
        MIMEType: picker.PhotoViewMIMETypes.IMAGE_TYPE,
        maxSelectNumber: 9
      });
      if (result && result.photoUris && result.photoUris.length > 0) {
        const context = this.getUIContext().getHostContext() as common.Context;
        const newUris: string[] = this.imageUris.concat(result.photoUris);
        this.imageUris = newUris;
        const urisJson: string = JSON.stringify(newUris);
        CloudStorageService.uploadSpotImages(context, this.trackId, this.tombId, urisJson)
          .then((updatedJson: string) => {
            const updated: string[] = JSON.parse(updatedJson) as string[];
            this.imageUris = updated;
            TrackStore.updateTombSpot(context, this.tombId, { imageUris: updatedJson });
            hilog.info(LOG_DOMAIN, LOG_TAG, 'Upload done, spot images: %{public}d', updated.length);
            SyncService.syncTrack(context, this.trackId).then(() => {
              hilog.info(LOG_DOMAIN, LOG_TAG, 'Spot synced to Cloud DB after image upload');
            }).catch((e: Error) => {
              hilog.warn(LOG_DOMAIN, LOG_TAG, 'Sync after image upload: %{public}s', JSON.stringify(e));
            });
          })
          .catch((e: Error) => {
            hilog.error(LOG_DOMAIN, LOG_TAG, 'uploadSpotImages error: %{public}s', JSON.stringify(e));
          });
      }
    } catch (e) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'pickImages error: %{public}s', JSON.stringify(e));
    }
  }

  /** 打开图片查看器（大图、双指缩放/拖动、滑动切换、下载） */
  private openImageViewer(index: number): void {
    this.selectedImageIndex = index;
    this.viewerScale = 1;
    this.viewerOffsetX = 0;
    this.viewerOffsetY = 0;
    this.showImageViewer = true;
  }

  /** 重置当前页缩放与偏移（切换图片时调用） */
  private resetViewerTransform(): void {
    this.viewerScale = 1;
    this.viewerOffsetX = 0;
    this.viewerOffsetY = 0;
  }

  /** 关闭图片查看器 */
  private closeImageViewer(): void {
    this.showImageViewer = false;
  }

  /** 下载当前查看的图片到应用目录 */
  private async downloadCurrentImage(): Promise<void> {
    if (this.imageUris.length === 0 || this.selectedImageIndex < 0 || this.selectedImageIndex >= this.imageUris.length) {
      return;
    }
    const uri: string = this.imageUris[this.selectedImageIndex];
    this.isDownloading = true;
    const context = this.getUIContext().getHostContext() as common.Context;
    try {
      let savedPath: string = '';
      if (uri.startsWith('http://') || uri.startsWith('https://')) {
        const httpReq = http.createHttp();
        const resp = await httpReq.request(uri, { method: http.RequestMethod.GET, expectDataType: http.HttpDataType.ARRAY_BUFFER });
        const data = resp.result as ArrayBuffer;
        httpReq.destroy();
        const dir = context.filesDir + '/Download';
        try {
          fileIo.mkdirSync(dir, false);
        } catch (e) {
          // 已存在则忽略
        }
        const name = 'img_' + Date.now() + '.jpg';
        savedPath = dir + '/' + name;
        const f = fileIo.openSync(savedPath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
        fileIo.writeSync(f.fd, data);
        fileIo.closeSync(f);
      } else if (uri.startsWith('file://') || (uri.length > 0 && !uri.startsWith('http'))) {
        const dir = context.filesDir + '/Download';
        try {
          fileIo.mkdirSync(dir, false);
        } catch (e) {
          // ignore
        }
        const name = 'img_' + Date.now() + '.jpg';
        savedPath = dir + '/' + name;
        try {
          fileIo.copyFileSync(uri, savedPath);
        } catch (copyErr) {
          const srcFile = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
          const dstFile = fileIo.openSync(savedPath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
          const bufSize = 8192;
          const buf = new ArrayBuffer(bufSize);
          let readLen = fileIo.readSync(srcFile.fd, buf);
          while (readLen > 0) {
            fileIo.writeSync(dstFile.fd, buf.slice(0, readLen));
            readLen = fileIo.readSync(srcFile.fd, buf);
          }
          fileIo.closeSync(srcFile);
          fileIo.closeSync(dstFile);
        }
      }
      if (savedPath.length > 0) {
        promptAction.openToast({ message: '已保存至：' + savedPath });
      }
    } catch (e) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Download image failed: %{public}s', JSON.stringify(e));
      try {
        promptAction.openToast({ message: '保存失败' });
      } catch (_t) {
        // 忽略 Toast 异常
      }
    }
    this.isDownloading = false;
  }

  /** 删除打卡点 */
  private showDeleteConfirm(): void {
    this.getUIContext().getPromptAction().showDialog({
      message: '确定删除该打卡点及其图文内容？',
      buttons: [
        { text: $r('app.string.dialog_cancel'), color: $r('app.color.dialog_secondary_text') },
        { text: $r('app.string.dialog_confirm_delete'), color: $r('app.color.destructive') }
      ]
    }).then((result: promptAction.ShowDialogSuccessResponse) => {
      if (result.index === 1) {
        const context = this.getUIContext().getHostContext() as common.Context;
        TrackStore.deleteTombSpot(context, this.tombId).then(() => {
          this.getUIContext().getRouter().back();
        });
      }
    }).catch(() => {});
  }

  /** 全屏图片预览：Swiper 左右滑动多图，底部关闭/下载便于点击 */
  @Builder
  imageViewerCover(): void {
    Column() {
      Swiper() {
        ForEach(this.imageUris, (uri: string, index: number) => {
          Stack() {
            Image(uri)
              .width('100%')
              .height('100%')
              .objectFit(ImageFit.Contain)
              .scale({ x: this.viewerScale, y: this.viewerScale })
              .translate({ x: this.viewerOffsetX, y: this.viewerOffsetY })
              .gesture(
                PinchGesture({ fingers: 2, distance: 0.1 })
                  .onActionStart(() => {
                    this.pinchStartScale = this.viewerScale;
                  })
                  .onActionUpdate((event: GestureEvent) => {
                    const pinchEvent = event as PinchEventLike;
                    const scaleVal = pinchEvent.scale !== undefined ? pinchEvent.scale : 1;
                    const s = this.pinchStartScale * scaleVal;
                    this.viewerScale = Math.min(4, Math.max(0.5, s));
                  })
                  .onActionEnd(() => {
                    this.pinchStartScale = this.viewerScale;
                  })
              );
          }
          .width('100%')
          .height('100%');
        }, (uri: string, index: number) => uri + index.toString());
      }
      .index(this.selectedImageIndex)
      .indicator(false)
      .loop(false)
      .curve(Curve.EaseOut)
      .onChange((index: number) => {
        this.selectedImageIndex = index;
        this.resetViewerTransform();
      })
      .layoutWeight(1)
      .width('100%');

      Column() {
        Text((this.selectedImageIndex + 1).toString() + ' / ' + this.imageUris.length.toString())
          .fontSize(13)
          .fontColor('rgba(255,255,255,0.8)');
        Row() {
          Button('关闭')
            .fontSize(16)
            .fontColor(Color.White)
            .backgroundColor($r('app.color.overlay_dark'))
            .layoutWeight(1)
            .height(48)
            .onClick(() => {
              this.closeImageViewer();
            });
          Button(this.isDownloading ? '保存中…' : '下载')
            .fontSize(16)
            .fontColor(Color.White)
            .backgroundColor($r('app.color.overlay_dark'))
            .layoutWeight(1)
            .height(48)
            .enabled(!this.isDownloading)
            .onClick(() => {
              this.downloadCurrentImage();
            });
        }
        .width('100%');
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 16, top: 12 })
      .backgroundColor($r('app.color.overlay_dark_strong'));
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.overlay_dark_modal'));
  }

  build() {
    Stack() {
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
            Text($r('app.string.tomb_spot_section'))
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
                Text($r('app.string.tomb_spot_empty'))
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
                      .borderRadius(8)
                      .onClick(() => {
                        this.openImageViewer(index);
                      });
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
                      .onClick(async () => {
                        const uri = this.imageUris[index];
                        if (uri && (uri.startsWith('http://') || uri.startsWith('https://'))) {
                          try {
                            await CloudStorageService.deleteSpotImageByUrl(uri);
                          } catch (e) {
                            hilog.warn(LOG_DOMAIN, LOG_TAG, 'Delete cloud image: %{public}s', JSON.stringify(e));
                          }
                        }
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
                    Text($r('app.string.tomb_spot_add_photo'))
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
            Text($r('app.string.tomb_spot_person_section'))
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
                Text($r('app.string.tomb_spot_person_empty'))
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
              if (this.fromRecording) {
                Button('保存并返回继续记录')
                  .width('100%')
                  .height(50)
                  .fontSize(17)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(Color.White)
                  .backgroundColor($r('app.color.primary'))
                  .borderRadius(25)
                  .onClick(async () => {
                    await this.saveSpotData();
                    this.getUIContext().getRouter().back();
                  });
              }
              Button(this.fromRecording ? '仅保存' : '保存')
                .width('100%')
                .height(this.fromRecording ? 44 : 50)
                .fontSize(this.fromRecording ? 15 : 17)
                .fontWeight(FontWeight.Medium)
                .fontColor(Color.White)
                .backgroundColor(this.fromRecording ? $r('app.color.primary') : $r('app.color.primary'))
                .borderRadius(this.fromRecording ? 22 : 25)
                .onClick(() => {
                  this.saveSpotData();
                });
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
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.app_background'))
    .bindContentCover(this.showImageViewer, this.imageViewerCover());
  }
}
