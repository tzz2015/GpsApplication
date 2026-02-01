import { router } from '@kit.ArkUI';
import { NavBar } from '../common/NavBar';

/**
 * P3-2 个人信息编辑页：iOS 风格，头像、昵称。
 */
@Entry
@Component
struct ProfileEdit {
  @State nickname: string = '昵称';

  build() {
    Column() {
      NavBar({ title: $r('app.string.profile_edit'), showBack: true });

      Scroll() {
        Column({ space: 24 }) {
          Column({ space: 12 }) {
            Image($r('app.media.startIcon'))
              .width(80)
              .height(80)
              .borderRadius(40)
              .objectFit(ImageFit.Cover)
              .onClick(() => {
                // TODO: 选择图片上传为头像
              });
            Text($r('app.string.profile_edit_avatar_hint'))
              .fontSize(13)
              .fontColor($r('app.color.label_tertiary'));
          }
          .padding(24);

          Column({ space: 8 }) {
            Text('昵称')
              .fontSize(13)
              .fontColor($r('app.color.label_tertiary'))
              .width('100%');
            TextInput({ placeholder: $r('app.string.profile_edit_nickname_hint'), text: this.nickname })
              .onChange((value: string) => {
                this.nickname = value;
              })
              .width('100%')
              .height(44)
              .fontSize(17)
              .backgroundColor($r('app.color.card_background'))
              .borderRadius(10)
              .padding({ left: 12, right: 12 });
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding(16)
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

      Button($r('app.string.profile_edit_save'))
        .width('90%')
        .height(50)
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.button_primary_text'))
        .backgroundColor($r('app.color.button_primary_bg'))
        .borderRadius(12)
        .margin({ bottom: 24 })
        .onClick(() => {
          // TODO: 写本地/Cloud DB 更新用户信息
          router.back();
        });
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.app_background'));
  }
}
