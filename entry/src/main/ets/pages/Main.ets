import { promptAction } from '@kit.ArkUI';
import { window } from '@kit.ArkUI';
import { common, abilityAccessCtrl } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { TrackStore } from '../common/TrackStore';
import { TrackModel } from '../common/TrackModel';
import { AuthStore, AuthUser } from '../common/AuthStore';
import { SyncService } from '../common/SyncService';
import { Config } from '../common/Config';

const LOG_DOMAIN = 0x0000;
const LOG_TAG = 'Main';
/** 我的轨迹列表每页条数，支持分页加载更多 */
const MY_TRACKS_PAGE_SIZE = 20;

interface PermissionRequestResult {
  authResults: number[];
}

/**
 * P1-0 首页（顶部 Tab：我的轨迹 | 公开轨迹）+ P3-1 个人中心
 */
@Entry
@Component
struct Main {
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafeHeight: number = 0;
  @State currentBottomIndex: number = 0;
  @State currentTopIndex: number = 0;
  @State myTracks: TrackModel.Track[] = [];
  @State myTracksDisplayCount: number = MY_TRACKS_PAGE_SIZE;
  @State publicTracks: TrackModel.Track[] = [];
  @State publicTracksDisplayCount: number = MY_TRACKS_PAGE_SIZE;
  @State isLoading: boolean = false;
  @State currentUser: AuthUser | null = null;
  /** 缓存窗口实例，避免每次切换 Tab 都异步获取 */
  private cachedWindow: window.Window | null = null;

  aboutToAppear(): void {
    this.loadAllData();
    // 提前缓存窗口实例
    this.cacheWindowInstance();
  }

  onPageShow(): void {
    this.loadAllData();
    // 恢复当前 Tab 对应的状态栏颜色（从其他页面返回时）
    this.updateStatusBarColor(this.currentBottomIndex);
  }

  onPageHide(): void {
    // 离开 Main 页面时（进入子页面），将状态栏重置为白底黑字
    this.updateStatusBarColor(0);
  }

