import { hilog } from '@kit.PerformanceAnalysisKit';
import { common } from '@kit.AbilityKit';
import { connection } from '@kit.NetworkKit';
import { TrackModel } from './TrackModel';
import { TrackStore } from './TrackStore';
import { AuthStore } from './AuthStore';
import { CloudDBService } from './CloudDBService';
import { CloudStorageService } from './CloudStorageService';
import { UserEntity } from '../model/UserEntity';
import { TrackEntity } from '../model/TrackEntity';
import { TrackPointEntity } from '../model/TrackPointEntity';
import { TombSpotEntity } from '../model/TombSpotEntity';

const LOG_DOMAIN = 0x0000;
const LOG_TAG = 'SyncService';

/**
 * 数据同步服务
 * 核心策略：本地优先写入，有网时同步到云端
 */
export class SyncService {
  private static isSyncing: boolean = false;

  /**
   * 检查网络是否可用
   */
  static isNetworkAvailable(): boolean {
    try {
      const netHandle = connection.getDefaultNetSync();
      if (netHandle && netHandle.netId > 0) {
        return true;
      }
      return false;
    } catch (e) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'Check network failed: %{public}s', JSON.stringify(e));
      return false;
    }
  }

  /**
   * 同步用户信息到云端
   * 关闭 Cloud DB World 写入权限时，须先 AGC Auth 登录，否则跳过
   */
  static async syncUser(context: common.Context): Promise<void> {
    hilog.info(LOG_DOMAIN, LOG_TAG, '--- syncUser start ---');

    if (!SyncService.isNetworkAvailable()) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, '⚠️ syncUser: 无网络，跳过');
      return;
    }
    if (!(await CloudDBService.hasAgcAuthUser())) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, '⚠️ syncUser: AGC Auth 未登录，无写入权限，跳过');
      return;
    }

    try {
      const authUser = await AuthStore.getCurrentUser(context);
      if (!authUser) {
        hilog.warn(LOG_DOMAIN, LOG_TAG, '⚠️ syncUser: 本地无用户数据');
        return;
      }
      hilog.info(LOG_DOMAIN, LOG_TAG, 'syncUser: userId=%{public}s, name=%{public}s',
        authUser.userId, authUser.displayName);

      const userEntity = new UserEntity();
      userEntity.userId = authUser.userId;
      userEntity.nickname = authUser.displayName;
      userEntity.avatarUrl = authUser.avatarUrl;
      userEntity.familyName = authUser.familyName;
      userEntity.createdAt = new Date(authUser.createdAt);
      userEntity.updatedAt = new Date(authUser.updatedAt);

      await CloudDBService.upsertUser(userEntity);
      hilog.info(LOG_DOMAIN, LOG_TAG, '✅ syncUser 完成');
    } catch (e) {
      hilog.error(LOG_DOMAIN, LOG_TAG, '❌ syncUser 失败: %{public}s', JSON.stringify(e));
    }
  }

  /**
   * 同步单条轨迹到云端（包含打卡点和轨迹点）
   * 流程：上传图片 → 同步轨迹 → 同步打卡点 → 同步轨迹点
   * 关闭 Cloud DB World 写入权限时，须先 AGC Auth 登录，否则跳过
   */
  static async syncTrack(context: common.Context, trackId: string): Promise<void> {
    if (!SyncService.isNetworkAvailable()) {
      hilog.info(LOG_DOMAIN, LOG_TAG, 'No network, skip track sync');
      return;
    }
    if (!(await CloudDBService.hasAgcAuthUser())) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, '⚠️ syncTrack: AGC Auth 未登录，无写入权限，跳过');
      return;
    }

    try {
      // 1. 读取轨迹主体
      const track = await TrackStore.getTrackById(context, trackId);
      if (!track) {
        return;
      }

      // 2. ★ 上传轨迹封面图到云存储（本地路径 → 云端 URL）
      if (track.coverImageUrl.length > 0 && CloudStorageService.isLocalPath(track.coverImageUrl)) {
        hilog.info(LOG_DOMAIN, LOG_TAG, 'Uploading track cover for %{public}s...', trackId);
        const cloudCoverUrl = await CloudStorageService.uploadTrackCover(context, trackId, track.coverImageUrl);
        if (cloudCoverUrl !== track.coverImageUrl) {
          // 上传成功，更新本地存储的封面 URL
          track.coverImageUrl = cloudCoverUrl;
          await TrackStore.updateTrack(context, trackId, { coverImageUrl: cloudCoverUrl });
          hilog.info(LOG_DOMAIN, LOG_TAG, '✅ Track cover uploaded & local updated');
        }
      }

      // 3. 同步轨迹主体到 Cloud DB
      const trackEntity = SyncService.localTrackToEntity(track);
      await CloudDBService.upsertTrack(trackEntity);

      // 4. 同步打卡点（含图片上传）
      const spots = await TrackStore.getTombSpotsByTrackId(context, trackId);
      for (let i = 0; i < spots.length; i++) {
        let spot = spots[i];

        // ★ 上传打卡点图片到云存储
        if (spot.imageUris.length > 0 && spot.imageUris !== '[]') {
          const updatedUrisJson = await CloudStorageService.uploadSpotImages(
            context, trackId, spot.tombId, spot.imageUris
          );
          if (updatedUrisJson !== spot.imageUris) {
            spot.imageUris = updatedUrisJson;
            await TrackStore.updateTombSpot(context, spot.tombId, { imageUris: updatedUrisJson });
            hilog.info(LOG_DOMAIN, LOG_TAG, '✅ Spot images uploaded: %{public}s', spot.tombId);
          }
        }

        // 同步前再读一次本地，确保 contentText/imageUris 为最新（避免与保存竞态）
        const latest = await TrackStore.getTombSpotById(context, spot.tombId);
        if (latest) {
          spot = latest;
        }
        const spotEntity = SyncService.localSpotToEntity(spot);
        await CloudDBService.upsertTombSpot(spotEntity);
      }

      // 5. 同步轨迹点（本地 syncStatus=pending 的）
      const points = await TrackStore.getTrackPointsByTrackId(context, trackId);
      const pendingPoints = points.filter((p: TrackModel.TrackPointItem) => p.syncStatus === 'pending');
      if (pendingPoints.length > 0) {
        const pointEntities = SyncService.localPointsToEntities(trackId, pendingPoints);
        await CloudDBService.upsertTrackPoints(pointEntities);
        await TrackStore.markPointsSynced(context, trackId, pendingPoints);
      }

      hilog.info(LOG_DOMAIN, LOG_TAG,
        'Track synced: %{public}s, spots: %{public}d, points: %{public}d',
        trackId, spots.length, pendingPoints.length);
    } catch (e) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Sync track failed: %{public}s', JSON.stringify(e));
    }
  }

  /**
   * 同步所有待同步的数据
   */
  static async syncAll(context: common.Context): Promise<void> {
    if (SyncService.isSyncing) {
      return;
    }
    if (!SyncService.isNetworkAvailable()) {
      return;
    }

    SyncService.isSyncing = true;
    try {
      await SyncService.syncUser(context);

      const authUser = await AuthStore.getCurrentUser(context);
      if (!authUser) {
        return;
      }

      const tracks = await TrackStore.getTracksByUser(context, authUser.userId);
      for (let i = 0; i < tracks.length; i++) {
        await SyncService.syncTrack(context, tracks[i].trackId);
      }

      hilog.info(LOG_DOMAIN, LOG_TAG, 'Sync all completed, tracks: %{public}d', tracks.length);
    } catch (e) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Sync all failed: %{public}s', JSON.stringify(e));
    } finally {
      SyncService.isSyncing = false;
    }
  }

  /**
   * 从云端恢复当前用户信息到本地（重装后登录用）
   * 若 Cloud DB 中已有该用户的 nickname/avatarUrl/familyName，则覆盖本地
   */
  static async restoreUserFromCloud(context: common.Context): Promise<void> {
    if (!SyncService.isNetworkAvailable()) {
      return;
    }
    try {
      const authUser = await AuthStore.getCurrentUser(context);
      if (!authUser) {
        return;
      }
      const cloudUser = await CloudDBService.queryUser(authUser.userId);
      if (!cloudUser || !cloudUser.nickname || cloudUser.nickname.length === 0) {
        hilog.info(LOG_DOMAIN, LOG_TAG, 'No cloud user or nickname, keep local');
        return;
      }
      await AuthStore.updateUser(context, {
        displayName: cloudUser.nickname,
        avatarUrl: cloudUser.avatarUrl || '',
        familyName: cloudUser.familyName || ''
      });
      hilog.info(LOG_DOMAIN, LOG_TAG, '✅ restoreUserFromCloud: nickname=%{public}s', cloudUser.nickname);
    } catch (e) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'restoreUserFromCloud failed: %{public}s', JSON.stringify(e));
    }
  }

  /**
   * 从云端恢复「我的轨迹」到本地（重装后或本地为空时用）
   * 仅当本地当前用户轨迹数为 0 时才拉取，避免覆盖本地新数据
   */
  static async restoreMyTracksFromCloud(context: common.Context): Promise<void> {
    if (!SyncService.isNetworkAvailable()) {
      return;
    }
    try {
      const authUser = await AuthStore.getCurrentUser(context);
      if (!authUser) {
        return;
      }
      const localTracks = await TrackStore.getTracksByUser(context, authUser.userId);
      if (localTracks.length > 0) {
        hilog.info(LOG_DOMAIN, LOG_TAG, 'Local tracks exist (%{public}d), skip restore', localTracks.length);
        return;
      }

      const cloudTracks = await CloudDBService.queryTracksByUser(authUser.userId);
      hilog.info(LOG_DOMAIN, LOG_TAG, 'Restore my tracks from cloud: %{public}d', cloudTracks.length);

      for (let i = 0; i < cloudTracks.length; i++) {
        const entity = cloudTracks[i];
        const track = SyncService.cloudTrackToLocal(entity);
        track.ownerDisplayName = authUser.displayName;
        await TrackStore.saveTrack(context, track);

        const trackId = track.trackId;
        const spots = await CloudDBService.queryTombSpots(trackId);
        for (let s = 0; s < spots.length; s++) {
          const spot = SyncService.cloudSpotToLocal(spots[s]);
          // 重装恢复：将打卡点图片的云端 URL 下载到本地，保证图文记录可正常显示
          if (spot.imageUris.length > 0 && spot.imageUris !== '[]') {
            const localUrisJson: string = await CloudStorageService.restoreSpotImagesToLocal(
              context, spot.tombId, spot.imageUris
            );
            if (localUrisJson !== spot.imageUris) {
              spot.imageUris = localUrisJson;
            }
          }
          await TrackStore.saveTombSpot(context, spot);
        }
        if (spots.length > 0) {
          await TrackStore.updateTrack(context, trackId, { spotCount: spots.length });
        }

        const points = await CloudDBService.queryTrackPoints(trackId);
        const localPoints = SyncService.cloudPointsToLocal(points, trackId);
        if (localPoints.length > 0) {
          await TrackStore.saveTrackPoints(context, trackId, localPoints);
        }
      }

      if (cloudTracks.length > 0) {
        hilog.info(LOG_DOMAIN, LOG_TAG, '✅ restoreMyTracksFromCloud done: %{public}d tracks', cloudTracks.length);
      }
    } catch (e) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'restoreMyTracksFromCloud failed: %{public}s', JSON.stringify(e));
    }
  }

  /**
   * 从云端拉取公开轨迹
   */
  static async fetchPublicTracks(): Promise<TrackEntity[]> {
    if (!SyncService.isNetworkAvailable()) {
      return [];
    }
    try {
      return await CloudDBService.queryPublicTracks();
    } catch (e) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Fetch public tracks failed: %{public}s', JSON.stringify(e));
      return [];
    }
  }

  /**
   * 删除云端轨迹（及关联数据 + 云存储文件）
   */
  static async deleteCloudTrack(trackId: string): Promise<void> {
    if (!SyncService.isNetworkAvailable()) {
      return;
    }

    try {
      // 1. 删除 Cloud DB 数据
      await CloudDBService.deleteTrackPoints(trackId);

      const spots = await CloudDBService.queryTombSpots(trackId);
      for (let i = 0; i < spots.length; i++) {
        const tombId = spots[i].tombId;
        if (tombId) {
          await CloudDBService.deleteTombSpot(tombId);
        }
      }

      await CloudDBService.deleteTrack(trackId);

      // 2. ★ 清理云存储中该轨迹的所有文件（封面 + 打卡点图片）
      const tombIds: string[] = [];
      for (let i = 0; i < spots.length; i++) {
        if (spots[i].tombId) {
          tombIds.push(spots[i].tombId as string);
        }
      }
      await CloudStorageService.deleteTrackFiles(trackId, tombIds);

      hilog.info(LOG_DOMAIN, LOG_TAG, 'Cloud track deleted (DB + Storage): %{public}s', trackId);
    } catch (e) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Delete cloud track failed: %{public}s', JSON.stringify(e));
    }
  }

  // ==================== 数据转换 ====================

  private static localTrackToEntity(track: TrackModel.Track): TrackEntity {
    const entity = new TrackEntity();
    entity.trackId = track.trackId;
    entity.ownerUserId = track.ownerUserId;
    entity.title = track.title;
    entity.description = track.description;
    entity.startName = track.startName;
    entity.endName = track.endName;
    entity.visibility = track.visibility;
    entity.status = track.status;
    entity.coverImageUrl = track.coverImageUrl;
    entity.createdAt = new Date(track.createdAt);
    entity.updatedAt = new Date(track.updatedAt);
    entity.totalDistance = track.totalDistance;
    entity.totalDuration = track.totalDuration;
    entity.maxAltitude = track.maxAltitude;
    entity.startLat = track.startLat;
    entity.startLng = track.startLng;
    entity.endLat = track.endLat;
    entity.endLng = track.endLng;
    return entity;
  }

  private static localSpotToEntity(spot: TrackModel.TombSpot): TombSpotEntity {
    const entity = new TombSpotEntity();
    entity.tombId = spot.tombId;
    entity.trackId = spot.trackId;
    entity.orderIndex = spot.orderIndex;
    entity.name = spot.name || '';
    entity.personInfo = spot.personInfo ?? '';
    entity.remark = spot.remark ?? '';
    entity.lat = spot.latitude;
    entity.lng = spot.longitude;
    entity.altitude = spot.altitude;
    entity.contentText = spot.contentText ?? '';
    entity.imageUris = spot.imageUris ?? '[]';
    entity.createdAt = new Date(spot.createdAt);
    entity.updatedAt = new Date(spot.updatedAt);
    return entity;
  }

  private static localPointsToEntities(trackId: string, points: TrackModel.TrackPointItem[]): TrackPointEntity[] {
    const entities: TrackPointEntity[] = [];
    for (let i = 0; i < points.length; i++) {
      const p = points[i];
      const entity = new TrackPointEntity();
      entity.pointId = p.pointId;
      entity.trackId = trackId;
      entity.orderIndex = i.toString(); // 云 schema 中 orderIndex 为 String 类型
      entity.lat = p.latitude;
      entity.lng = p.longitude;
      entity.altitude = p.altitude;
      entity.accuracy = p.accuracy;
      entity.timestamp = p.timestamp;
      entity.createdAt = new Date(p.timestamp);
      entities.push(entity);
    }
    return entities;
  }

  static cloudTrackToLocal(entity: TrackEntity): TrackModel.Track {
    const track: TrackModel.Track = {
      trackId: entity.trackId || '',
      ownerUserId: entity.ownerUserId || '',
      ownerDisplayName: '',
      title: entity.title || '',
      description: entity.description || '',
      visibility: entity.visibility || 'PRIVATE',
      status: entity.status || 'editing',
      startName: entity.startName || '',
      endName: entity.endName || '',
      startLat: entity.startLat ?? 0,
      startLng: entity.startLng ?? 0,
      endLat: entity.endLat ?? 0,
      endLng: entity.endLng ?? 0,
      totalDistance: entity.totalDistance ?? 0,
      totalDuration: entity.totalDuration ?? 0,
      maxAltitude: entity.maxAltitude ?? 0,
      spotCount: 0,
      coverImageUrl: entity.coverImageUrl || '',
      createdAt: entity.createdAt ? entity.createdAt.getTime() : Date.now(),
      updatedAt: entity.updatedAt ? entity.updatedAt.getTime() : Date.now()
    };
    return track;
  }

  private static cloudSpotToLocal(entity: TombSpotEntity): TrackModel.TombSpot {
    const spot: TrackModel.TombSpot = {
      tombId: entity.tombId || '',
      trackId: entity.trackId || '',
      orderIndex: entity.orderIndex ?? 0,
      name: entity.name || '',
      personInfo: entity.personInfo || '',
      remark: entity.remark || '',
      latitude: entity.lat ?? 0,
      longitude: entity.lng ?? 0,
      altitude: entity.altitude ?? 0,
      contentText: entity.contentText || '',
      imageUris: entity.imageUris || '[]',
      createdAt: entity.createdAt ? entity.createdAt.getTime() : Date.now(),
      updatedAt: entity.updatedAt ? entity.updatedAt.getTime() : Date.now()
    };
    return spot;
  }

  private static cloudPointsToLocal(entities: TrackPointEntity[], trackId: string): TrackModel.TrackPointItem[] {
    const items: TrackModel.TrackPointItem[] = [];
    for (let i = 0; i < entities.length; i++) {
      const e = entities[i];
      const item: TrackModel.TrackPointItem = {
        pointId: e.pointId || (trackId + '_pt_' + (e.timestamp ?? Date.now()) + '_' + i),
        latitude: e.lat ?? 0,
        longitude: e.lng ?? 0,
        altitude: e.altitude ?? 0,
        accuracy: e.accuracy ?? 0,
        timestamp: e.timestamp ?? Date.now(),
        syncStatus: 'synced'
      };
      items.push(item);
    }
    return items;
  }
}
