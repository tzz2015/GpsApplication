import { common } from '@kit.AbilityKit';
import { picker } from '@kit.CoreFileKit';
import { NavBar } from '../common/NavBar';
import { AuthStore } from '../common/AuthStore';
import { SyncService } from '../common/SyncService';
import { CloudStorageService } from '../common/CloudStorageService';

/**
 * P3-2 个人信息编辑页：头像、昵称、家族
 */
@Entry
@Component
struct ProfileEdit {
  @State nickname: string = '';
  @State familyName: string = '';
  @State avatarUrl: string = '';
  @State isSaving: boolean = false;
  @State isUploadingAvatar: boolean = false;

  aboutToAppear(): void {
    this.loadUserInfo();
  }

  private async loadUserInfo(): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.Context;
    const user = await AuthStore.getCurrentUser(context);
    if (user) {
      this.nickname = user.displayName;
      this.familyName = user.familyName;
      this.avatarUrl = user.avatarUrl;
    }
  }

  private async saveUserInfo(): Promise<void> {
    this.isSaving = true;
    const context = this.getUIContext().getHostContext() as common.Context;
    await AuthStore.updateUser(context, {
      displayName: this.nickname,
      familyName: this.familyName,
      avatarUrl: this.avatarUrl
    });
    SyncService.syncUser(context).catch(() => {});
    this.isSaving = false;
    this.getUIContext().getRouter().back();
  }

  /** 选择照片并上传为头像 */
  private async pickAndUploadAvatar(): Promise<void> {
    if (this.isUploadingAvatar) {
      return;
    }
    const context = this.getUIContext().getHostContext() as common.Context;
    const user = await AuthStore.getCurrentUser(context);
    if (!user) {
      return;
    }
    try {
      const photoPicker = new picker.PhotoViewPicker();
      const result = await photoPicker.select({
        MIMEType: picker.PhotoViewMIMETypes.IMAGE_TYPE,
        maxSelectNumber: 1
      });
      if (result && result.photoUris && result.photoUris.length > 0) {
        const uri: string = result.photoUris[0];
        this.isUploadingAvatar = true;
        const cloudUrl: string = await CloudStorageService.uploadUserAvatar(context, user.userId, uri);
        this.isUploadingAvatar = false;
        if (cloudUrl.length > 0) {
          this.avatarUrl = cloudUrl;
          await AuthStore.updateUser(context, { avatarUrl: cloudUrl });
          SyncService.syncUser(context).catch(() => {});
        }
      }
    } catch (e) {
      this.isUploadingAvatar = false;
    }
  }

  build() {
    Column() {
      NavBar({ title: '编辑个人信息', showBack: true });

      Scroll() {
        Column() {
          // ===== 统一卡片：头像 + 表单 + 保存 =====
          Column({ space: 24 }) {

            // --- 头像区域 ---
            Column({ space: 10 }) {
              Stack() {
                if (this.avatarUrl.length > 0) {
                  Image(this.avatarUrl)
                    .width(88)
                    .height(88)
                    .borderRadius(44)
                    .objectFit(ImageFit.Cover);
                } else {
                  Column() {
                    Image($r('app.media.ic_user'))
                      .width(40)
                      .height(40)
                      .fillColor(Color.White);
                  }
                  .width(88)
                  .height(88)
                  .borderRadius(44)
                  .backgroundColor($r('app.color.primary'))
                  .justifyContent(FlexAlign.Center);
                }
                // 相机角标
                Column() {
                  if (this.isUploadingAvatar) {
                    LoadingProgress()
                      .width(16)
                      .height(16)
                      .color(Color.White);
                  } else {
                    Image($r('app.media.ic_camera'))
                      .width(16)
                      .height(16)
                      .fillColor(Color.White);
                  }
                }
                .width(32)
                .height(32)
                .borderRadius(16)
                .backgroundColor($r('app.color.accent'))
                .justifyContent(FlexAlign.Center)
                .borderWidth(3)
                .borderColor(Color.White)
                .position({ x: 60, y: 60 });
              }
              .width(88)
              .height(88)
              .onClick(() => {
                this.pickAndUploadAvatar();
              });

              Text(this.isUploadingAvatar ? '上传中…' : '点击更换头像')
                .fontSize(13)
                .fontColor($r('app.color.label_tertiary'));
            }
            .width('100%')
            .alignItems(HorizontalAlign.Center);

            // --- 分隔线 ---
            Row()
              .width('100%')
              .height(1)
              .backgroundColor($r('app.color.separator'));

            // --- 表单字段 ---
            Column({ space: 20 }) {
              // 昵称
              Column({ space: 8 }) {
                Text('昵称')
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.label_primary'));
                TextInput({ placeholder: '请输入昵称', text: this.nickname })
                  .onChange((value: string) => {
                    this.nickname = value;
                  })
                  .width('100%')
                  .height(46)
                  .fontSize(15)
                  .backgroundColor($r('app.color.app_background'))
                  .borderRadius(12)
                  .padding({ left: 14, right: 14 });
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start);

              // 家族
              Column({ space: 8 }) {
                Text('家族称谓')
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.label_primary'));
                TextInput({ placeholder: '例如：刘氏', text: this.familyName })
                  .onChange((value: string) => {
                    this.familyName = value;
                  })
                  .width('100%')
                  .height(46)
                  .fontSize(15)
                  .backgroundColor($r('app.color.app_background'))
                  .borderRadius(12)
                  .padding({ left: 14, right: 14 });
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start);
            }
            .width('100%');

            // --- 保存按钮 ---
            Button(this.isSaving ? '保存中…' : '保存')
              .width('100%')
              .height(46)
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(Color.White)
              .backgroundColor($r('app.color.primary'))
              .borderRadius(23)
              .enabled(!this.isSaving)
              .opacity(this.isSaving ? 0.5 : 1)
              .onClick(() => {
                this.saveUserInfo();
              });
          }
          .padding({ left: 20, right: 20, top: 28, bottom: 24 })
          .backgroundColor($r('app.color.card_background'))
          .borderRadius(16)
          .margin({ left: 20, right: 20, top: 16 })
          .shadow({ radius: 8, color: $r('app.color.shadow_light'), offsetX: 0, offsetY: 2 });

          // 底部提示
          Text('修改后将自动同步到云端')
            .fontSize(12)
            .fontColor($r('app.color.label_tertiary'))
            .margin({ top: 16, bottom: 40 });
        }
        .width('100%');
      }
      .layoutWeight(1)
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.None)
      .backgroundColor($r('app.color.app_background'));
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.app_background'));
  }
}
