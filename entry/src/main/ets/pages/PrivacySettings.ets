import { promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { NavBar } from '../common/NavBar';
import { AuthStore } from '../common/AuthStore';
import { TrackStore } from '../common/TrackStore';
import { TrackModel } from '../common/TrackModel';
import { CloudDBService } from '../common/CloudDBService';
import { CloudStorageService } from '../common/CloudStorageService';

const LOG_DOMAIN = 0x0000;
const LOG_TAG = 'PrivacySettings';

/**
 * 隐私设置页面：隐私政策、用户协议、注销账户
 */
@Entry
@Component
struct PrivacySettings {
  @State isDeleting: boolean = false;

  build() {
    Column() {
      NavBar({ title: '隐私设置', showBack: true });

      Scroll() {
        Column({ space: 12 }) {
          // 隐私政策 & 用户协议
          Column() {
            this.SettingItem($r('app.media.ic_document'), '隐私政策', $r('app.color.menu_icon_sky'), () => {
              this.getUIContext().getRouter().pushUrl({ url: 'pages/PrivacyPolicy' });
            });
            Divider().color($r('app.color.separator')).margin({ left: 56, right: 16 });
            this.SettingItem($r('app.media.ic_clipboard'), '用户协议', $r('app.color.menu_icon_sky'), () => {
              this.getUIContext().getRouter().pushUrl({ url: 'pages/UserAgreement' });
            });
          }
          .backgroundColor($r('app.color.card_background'))
          .borderRadius(12)
          .shadow({ radius: 4, color: $r('app.color.shadow_light'), offsetX: 0, offsetY: 2 });

          // 注销账户
          Column() {
            this.SettingItem($r('app.media.ic_warning'), '注销账户', $r('app.color.destructive'), () => {
              this.showDeleteAccountDialog();
            });
          }
          .backgroundColor($r('app.color.card_background'))
          .borderRadius(12)
          .shadow({ radius: 4, color: $r('app.color.shadow_light'), offsetX: 0, offsetY: 2 });

          // 注销说明
          Text('注销账户后，您的所有数据（轨迹、打卡点、图片等）将被永久删除且不可恢复，请谨慎操作。')
            .fontSize(12)
            .fontColor($r('app.color.label_tertiary'))
            .padding({ left: 4, right: 4, top: 4 });
        }
        .width('100%')
        .padding(16);
      }
      .layoutWeight(1)
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring);

      // 删除中遮罩
      if (this.isDeleting) {
        Column() {
          LoadingProgress()
            .width(48)
            .height(48)
            .color(Color.White);
          Text('正在注销账户…')
            .fontSize(15)
            .fontColor(Color.White)
            .margin({ top: 12 });
        }
        .width('100%')
        .height('100%')
        .position({ x: 0, y: 0 })
        .backgroundColor('#99000000')
        .justifyContent(FlexAlign.Center)
        .zIndex(100);
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.app_background'));
  }

  @Builder
  SettingItem(icon: Resource, title: string, iconBgColor: string | Resource, onClick: () => void) {
    Row() {
      Column() {
        Image(icon)
          .width(18)
          .height(18)
          .fillColor(Color.White);
      }
      .width(32)
      .height(32)
      .borderRadius(8)
      .backgroundColor(iconBgColor)
      .justifyContent(FlexAlign.Center);
      Text(title)
        .fontSize(15)
        .fontColor(title === '注销账户' ? $r('app.color.destructive') : $r('app.color.label_primary'))
        .margin({ left: 14 })
        .layoutWeight(1);
      Image($r('app.media.ic_arrow_right'))
        .width(14)
        .height(14)
        .fillColor($r('app.color.label_tertiary'));
    }
    .width('100%')
    .height(56)
    .padding({ left: 16, right: 16 })
    .onClick(() => {
      onClick();
    });
  }

  /** 弹窗确认注销 */
  private showDeleteAccountDialog(): void {
    this.getUIContext().getPromptAction().showDialog({
      title: '注销账户',
      message: '注销后，您的账户信息、所有轨迹、打卡点及相关数据将被永久删除且不可恢复。\n\n确定要注销吗？',
      buttons: [
        { text: '取消', color: $r('app.color.dialog_secondary_text') },
        { text: '确定注销', color: $r('app.color.destructive') }
      ]
    }).then((result: promptAction.ShowDialogSuccessResponse) => {
      if (result.index === 1) {
        this.deleteAccountAndData();
      }
    }).catch(() => {});
  }

  /** 执行注销：删除云端数据 → 清除本地 → 跳转登录 */
  private async deleteAccountAndData(): Promise<void> {
    this.isDeleting = true;
    const context = this.getUIContext().getHostContext() as common.Context;

    try {
      // 1. 获取用户信息和所有轨迹
      const user = await AuthStore.getCurrentUser(context);
      const allTracks = await TrackStore.getTracks(context);

      // 2. 逐条删除云端数据（轨迹、轨迹点、打卡点、云存储文件）
      for (let i = 0; i < allTracks.length; i++) {
        const track: TrackModel.Track = allTracks[i];
        try {
          // 获取打卡点 ID 列表用于删除云存储图片
          const spots = await TrackStore.getTombSpotsByTrackId(context, track.trackId);
          const tombIds: string[] = spots.map((s: TrackModel.TombSpot) => s.tombId);

          // 删除云存储文件（封面、打卡点图片）
          await CloudStorageService.deleteTrackFiles(track.trackId, tombIds);

          // 删除云端打卡点
          for (let j = 0; j < tombIds.length; j++) {
            await CloudDBService.deleteTombSpot(tombIds[j]).catch((e: BusinessError) => {
              hilog.warn(LOG_DOMAIN, LOG_TAG, 'Delete cloud spot: %{public}s', JSON.stringify(e));
            });
          }

          // 删除云端轨迹点
          await CloudDBService.deleteTrackPoints(track.trackId).catch((e: BusinessError) => {
            hilog.warn(LOG_DOMAIN, LOG_TAG, 'Delete cloud points: %{public}s', JSON.stringify(e));
          });

          // 删除云端轨迹
          await CloudDBService.deleteTrack(track.trackId).catch((e: BusinessError) => {
            hilog.warn(LOG_DOMAIN, LOG_TAG, 'Delete cloud track: %{public}s', JSON.stringify(e));
          });

          // 删除本地轨迹
          await TrackStore.deleteTrack(context, track.trackId);

          hilog.info(LOG_DOMAIN, LOG_TAG, 'Deleted track [%{public}d/%{public}d]: %{public}s',
            i + 1, allTracks.length, track.trackId);
        } catch (e) {
          hilog.warn(LOG_DOMAIN, LOG_TAG, 'Delete track error: %{public}s', JSON.stringify(e));
        }
      }

      // 3. 清除用户信息
      await AuthStore.clearUser(context);

      hilog.info(LOG_DOMAIN, LOG_TAG, 'Account deleted, userId: %{public}s',
        user ? user.userId : 'unknown');

      // 4. 跳转登录页
      this.isDeleting = false;
      try {
        promptAction.showToast({ message: '账户已注销', alignment: Alignment.Center });
      } catch (_t) {
      }
      this.getUIContext().getRouter().replaceUrl({ url: 'pages/Login' });
    } catch (e) {
      this.isDeleting = false;
      hilog.error(LOG_DOMAIN, LOG_TAG, 'deleteAccountAndData error: %{public}s', JSON.stringify(e));
      try {
        promptAction.showToast({ message: '注销失败，请重试', alignment: Alignment.Center });
      } catch (_t) {
      }
    }
  }
}
