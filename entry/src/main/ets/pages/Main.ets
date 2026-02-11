import { promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { TrackStore } from '../common/TrackStore';
import { TrackModel } from '../common/TrackModel';
import { AuthStore, AuthUser } from '../common/AuthStore';
import { SyncService } from '../common/SyncService';
import { CloudDBService } from '../common/CloudDBService';

const LOG_DOMAIN = 0x0000;
const LOG_TAG = 'Main';
/** 我的轨迹列表每页条数，支持分页加载更多 */
const MY_TRACKS_PAGE_SIZE = 20;

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
  @State diagResult: string = '';
  @State isDiagnosing: boolean = false;

  aboutToAppear(): void {
    this.loadAllData();
  }

  onPageShow(): void {
    this.loadAllData();
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

  build() {
    Tabs({ barPosition: BarPosition.End, index: this.currentBottomIndex }) {
      TabContent() {
        this.HomeTabContent();
      }
      .tabBar(this.BottomTabItem(0, '首页', '🏠'));

      TabContent() {
        this.ProfileTabContent();
      }
      .tabBar(this.BottomTabItem(1, '个人中心', '👤'));
    }
    .barMode(BarMode.Fixed)
    .barHeight(56 + this.bottomSafeHeight)
    .barBackgroundColor($r('app.color.tab_bar_background'))
    .onChange((index: number) => {
      this.currentBottomIndex = index;
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
          Text('遨游轨迹')
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
        .tabBar(this.TopTabItem(0, '我的轨迹'));

        TabContent() {
          this.PublicTracksList();
        }
        .tabBar(this.TopTabItem(1, '公开轨迹'));
      }
      .barMode(BarMode.Fixed)
      .barHeight(44)
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
  TopTabItem(index: number, title: string) {
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
  BottomTabItem(index: number, title: string, icon: string) {
    Column({ space: 2 }) {
      Text(icon)
        .fontSize(22);
      Text(title)
        .fontSize(10)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.currentBottomIndex === index ? $r('app.color.primary') : $r('app.color.label_tertiary'));
    }
    .padding({ top: 6, bottom: 6 })
    .layoutWeight(1);
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
              Text('+')
                .fontSize(18)
                .fontColor($r('app.color.primary'));
              Text('新建扫墓轨迹')
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.primary'));
            }
            .width('100%')
            .height(48)
            .justifyContent(FlexAlign.Center)
            .backgroundColor($r('app.color.card_background'))
            .borderRadius(12)
            .borderWidth(2)
            .borderColor($r('app.color.primary'))
            .borderStyle(BorderStyle.Dashed)
            .onClick(() => {
              this.getUIContext().getRouter().pushUrl({ url: 'pages/CreateOrEditTrack' });
            });
          }
          .margin({ left: 16, right: 16 });

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
        }
        .layoutWeight(1)
        .width('100%')
        .padding({ top: 12, bottom: 16 })
        .scrollBar(BarState.Off);
      } else {
        // 空状态
        Column({ space: 12 }) {
          Text('📍')
            .fontSize(48);
          Text('还没有轨迹')
            .fontSize(17)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.label_primary'));
          Text('点击下方按钮创建第一条扫墓轨迹\n记录祖先墓地位置，让后代也能找到')
            .fontSize(14)
            .fontColor($r('app.color.label_tertiary'))
            .textAlign(TextAlign.Center)
            .lineHeight(22);
          Button('创建第一条轨迹')
            .fontSize(17)
            .fontWeight(FontWeight.Medium)
            .fontColor(Color.White)
            .backgroundColor($r('app.color.primary'))
            .height(48)
            .padding({ left: 32, right: 32 })
            .borderRadius(24)
            .margin({ top: 8 })
            .onClick(() => {
              this.getUIContext().getRouter().pushUrl({ url: 'pages/CreateOrEditTrack' });
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
        .fontColor('#CCFFFFFF');
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
            Text('已完成')
              .fontSize(11)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.success'))
              .backgroundColor($r('app.color.success_light'))
              .padding({ left: 8, right: 8, top: 2, bottom: 2 })
              .borderRadius(10);
          } else {
            Text('编辑中')
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
          Text('📍 ' + TrackModel.formatDistance(item.totalDistance))
            .fontSize(12)
            .fontColor($r('app.color.label_secondary'));
          if (item.maxAltitude > 0) {
            Text('⛰ ' + item.maxAltitude.toString() + 'm')
              .fontSize(12)
              .fontColor($r('app.color.label_secondary'));
          }
          if (item.totalDuration > 0) {
            Text('⏱ ' + TrackModel.formatDuration(item.totalDuration))
              .fontSize(12)
              .fontColor($r('app.color.label_secondary'));
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
    .shadow({ radius: 4, color: '#0D000000', offsetX: 0, offsetY: 2 })
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
          ForEach(this.publicTracks.slice(0, this.publicTracksDisplayCount), (item: TrackModel.Track) => {
            ListItem() {
              this.PublicTrackCard(item);
            }
            .margin({ left: 16, right: 16 });
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
        }
        .layoutWeight(1)
        .width('100%')
        .padding({ top: 12, bottom: 16 })
        .scrollBar(BarState.Off);
      } else {
        Column({ space: 12 }) {
          Text('🌍')
            .fontSize(48);
          Text('暂无公开轨迹')
            .fontSize(17)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.label_primary'));
          Text('将你的轨迹设为公开，让更多人看到')
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
        Text('公开')
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor('#3478F6')
          .backgroundColor('#EEF3FF')
          .padding({ left: 8, right: 8, top: 2, bottom: 2 })
          .borderRadius(10);
      }
      .width('100%');

      // 作者信息
      Row({ space: 4 }) {
        Text('👤')
          .fontSize(11);
        Text(item.ownerDisplayName && item.ownerDisplayName.length > 0 ? item.ownerDisplayName : '轨迹用户')
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
        Text('📍 ' + TrackModel.formatDistance(item.totalDistance))
          .fontSize(12)
          .fontColor($r('app.color.label_secondary'));
        if (item.spotCount > 0) {
          Text('🏁 ' + item.spotCount.toString() + '个打卡点')
            .fontSize(12)
            .fontColor($r('app.color.label_secondary'));
        }
        if (item.maxAltitude > 0) {
          Text('⛰ ' + item.maxAltitude.toString() + 'm')
            .fontSize(12)
            .fontColor($r('app.color.label_secondary'));
        }
      }
      .width('100%')
      .margin({ top: 8 });
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(12)
    .shadow({ radius: 4, color: '#0D000000', offsetX: 0, offsetY: 2 })
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
            Text('👤')
              .fontSize(32);
          }
          .width(72)
          .height(72)
          .borderRadius(36)
          .backgroundColor('#E8E8ED')
          .justifyContent(FlexAlign.Center);
        }
        Text(this.currentUser && this.currentUser.displayName.length > 0 ?
          this.currentUser.displayName : '轨迹用户')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White);
        if (this.currentUser && this.currentUser.familyName.length > 0) {
          Text(this.currentUser.familyName)
            .fontSize(13)
            .fontColor('#BBFFFFFF');
        }

        // 统计
        Row() {
          Column({ space: 2 }) {
            Text(this.getTrackCount().toString())
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
              .fontColor(Color.White);
            Text('轨迹')
              .fontSize(11)
              .fontColor('#AAFFFFFF');
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Center);

          Column().width(1).height(30).backgroundColor('#33FFFFFF');

          Column({ space: 2 }) {
            Text(this.getSpotCount().toString())
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
              .fontColor(Color.White);
            Text('打卡点')
              .fontSize(11)
              .fontColor('#AAFFFFFF');
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Center);

          Column().width(1).height(30).backgroundColor('#33FFFFFF');

          Column({ space: 2 }) {
            Text(this.getTotalDistance())
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
              .fontColor(Color.White);
            Text('总里程')
              .fontSize(11)
              .fontColor('#AAFFFFFF');
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Center);
        }
        .width('100%')
        .padding(12)
        .backgroundColor('#22FFFFFF')
        .borderRadius(12)
        .margin({ top: 8 });
      }
      .width('100%')
      .padding({ top: 16 + this.statusBarHeight, bottom: 24, left: 20, right: 20 })
      .linearGradient({
        angle: 160,
        colors: [['#3478F6', 0], ['#1E56CC', 0.5], ['#0D3BA8', 1]]
      })
      .alignItems(HorizontalAlign.Center);

      // 菜单
      Column({ space: 12 }) {
        Column() {
          this.MenuItem('👤', '编辑个人信息', '', '#3478F6', () => {
            this.getUIContext().getRouter().pushUrl({ url: 'pages/ProfileEdit' });
          });
        }
        .backgroundColor($r('app.color.card_background'))
        .borderRadius(12)
        .shadow({ radius: 4, color: '#0D000000', offsetX: 0, offsetY: 2 });

        Column() {
          this.MenuItem('📄', '隐私政策', '', '#34C759', () => {
            this.getUIContext().getRouter().pushUrl({ url: 'pages/PrivacyPolicy' });
          });
          Divider().color($r('app.color.separator')).margin({ left: 56, right: 16 });
          this.MenuItem('📋', '用户协议', '', '#34C759', () => {
            this.getUIContext().getRouter().pushUrl({ url: 'pages/UserAgreement' });
          });
          Divider().color($r('app.color.separator')).margin({ left: 56, right: 16 });
          this.MenuItem('ℹ', '关于遨游轨迹', 'V1.0', '#5856D6', () => {
            this.getUIContext().getRouter().pushUrl({ url: 'pages/About' });
          });
          Divider().color($r('app.color.separator')).margin({ left: 56, right: 16 });
          this.MenuItem('💬', '意见反馈', '', '#FF3B30', () => {
            this.getUIContext().getRouter().pushUrl({ url: 'pages/Feedback' });
          });
        }
        .backgroundColor($r('app.color.card_background'))
        .borderRadius(12)
        .shadow({ radius: 4, color: '#0D000000', offsetX: 0, offsetY: 2 });

        // 开发调试：Cloud DB 诊断
        Column({ space: 8 }) {
          Button(this.isDiagnosing ? '诊断中...' : '🔧 诊断 Cloud DB 连通性')
            .width('100%')
            .height(48)
            .fontSize(14)
            .fontColor('#3478F6')
            .backgroundColor($r('app.color.card_background'))
            .borderRadius(12)
            .enabled(!this.isDiagnosing)
            .onClick(() => {
              this.isDiagnosing = true;
              this.diagResult = '';
              CloudDBService.diagnose().then((result: string) => {
                this.diagResult = result;
                this.isDiagnosing = false;
              }).catch((e: Error) => {
                this.diagResult = '❌ 诊断异常: ' + JSON.stringify(e);
                this.isDiagnosing = false;
              });
            });

          if (this.diagResult.length > 0) {
            Text(this.diagResult)
              .fontSize(12)
              .fontColor($r('app.color.label_secondary'))
              .width('100%')
              .padding(12)
              .backgroundColor('#F5F5F5')
              .borderRadius(8);
          }
        }

        Button('退出登录')
          .width('100%')
          .height(48)
          .fontSize(15)
          .fontColor($r('app.color.destructive'))
          .backgroundColor($r('app.color.card_background'))
          .borderRadius(12)
          .shadow({ radius: 4, color: '#0D000000', offsetX: 0, offsetY: 2 })
          .onClick(() => {
            this.getUIContext().getPromptAction().showDialog({
              message: '确定退出当前帐号？',
              buttons: [
                { text: '取消', color: '#666666' },
                { text: '确定', color: '#FF3B30' }
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
  MenuItem(icon: string, title: string, value: string, iconBgColor: string, onClick: () => void) {
    Row() {
      Column() {
        Text(icon)
          .fontSize(16);
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
      Text('›')
        .fontSize(18)
        .fontColor($r('app.color.label_tertiary'));
    }
    .width('100%')
    .height(52)
    .padding({ left: 16, right: 16 })
    .onClick(onClick);
  }
}
