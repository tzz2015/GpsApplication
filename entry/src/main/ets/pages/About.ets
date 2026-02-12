import { NavBar } from '../common/NavBar';
import { Config } from '../common/Config';

/**
 * 关于页面：品牌展示 + APP 介绍 + 版权信息
 */
@Entry
@Component
struct About {
  build() {
    Column() {
      NavBar({ title: '关于', showBack: true });

      Scroll() {
        Column() {
          // ===== 品牌区 =====
          Column({ space: 12 }) {
            // 图标 + 光晕效果
            Stack() {
              Column()
                .width(110)
                .height(110)
                .borderRadius(55)
                .backgroundColor($r('app.color.primary_light'));
              Image($r('app.media.startIcon'))
                .width(88)
                .height(88)
                .borderRadius(22)
                .objectFit(ImageFit.Contain)
                .shadow({ radius: 16, color: $r('app.color.shadow_medium'), offsetX: 0, offsetY: 4 });
            }

            Text($r('app.string.app_name'))
              .fontSize(24)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.label_primary'));

            Text('V' + Config.APP_VERSION)
              .fontSize(13)
              .fontColor(Color.White)
              .backgroundColor($r('app.color.primary'))
              .padding({ left: 12, right: 12, top: 4, bottom: 4 })
              .borderRadius(12);

            Text($r('app.string.about_tagline'))
              .fontSize(14)
              .fontColor($r('app.color.label_secondary'))
              .margin({ top: 4 });
          }
          .width('100%')
          .padding({ top: 36, bottom: 28 })
          .alignItems(HorizontalAlign.Center);

          // ===== APP 介绍卡片 =====
          Column({ space: 16 }) {
            Text('遨游轨迹是一款专为家族祭祖扫墓场景设计的轨迹记录工具。')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.label_primary'))
              .lineHeight(24)
              .width('100%');

            Text('许多家族的祖先墓地分布在偏远山区，道路复杂，年轻一代常常难以找到具体位置。遨游轨迹通过实时 GPS 记录行进路线，在沿途关键位置设置打卡点，配合图文与人物信息记录，将一次扫墓经历完整保存下来。')
              .fontSize(14)
              .fontColor($r('app.color.label_secondary'))
              .lineHeight(24)
              .width('100%');

            Text('下一次，无论是谁前往祭扫，只需打开保存的轨迹，跟随路线指引即可顺利抵达每一处墓地。让寻根祭祖不再困难，让家族记忆代代相传。')
              .fontSize(14)
              .fontColor($r('app.color.label_secondary'))
              .lineHeight(24)
              .width('100%');
          }
          .padding(20)
          .backgroundColor($r('app.color.card_background'))
          .borderRadius(16)
          .margin({ left: 20, right: 20 })
          .shadow({ radius: 8, color: $r('app.color.shadow_light'), offsetX: 0, offsetY: 2 });

          // ===== 底部版权 =====
          Column({ space: 6 }) {
            Text($r('app.string.about_desc'))
              .fontSize(12)
              .fontColor($r('app.color.label_tertiary'))
              .textAlign(TextAlign.Center);
            Text('Build ' + Config.BUILD_NUMBER)
              .fontSize(11)
              .fontColor($r('app.color.label_tertiary'));
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
          .padding({ top: 24, bottom: 40 });
        }
        .width('100%');
      }
      .layoutWeight(1)
      .width('100%')
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
