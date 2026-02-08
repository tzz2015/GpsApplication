import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { authentication } from '@kit.AccountKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { TrackStore } from '../common/TrackStore';
import { TrackModel } from '../common/TrackModel';
import { AuthStore, type AuthUser } from '../common/AuthStore';

const LOG_DOMAIN = 0x0000;
const LOG_TAG = 'Main';

/**
 * P1-0 首页 + P3-1 个人中心：我的轨迹从本地存储加载并展示；显示登录用户头像与昵称。
 */
@Entry
@Component
struct Main {
  @State currentBottomIndex: number = 0;
  @State currentTopIndex: number = 0;
  @State myTracks: TrackModel.Track[] = [];
  @State isLoadingMyTracks: boolean = false;
  @State hasErrorMyTracks: boolean = false;
  @State currentUser: AuthUser | null = null;

  private loadMyTracks(): void {
    this.isLoadingMyTracks = true;
    const context = this.getUIContext().getHostContext() as common.Context;
    TrackStore.getTracks(context).then((tracks: TrackModel.Track[]) => {
      this.myTracks = tracks;
      this.isLoadingMyTracks = false;
    }).catch(() => {
      this.hasErrorMyTracks = true;
      this.isLoadingMyTracks = false;
    });
  }

  private loadCurrentUser(): void {
    const context = this.getUIContext().getHostContext() as common.Context;
    AuthStore.getCurrentUser(context).then((user: AuthUser | null) => {
      this.currentUser = user;
    }).catch(() => {
      this.currentUser = null;
    });
  }

  aboutToAppear(): void {
    this.loadMyTracks();
    this.loadCurrentUser();
  }

  onPageShow(): void {
    this.loadMyTracks();
    this.loadCurrentUser();
  }

  @Builder
  HomeTabContent() {
    Column() {
      // 首页顶部：登录用户头像与昵称
      Row({ space: 12 }) {
        if (this.currentUser && this.currentUser.avatarUrl.length > 0) {
          Image(this.currentUser.avatarUrl)
            .width(40)
            .height(40)
            .borderRadius(20)
            .objectFit(ImageFit.Cover);
        } else {
          Image($r('app.media.startIcon'))
            .width(40)
            .height(40)
            .borderRadius(20)
            .objectFit(ImageFit.Cover);
        }
        Text(this.currentUser && this.currentUser.displayName.length > 0 ?
          this.currentUser.displayName : '轨迹用户')
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.label_primary'));
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 8 })
      .alignItems(VerticalAlign.Center);

      Tabs({ barPosition: BarPosition.Start, index: this.currentTopIndex }) {
        TabContent() {
          this.MyTracksList();
        }
        .tabBar($r('app.string.tab_my_tracks'));

        TabContent() {
          this.AllTracksList();
        }
        .tabBar($r('app.string.tab_all_tracks'));
      }
      .barMode(BarMode.Fixed)
      .barHeight(44)
      .onChange((index: number) => {
        this.currentTopIndex = index;
      })
      .layoutWeight(1);
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.app_background'));
  }

