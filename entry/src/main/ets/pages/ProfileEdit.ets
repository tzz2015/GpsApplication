import { common } from '@kit.AbilityKit';
import { picker } from '@kit.CoreFileKit';
import { NavBar } from '../common/NavBar';
import { AuthStore } from '../common/AuthStore';
import { SyncService } from '../common/SyncService';
import { CloudStorageService } from '../common/CloudStorageService';

/**
 * P3-2 个人信息编辑页：头像、昵称、家族、签名
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
    // 同步到 Cloud DB，重装后登录可恢复昵称
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
          // 头像区域（可点击更换），顶部无留白
          Column({ space: 12 }) {
            Stack() {
              if (this.avatarUrl.length > 0) {
                Image(this.avatarUrl)
                  .width(80)
                  .height(80)
                  .borderRadius(40)
                  .objectFit(ImageFit.Cover);
              } else {
                Column() {
                  Text('👤')
                    .fontSize(36);
                }
                .width(80)
                .height(80)
                .borderRadius(40)
                .backgroundColor($r('app.color.primary_light'))
                .justifyContent(FlexAlign.Center);
              }
              // 相机角标
              Column() {
                Text(this.isUploadingAvatar ? '…' : '📷')
                  .fontSize(14);
              }
              .width(28)
              .height(28)
              .borderRadius(14)
              .backgroundColor('#3478F6')
              .justifyContent(FlexAlign.Center)
              .borderWidth(2)
              .borderColor(Color.White)
              .position({ x: 56, y: 56 });
            }
            .width(80)
            .height(80)
            .onClick(() => {
              this.pickAndUploadAvatar();
            });
            Text(this.isUploadingAvatar ? '上传中…' : '点击更换头像')
              .fontSize(13)
              .fontColor($r('app.color.label_tertiary'));
          }
          .width('100%')
          .padding(24)
          .backgroundColor($r('app.color.card_background'))
          .alignItems(HorizontalAlign.Center);

          Column().width('100%').height(8).backgroundColor($r('app.color.app_background'));

          // 表单
          Column({ space: 16 }) {
            Column({ space: 6 }) {
              Text('昵称')
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.label_secondary'));
              TextInput({ placeholder: '请输入昵称', text: this.nickname })
                .onChange((value: string) => {
                  this.nickname = value;
                })
                .width('100%')
                .height(44)
                .fontSize(16)
                .backgroundColor($r('app.color.app_background'))
                .borderRadius(10)
                .padding({ left: 12, right: 12 });
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start);

            Column({ space: 6 }) {
              Text('所属家族')
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.label_secondary'));
              TextInput({ placeholder: '例如：刘氏', text: this.familyName })
                .onChange((value: string) => {
                  this.familyName = value;
                })
                .width('100%')
                .height(44)
                .fontSize(16)
                .backgroundColor($r('app.color.app_background'))
                .borderRadius(10)
                .padding({ left: 12, right: 12 });
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start);
          }
          .width('100%')
          .padding(20)
          .backgroundColor($r('app.color.card_background'));
        }
        .width('100%');
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .backgroundColor($r('app.color.app_background'));

      Button(this.isSaving ? '保存中…' : '保存')
        .width('90%')
        .height(50)
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor(Color.White)
        .backgroundColor($r('app.color.primary'))
        .borderRadius(25)
        .enabled(!this.isSaving)
        .margin({ bottom: 32 })
        .onClick(() => {
          this.saveUserInfo();
        });
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.app_background'));
  }
}