  /** 提前获取并缓存窗口实例 */
  private cacheWindowInstance(): void {
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      window.getLastWindow(ctx).then((win: window.Window) => {
        this.cachedWindow = win;
      }).catch((e: BusinessError) => {
        hilog.warn(LOG_DOMAIN, LOG_TAG, 'cacheWindow: %{public}s', JSON.stringify(e));
      });
    } catch (e) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'cacheWindowInstance: %{public}s', JSON.stringify(e));
    }
  }

  /**
   * 沉浸式状态栏：背景始终透明，只切换内容颜色（时间/电量/信号图标的黑白）
   * - 首页（白色背景）→ 黑色内容
   * - 个人中心（蓝色渐变头部）→ 白色内容
   */
  private updateStatusBarColor(tabIndex: number): void {
    // 只切换 statusBarContentColor，不动背景色（始终透明）
    const contentColor: string = tabIndex === 1 ? '#FFFFFFFF' : '#FF000000';
    const props: window.SystemBarProperties = {
      statusBarContentColor: contentColor
    };
    if (this.cachedWindow) {
      this.cachedWindow.setWindowSystemBarProperties(props).catch((e: BusinessError) => {
        hilog.warn(LOG_DOMAIN, LOG_TAG, 'setStatusBar: %{public}s', JSON.stringify(e));
      });
    } else {
      // 兜底：缓存尚未就绪时重新获取
      try {
        const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
        window.getLastWindow(ctx).then((win: window.Window) => {
          this.cachedWindow = win;
          win.setWindowSystemBarProperties(props).catch((e: BusinessError) => {
            hilog.warn(LOG_DOMAIN, LOG_TAG, 'setStatusBar: %{public}s', JSON.stringify(e));
          });
        }).catch((e: BusinessError) => {
          hilog.warn(LOG_DOMAIN, LOG_TAG, 'getLastWindow: %{public}s', JSON.stringify(e));
        });
      } catch (e) {
        hilog.warn(LOG_DOMAIN, LOG_TAG, 'updateStatusBarColor: %{public}s', JSON.stringify(e));
      }
    }
  }

  private loadAllData(): void {
    this.isLoading = true;
    const context = this.getUIContext().getHostContext() as common.Context;

    AuthStore.getCurrentUser(context).then(async (user: AuthUser | null) => {
      this.currentUser = user;
      let tracks: TrackModel.Track[] = await TrackStore.getTracks(context);
      let myTracks: TrackModel.Track[] = user
        ? tracks.filter((t: TrackModel.Track) => t.ownerUserId === user.userId)
        : tracks;
      // 重装后本地为空时，从云端恢复「我的轨迹」
      if (user && myTracks.length === 0) {
        await SyncService.restoreMyTracksFromCloud(context);
        tracks = await TrackStore.getTracks(context);
        myTracks = tracks.filter((t: TrackModel.Track) => t.ownerUserId === user.userId);
      }
      this.myTracks = myTracks;
      this.myTracksDisplayCount = Math.min(MY_TRACKS_PAGE_SIZE, myTracks.length);
      this.publicTracks = tracks.filter((t: TrackModel.Track) =>
        t.visibility === TrackModel.VISIBILITY_PUBLIC && t.status === TrackModel.TRACK_STATUS_DONE
      );
      this.publicTracksDisplayCount = Math.min(MY_TRACKS_PAGE_SIZE, this.publicTracks.length);
      this.isLoading = false;

      // 进入首页时，后台同步本地数据到云端
      SyncService.syncAll(context).catch((e: Error) => {
        hilog.warn(LOG_DOMAIN, LOG_TAG, 'Background sync: %{public}s', JSON.stringify(e));
      });
    }).catch(() => {
      this.isLoading = false;
    });
  }

  /** 计算统计 */
  private getTrackCount(): number {
    return this.myTracks.length;
  }

  private getSpotCount(): number {
    let count = 0;
    for (let i = 0; i < this.myTracks.length; i++) {
      count += this.myTracks[i].spotCount || 0;
    }
    return count;
  }

  private getTotalDistance(): string {
    let total = 0;
    for (let i = 0; i < this.myTracks.length; i++) {
      total += this.myTracks[i].totalDistance;
    }
    return TrackModel.formatDistance(total);
  }

  /** 首页创建轨迹前强制申请定位权限；未授权则不允许进入 */
  private requestPermissionsAndGoCreate(): void {
    try {
      const atManager = abilityAccessCtrl.createAtManager();
      const context = this.getUIContext().getHostContext() as common.Context;
      atManager.requestPermissionsFromUser(context, [
        'ohos.permission.LOCATION',
        'ohos.permission.APPROXIMATELY_LOCATION'
      ]).then((data: PermissionRequestResult) => {
        const authResults = data.authResults;
        let allGranted = true;
        if (authResults && authResults.length > 0) {
          for (let i = 0; i < authResults.length; i++) {
            if (authResults[i] !== 0) {
              allGranted = false;
              break;
            }
          }
        }
        if (allGranted) {
          this.getUIContext().getRouter().pushUrl({ url: 'pages/CreateOrEditTrack' });
          return;
        }
        this.getUIContext().getPromptAction().showDialog({
          message: '未获得定位权限，无法创建轨迹。请先在系统设置中允许定位权限。',
          buttons: [{ text: '知道了', color: $r('app.color.primary') }]
        }).catch(() => {});
      }).catch((_e: BusinessError) => {
        this.getUIContext().getPromptAction().showDialog({
          message: '定位权限申请失败，无法创建轨迹。',
          buttons: [{ text: '知道了', color: $r('app.color.primary') }]
        }).catch(() => {});
      });
    } catch (_e) {
      this.getUIContext().getPromptAction().showDialog({
        message: '定位权限申请异常，无法创建轨迹。',
        buttons: [{ text: '知道了', color: $r('app.color.primary') }]
      }).catch(() => {});
    }
  }

  build() {
    Tabs({ barPosition: BarPosition.End, index: this.currentBottomIndex }) {
      TabContent() {
        this.HomeTabContent();
      }
      .tabBar(this.BottomTabItem(0, '首页', $r('app.media.ic_tab_home')));

      TabContent() {
        this.ProfileTabContent();
      }
      .tabBar(this.BottomTabItem(1, '个人中心', $r('app.media.ic_tab_profile')));
    }
    .barMode(BarMode.Fixed)
    .barHeight(56 + this.bottomSafeHeight)
    .barBackgroundColor($r('app.color.tab_bar_background'))
    .onChange((index: number) => {
      this.currentBottomIndex = index;
      this.updateStatusBarColor(index);
    })
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.app_background'));
  }

  // ==================== 首页 Tab ====================
  @Builder
  HomeTabContent() {
    Column() {
      // 状态栏占位 + 标题区（白色背景）
      Column() {
        Row()
          .width('100%')
          .height(this.statusBarHeight);
        Row({ space: 12 }) {
          Text($r('app.string.app_name'))
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.label_primary'));
          Blank();
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 12, bottom: 4 });
      }
      .width('100%')
      .backgroundColor(Color.White);

      // 顶部 Tab 切换
      Tabs({ barPosition: BarPosition.Start, index: this.currentTopIndex }) {
        TabContent() {
          this.MyTracksList();
        }
        .tabBar(this.TopTabItem(0, $r('app.string.tab_my_tracks')));

        TabContent() {
          this.PublicTracksList();
        }
        .tabBar(this.TopTabItem(1, $r('app.string.tab_all_tracks')));
      }
      .barMode(BarMode.Fixed)
      .barHeight(44)
      .barOverlap(false)
      .barBackgroundColor(Color.White)
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
  TopTabItem(index: number, title: string | Resource) {
    Column() {
      Text(title)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.currentTopIndex === index ? $r('app.color.primary') : $r('app.color.label_tertiary'));
      // 始终渲染指示线，未选中时透明，避免布局抖动
      Column()
        .width(24)
        .height(3)
        .backgroundColor($r('app.color.primary'))
        .borderRadius(1.5)
        .margin({ top: 6 })
        .opacity(this.currentTopIndex === index ? 1 : 0);
    }
    .padding({ top: 8, bottom: 4 });
  }

  @Builder
  BottomTabItem(index: number, title: string, icon: Resource) {
    Column({ space: 4 }) {
      Image(icon)
        .width(24)
        .height(24)
        .objectFit(ImageFit.Contain)
        .fillColor(this.currentBottomIndex === index ? $r('app.color.primary') : $r('app.color.label_tertiary'));
      Text(title)
        .fontSize(11)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.currentBottomIndex === index ? $r('app.color.primary') : $r('app.color.label_tertiary'));
    }
    .padding({ top: 6, bottom: 6 })
    .layoutWeight(1)
    .constraintSize({ minHeight: 48 });
  }

  // ==================== 我的轨迹列表 ====================
  @Builder
  MyTracksList() {
    Column() {
      if (this.myTracks.length > 0) {
        List({ space: 12 }) {
          // 新建按钮
          ListItem() {
            Row({ space: 6 }) {
              Image($r('app.media.ic_plus'))
                .width(18)
                .height(18)
                .fillColor($r('app.color.accent'));
              Text($r('app.string.main_new_track_btn'))
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.accent_dark'));
            }
            .width('100%')
            .height(48)
            .justifyContent(FlexAlign.Center)
            .backgroundColor($r('app.color.accent_light'))
            .borderRadius(12)
            .borderWidth(2)
            .borderColor($r('app.color.accent'))
            .borderStyle(BorderStyle.Dashed)
            .onClick(() => {
              this.requestPermissionsAndGoCreate();
            });
          }
          .margin({ left: 16, right: 16, top: 12 });

          // 轨迹卡片列表（分页展示，避免一次渲染过多）
          ForEach(this.myTracks.slice(0, this.myTracksDisplayCount), (item: TrackModel.Track) => {
            ListItem() {
              this.TrackCard(item);
            }
            .margin({ left: 16, right: 16 });
          }, (item: TrackModel.Track) => item.trackId);

          // 加载更多
          if (this.myTracksDisplayCount < this.myTracks.length) {
            ListItem() {
              Row() {
                Text('加载更多（' + (this.myTracks.length - this.myTracksDisplayCount).toString() + ' 条）')
                  .fontSize(14)
                  .fontColor($r('app.color.primary'));
              }
              .width('100%')
              .height(48)
              .justifyContent(FlexAlign.Center)
              .onClick(() => {
                this.myTracksDisplayCount = Math.min(
                  this.myTracksDisplayCount + MY_TRACKS_PAGE_SIZE,
                  this.myTracks.length
                );
              });
            }
            .margin({ left: 16, right: 16 });
          }
          // 底部间距占位（随列表滚动，不固定遮挡）
          ListItem() {
            Row().height(4);
          }
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true });
      } else {
        // 空状态
        Column({ space: 12 }) {
          Image($r('app.media.ic_location_pin'))
            .width(48)
            .height(48)
            .fillColor($r('app.color.primary'));
          Text($r('app.string.empty_my_tracks_title'))
            .fontSize(17)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.label_primary'));
          Text($r('app.string.empty_my_tracks_hint'))
            .fontSize(14)
            .fontColor($r('app.color.label_tertiary'))
            .textAlign(TextAlign.Center)
            .lineHeight(22);
          Button($r('app.string.empty_my_tracks_action'))
            .fontSize(17)
            .fontWeight(FontWeight.Medium)
            .fontColor(Color.White)
            .backgroundColor($r('app.color.primary'))
            .height(48)
            .padding({ left: 32, right: 32 })
            .borderRadius(24)
            .margin({ top: 8 })
            .onClick(() => {
              this.requestPermissionsAndGoCreate();
            });
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .width('100%');
      }
    }
    .width('100%')
    .height('100%');
  }

  @Builder
  StatsItem(value: string, label: string) {
    Column({ space: 2 }) {
      Text(value)
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White);
      Text(label)
        .fontSize(11)
        .fontColor($r('app.color.login_button_secondary'));
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center);
  }

  @Builder
  TrackCard(item: TrackModel.Track) {
    Column() {
      // 封面图（如有）
      if (item.coverImageUrl.length > 0) {
        Image(item.coverImageUrl)
          .width('100%')
          .height(140)
          .objectFit(ImageFit.Cover)
          .borderRadius({ topLeft: 12, topRight: 12 })
          .alt($r('app.color.separator'));
      }

      Column() {
        Row({ space: 8 }) {
          Text(item.title)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.label_primary'))
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis });
          if (item.status === TrackModel.TRACK_STATUS_DONE) {
            Text($r('app.string.status_done'))
              .fontSize(11)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.success'))
              .backgroundColor($r('app.color.success_light'))
              .padding({ left: 8, right: 8, top: 2, bottom: 2 })
              .borderRadius(10);
          } else {
            Text($r('app.string.status_editing'))
              .fontSize(11)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.warning'))
              .backgroundColor($r('app.color.warning_light'))
              .padding({ left: 8, right: 8, top: 2, bottom: 2 })
              .borderRadius(10);
          }
        }
        .width('100%');

        Text(TrackModel.formatDate(item.createdAt))
          .fontSize(12)
          .fontColor($r('app.color.label_tertiary'))
          .margin({ top: 4 });

        if (item.description.length > 0) {
          Text(item.description)
            .fontSize(13)
            .fontColor($r('app.color.label_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 4 });
        }

        Row({ space: 16 }) {
          Row({ space: 4 }) {
            Image($r('app.media.ic_location_pin'))
              .width(14)
              .height(14)
              .fillColor($r('app.color.label_secondary'));
            Text(TrackModel.formatDistance(item.totalDistance))
              .fontSize(12)
              .fontColor($r('app.color.label_secondary'));
          }
          if (item.maxAltitude > 0) {
            Row({ space: 4 }) {
              Image($r('app.media.ic_mountain'))
                .width(14)
                .height(14)
                .fillColor($r('app.color.label_secondary'));
              Text(item.maxAltitude.toString() + 'm')
                .fontSize(12)
                .fontColor($r('app.color.label_secondary'));
            }
          }
          if (item.totalDuration > 0) {
            Row({ space: 4 }) {
              Image($r('app.media.ic_timer'))
                .width(14)
                .height(14)
                .fillColor($r('app.color.label_secondary'));
              Text(TrackModel.formatDuration(item.totalDuration))
                .fontSize(12)
                .fontColor($r('app.color.label_secondary'));
            }
          }
        }
        .width('100%')
        .margin({ top: 8 });
      }
      .width('100%')
      .padding(item.coverImageUrl.length > 0 ? { left: 16, right: 16, top: 12, bottom: 16 } :
        { left: 16, right: 16, top: 16, bottom: 16 });
    }
    .width('100%')
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(12)
    .shadow({ radius: 4, color: $r('app.color.shadow_light'), offsetX: 0, offsetY: 2 })
    .clip(true)
    .onClick(() => {
      this.getUIContext().getRouter().pushUrl({
        url: 'pages/TrackDetail',
        params: { trackId: item.trackId, title: item.title }
      });
    });
  }

  // ==================== 公开轨迹列表 ====================
  @Builder
  PublicTracksList() {
    Column() {
      if (this.publicTracks.length > 0) {
        List({ space: 12 }) {
          ForEach(this.publicTracks.slice(0, this.publicTracksDisplayCount), (item: TrackModel.Track, index: number) => {
            ListItem() {
              this.PublicTrackCard(item);
            }
            .margin({ left: 16, right: 16, top: index === 0 ? 12 : 0 });
          }, (item: TrackModel.Track) => item.trackId);
          if (this.publicTracksDisplayCount < this.publicTracks.length) {
            ListItem() {
              Row() {
                Text('加载更多（' + (this.publicTracks.length - this.publicTracksDisplayCount).toString() + ' 条）')
                  .fontSize(14)
                  .fontColor($r('app.color.primary'));
              }
              .width('100%')
              .height(48)
              .justifyContent(FlexAlign.Center)
              .onClick(() => {
                this.publicTracksDisplayCount = Math.min(
                  this.publicTracksDisplayCount + MY_TRACKS_PAGE_SIZE,
                  this.publicTracks.length
                );
              });
            }
            .margin({ left: 16, right: 16 });
          }
          // 底部间距占位（随列表滚动，不固定遮挡）
          ListItem() {
            Row().height(4);
          }
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true });
      } else {
        Column({ space: 12 }) {
          Image($r('app.media.ic_globe'))
            .width(48)
            .height(48)
            .fillColor($r('app.color.primary'));
          Text($r('app.string.empty_all_tracks_title'))
            .fontSize(17)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.label_primary'));
          Text($r('app.string.empty_all_tracks_hint'))
            .fontSize(14)
            .fontColor($r('app.color.label_tertiary'));
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .width('100%');
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.app_background'));
  }

  @Builder
  PublicTrackCard(item: TrackModel.Track) {
    Column() {
      Row({ space: 8 }) {
        Text(item.title)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.label_primary'))
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
        Text($r('app.string.visibility_public'))
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.primary'))
          .backgroundColor($r('app.color.menu_selected_bg'))
          .padding({ left: 8, right: 8, top: 2, bottom: 2 })
          .borderRadius(10);
      }
      .width('100%');

      // 作者信息
      Row({ space: 4 }) {
        Image($r('app.media.ic_user'))
          .width(12)
          .height(12)
          .fillColor($r('app.color.label_secondary'));
        Text(item.ownerDisplayName && item.ownerDisplayName.length > 0 ? item.ownerDisplayName : $r('app.string.profile_default_user'))
          .fontSize(12)
          .fontColor($r('app.color.label_secondary'));
        Text('·')
          .fontSize(12)
          .fontColor($r('app.color.label_tertiary'));
        Text(TrackModel.formatDate(item.createdAt))
          .fontSize(12)
          .fontColor($r('app.color.label_tertiary'));
      }
      .width('100%')
      .margin({ top: 4 });

      if (item.description.length > 0) {
        Text(item.description)
          .fontSize(13)
          .fontColor($r('app.color.label_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 4 });
      }

      Row({ space: 16 }) {
        Row({ space: 4 }) {
          Image($r('app.media.ic_location_pin'))
            .width(14)
            .height(14)
            .fillColor($r('app.color.label_secondary'));
          Text(TrackModel.formatDistance(item.totalDistance))
            .fontSize(12)
            .fontColor($r('app.color.label_secondary'));
        }
        if (item.spotCount > 0) {
          Row({ space: 4 }) {
            Image($r('app.media.ic_flag_finish'))
              .width(14)
              .height(14)
              .fillColor($r('app.color.label_secondary'));
            Text(item.spotCount.toString() + '个打卡点')
              .fontSize(12)
              .fontColor($r('app.color.label_secondary'));
          }
        }
        if (item.maxAltitude > 0) {
          Row({ space: 4 }) {
            Image($r('app.media.ic_mountain'))
              .width(14)
              .height(14)
              .fillColor($r('app.color.label_secondary'));
            Text(item.maxAltitude.toString() + 'm')
              .fontSize(12)
              .fontColor($r('app.color.label_secondary'));
          }
        }
      }
      .width('100%')
      .margin({ top: 8 });
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(12)
    .shadow({ radius: 4, color: $r('app.color.shadow_light'), offsetX: 0, offsetY: 2 })
    .onClick(() => {
      this.getUIContext().getRouter().pushUrl({
        url: 'pages/TrackDetail',
        params: { trackId: item.trackId, title: item.title, isPublicView: true }
      });
    });
  }

  // ==================== 个人中心 ====================
  @Builder
  ProfileTabContent() {
    Column() {
      // 头部
      Column({ space: 12 }) {
        if (this.currentUser && this.currentUser.avatarUrl.length > 0) {
          Image(this.currentUser.avatarUrl)
            .width(72)
            .height(72)
            .borderRadius(36)
            .objectFit(ImageFit.Cover);
        } else {
          Column() {
            Image($r('app.media.ic_user'))
              .width(36)
              .height(36)
              .fillColor(Color.White);
          }
          .width(72)
          .height(72)
          .borderRadius(36)
          .backgroundColor($r('app.color.menu_item_inactive'))
          .justifyContent(FlexAlign.Center);
        }
        Text(this.currentUser && this.currentUser.displayName.length > 0 ?
          this.currentUser.displayName : $r('app.string.profile_default_user'))
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White);
        if (this.currentUser && this.currentUser.familyName.length > 0) {
          Text(this.currentUser.familyName)
            .fontSize(13)
            .fontColor($r('app.color.login_title_secondary'));
        }

        // 统计
        Row() {
          Column({ space: 2 }) {
            Text(this.getTrackCount().toString())
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
              .fontColor(Color.White);
            Text($r('app.string.main_stat_tracks'))
              .fontSize(11)
              .fontColor($r('app.color.login_button_secondary'));
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Center);

          Column().width(1).height(30).backgroundColor($r('app.color.menu_divider'));

          Column({ space: 2 }) {
            Text(this.getSpotCount().toString())
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
              .fontColor(Color.White);
            Text($r('app.string.main_stat_spots'))
              .fontSize(11)
              .fontColor($r('app.color.login_button_secondary'));
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Center);

          Column().width(1).height(30).backgroundColor($r('app.color.menu_divider'));

          Column({ space: 2 }) {
            Text(this.getTotalDistance())
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
              .fontColor(Color.White);
            Text($r('app.string.main_stat_total_distance'))
              .fontSize(11)
              .fontColor($r('app.color.login_button_secondary'));
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Center);
        }
        .width('100%')
        .padding(12)
        .backgroundColor($r('app.color.icon_overlay_light'))
        .borderRadius(12)
        .margin({ top: 8 });
        }
        .width('100%')
        .padding({ top: 16 + this.statusBarHeight, bottom: 24, left: 20, right: 20 })
        .linearGradient({
          angle: 160,
          colors: [[$r('app.color.primary'), 0], [$r('app.color.primary_dark'), 0.5], [$r('app.color.gradient_end'), 1]]
        })
        .alignItems(HorizontalAlign.Center);

        // 菜单
        Column({ space: 12 }) {
        Column() {
          this.MenuItem($r('app.media.ic_user'), $r('app.string.menu_edit_profile'), '', $r('app.color.primary'), () => {
            this.getUIContext().getRouter().pushUrl({ url: 'pages/ProfileEdit' });
          });
        }
        .backgroundColor($r('app.color.card_background'))
        .borderRadius(12)
        .shadow({ radius: 4, color: $r('app.color.shadow_light'), offsetX: 0, offsetY: 2 });

        Column() {
          this.MenuItem($r('app.media.ic_lock'), '隐私设置', '', $r('app.color.menu_icon_sky'), () => {
            this.getUIContext().getRouter().pushUrl({ url: 'pages/PrivacySettings' });
          });
          Divider().color($r('app.color.separator')).margin({ left: 56, right: 16 });
          this.MenuItem($r('app.media.ic_info'), $r('app.string.menu_about'), 'V1.0', $r('app.color.primary'), () => {
            this.getUIContext().getRouter().pushUrl({ url: 'pages/About' });
          });
          Divider().color($r('app.color.separator')).margin({ left: 56, right: 16 });
          this.MenuItem($r('app.media.ic_chat'), $r('app.string.menu_feedback'), '', $r('app.color.accent'), () => {
            this.getUIContext().getRouter().pushUrl({ url: 'pages/Feedback' });
          });
          if (Config.IS_DEVELOPMENT_MODE) {
            Divider().color($r('app.color.separator')).margin({ left: 56, right: 16 });
            this.MenuItem($r('app.media.ic_tool'), '测试入口', '', $r('app.color.warning'), () => {
              this.getUIContext().getRouter().pushUrl({ url: 'pages/TestLab' });
            });
          }
        }
        .backgroundColor($r('app.color.card_background'))
        .borderRadius(12)
        .shadow({ radius: 4, color: $r('app.color.shadow_light'), offsetX: 0, offsetY: 2 });

        Button($r('app.string.profile_logout'))
          .width('100%')
          .height(48)
          .fontSize(15)
          .fontColor($r('app.color.destructive'))
          .backgroundColor($r('app.color.card_background'))
          .borderRadius(12)
          .shadow({ radius: 4, color: $r('app.color.shadow_light'), offsetX: 0, offsetY: 2 })
          .onClick(() => {
            this.getUIContext().getPromptAction().showDialog({
              message: $r('app.string.confirm_logout'),
              buttons: [
                { text: $r('app.string.dialog_cancel'), color: $r('app.color.dialog_secondary_text') },
                { text: $r('app.string.dialog_confirm'), color: $r('app.color.destructive') }
              ]
            }).then((result: promptAction.ShowDialogSuccessResponse) => {
              if (result.index === 1) {
                const ctx = this.getUIContext().getHostContext() as common.Context;
                AuthStore.clearUser(ctx).then(() => {
                  this.getUIContext().getRouter().replaceUrl({ url: 'pages/Login' });
                });
              }
            }).catch(() => {});
          });
        }
        .width('100%')
        .padding(16)
        .layoutWeight(1);
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.app_background'));
  }

  @Builder
  MenuItem(icon: Resource, title: string | Resource, value: string, iconBgColor: string | Resource, onClick: () => void) {
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
        .fontColor($r('app.color.label_primary'))
        .layoutWeight(1)
        .margin({ left: 12 });
      if (value.length > 0) {
        Text(value)
          .fontSize(13)
          .fontColor($r('app.color.label_tertiary'))
          .margin({ right: 8 });
      }
      Image($r('app.media.ic_arrow_right'))
        .width(16)
        .height(16)
        .fillColor($r('app.color.label_tertiary'));
    }
    .width('100%')
    .height(52)
    .padding({ left: 16, right: 16 })
    .onClick(onClick);
  }
}