  @Builder
  MyTracksList() {
    Column() {
      Row() {
        Blank();
        Button($r('app.string.home_new_track'))
          .fontSize(17)
          .fontColor($r('app.color.primary'))
          .backgroundColor(Color.Transparent)
          .height(36)
          .onClick(() => {
            router.pushUrl({ url: 'pages/CreateOrEditTrack' });
          });
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 8 });

      if (this.hasErrorMyTracks) {
        Column() {
          Text('网络异常，请检查后重试')
            .fontSize(15)
            .fontColor($r('app.color.label_secondary'));
          Button('重试')
            .fontSize(17)
            .fontColor($r('app.color.primary'))
            .backgroundColor(Color.Transparent)
            .margin({ top: 16 })
            .onClick(() => {
              this.hasErrorMyTracks = false;
              this.loadMyTracks();
            });
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center);
      } else if (this.isLoadingMyTracks) {
        Column() {
          Text('加载中…')
            .fontSize(15)
            .fontColor($r('app.color.label_tertiary'));
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center);
      } else if (this.myTracks.length > 0) {
        List({ space: 8 }) {
          ForEach(this.myTracks, (item: TrackModel.Track) => {
            ListItem() {
              Row() {
                Column({ space: 4 }) {
                  Text(item.title)
                    .fontSize(17)
                    .fontColor($r('app.color.label_primary'));
                  Text(item.status === 'done' ? '已完成' : '编辑中')
                    .fontSize(13)
                    .fontColor($r('app.color.label_tertiary'));
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1);
                Text('›')
                  .fontSize(20)
                  .fontColor($r('app.color.label_tertiary'));
              }
              .width('100%')
              .padding(16)
              .backgroundColor($r('app.color.card_background'))
              .borderRadius(12)
              .onClick(() => {
                router.pushUrl({
                  url: 'pages/TrackDetail',
                  params: { trackId: item.trackId, title: item.title }
                });
              });
            }
            .margin({ left: 16, right: 16 });
          }, (item: TrackModel.Track) => item.trackId);
        }
        .layoutWeight(1)
        .width('100%')
        .padding({ top: 8, bottom: 16 })
        .scrollBar(BarState.Off);
      } else {
        Column() {
          Text($r('app.string.empty_my_tracks_title'))
            .fontSize(17)
            .fontColor($r('app.color.label_primary'));
          Text($r('app.string.empty_my_tracks_hint'))
            .fontSize(14)
            .fontColor($r('app.color.empty_state_text'))
            .margin({ top: 8 })
            .textAlign(TextAlign.Center);
          Button($r('app.string.empty_my_tracks_action'))
            .fontSize(17)
            .fontColor($r('app.color.primary'))
            .backgroundColor(Color.Transparent)
            .margin({ top: 24 })
            .onClick(() => {
              router.pushUrl({ url: 'pages/CreateOrEditTrack' });
            });
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center);
      }
    }
    .width('100%')
    .height('100%');
  }

  @Builder
  AllTracksList() {
    Column() {
      Column() {
        Text($r('app.string.empty_all_tracks_title'))
          .fontSize(17)
          .fontColor($r('app.color.label_primary'));
        Text($r('app.string.empty_all_tracks_hint'))
          .fontSize(14)
          .fontColor($r('app.color.empty_state_text'))
          .margin({ top: 8 })
          .textAlign(TextAlign.Center);
      }
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center);
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.app_background'));
  }

  @Builder
  ProfileTabContent() {
    Column() {
      Column({ space: 12 }) {
        if (this.currentUser && this.currentUser.avatarUrl.length > 0) {
          Image(this.currentUser.avatarUrl)
            .width(72)
            .height(72)
            .borderRadius(36)
            .objectFit(ImageFit.Cover);
        } else {
          Image($r('app.media.startIcon'))
            .width(72)
            .height(72)
            .borderRadius(36)
            .objectFit(ImageFit.Cover);
        }
        Text(this.currentUser && this.currentUser.displayName.length > 0 ?
          this.currentUser.displayName : '轨迹用户')
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.label_primary'));
      }
      .padding({ top: 24, bottom: 24 });

      Column() {
        this.ProfileRow($r('app.string.profile_edit'), () => {
          router.pushUrl({ url: 'pages/ProfileEdit' });
        });
        this.ProfileRow($r('app.string.profile_about'), () => {
          router.pushUrl({ url: 'pages/About' });
        });
        this.ProfileRow($r('app.string.profile_privacy'), () => {
          router.pushUrl({ url: 'pages/PrivacyPolicy' });
        });
        Row() {
          Text($r('app.string.profile_logout'))
            .fontSize(17)
            .fontColor($r('app.color.destructive'));
          Blank();
        }
        .width('100%')
        .height(56)
        .padding({ left: 16, right: 16 })
        .onClick(() => {
          const ctx = this.getUIContext().getHostContext() as common.Context;
          AlertDialog.show({
            title: '退出帐号',
            message: '确定退出当前帐号？',
            primaryButton: { value: '取消', action: () => {} },
            secondaryButton: {
              value: '确定',
              fontColor: $r('app.color.destructive'),
              action: () => {
                // authentication.signOut();
                AuthStore.clearUser(ctx).then(() => {
                  router.replaceUrl({ url: 'pages/Login' });
                });
              }
            }
          });
        });
        Row() {
          Text($r('app.string.profile_delete_account'))
            .fontSize(17)
            .fontColor($r('app.color.destructive'));
          Blank();
        }
        .width('100%')
        .height(56)
        .padding({ left: 16, right: 16 })
        .onClick(() => {
          const ctx = this.getUIContext().getHostContext() as common.Context;
          AlertDialog.show({
            title: '注销账号',
            message: '注销后账号数据将无法恢复，确定继续？',
            primaryButton: { value: '取消', action: () => {} },
            secondaryButton: {
              value: '确定注销',
              fontColor: $r('app.color.destructive'),
              action: () => {
                // authentication.deleteUser().then(() => {
                //   hilog.info(LOG_DOMAIN, LOG_TAG, '账号已注销');
                //   AuthStore.clearUser(ctx).then(() => {
                //     router.replaceUrl({ url: 'pages/Login' });
                //   });
                // }).catch((err) => {
                //   hilog.error(LOG_DOMAIN, LOG_TAG, '注销失败: %{public}s', JSON.stringify(err));
                // });
                hilog.info(LOG_DOMAIN, LOG_TAG, '账号已注销（模拟）');
                AuthStore.clearUser(ctx).then(() => {
                  router.replaceUrl({ url: 'pages/Login' });
                });
              }
            }
          });
        });
      }
      .width('100%')
      .backgroundColor($r('app.color.card_background'))
      .borderRadius(12)
      .margin({ left: 16, right: 16 })
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start);
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.app_background'))
    .alignItems(HorizontalAlign.Center);
  }

  @Builder
  ProfileRow(title: ResourceStr, onClick: () => void) {
    Row() {
      Text(title)
        .fontSize(17)
        .fontColor($r('app.color.label_primary'));
      Blank();
      Text('›')
        .fontSize(20)
        .fontColor($r('app.color.label_tertiary'));
    }
    .width('100%')
    .height(56)
    .padding({ left: 16, right: 16 })
    .onClick(onClick);
  }

  build() {
    Tabs({ barPosition: BarPosition.End, index: this.currentBottomIndex }) {
      TabContent() {
        this.HomeTabContent();
      }
      .tabBar(this.TabBarItem(0, $r('app.string.tab_home')));

      TabContent() {
        this.ProfileTabContent();
      }
      .tabBar(this.TabBarItem(1, $r('app.string.tab_profile')));
    }
    .barMode(BarMode.Fixed)
    .barHeight(56)
    .barBackgroundColor($r('app.color.tab_bar_background'))
    .onChange((index: number) => {
      this.currentBottomIndex = index;
    })
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.app_background'));
  }

  @Builder
  TabBarItem(index: number, title: ResourceStr) {
    Column() {
      Text(title)
        .fontSize(10)
        .fontColor(this.currentBottomIndex === index ? $r('app.color.primary') : $r('app.color.label_tertiary'));
    }
    .padding({ top: 6, bottom: 6 })
    .layoutWeight(1);
  }
}
