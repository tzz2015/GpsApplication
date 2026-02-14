import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { TrackModel } from './TrackModel';

const LOG_DOMAIN = 0x0000;
const LOG_TAG = 'TrackStore';
const PREF_NAME = 'track_prefs';
const KEY_TRACKS = 'tracks_list';
const KEY_TOMBSPOTS = 'tombspots_list';
const KEY_TRACKPOINTS = 'trackpoints_list';

/**
 * 轨迹本地存储（Preferences），先写本地，后续可同步 Cloud DB。
 * 管理 Track、TombSpot、TrackPoint 三种数据。
 */
export class TrackStore {

  // ==================== Track CRUD ====================

  /**
   * 获取当前用户所有轨迹（按创建时间倒序）
   */
  static async getTracks(context: common.Context): Promise<TrackModel.Track[]> {
    try {
      const prefs = await preferences.getPreferences(context, PREF_NAME);
      const json = await prefs.get(KEY_TRACKS, '[]') as string;
      const list = JSON.parse(json) as TrackModel.Track[];
      return (list || []).sort((a: TrackModel.Track, b: TrackModel.Track) => b.createdAt - a.createdAt);
    } catch (e) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'getTracks: %{public}s', JSON.stringify(e));
      return [];
    }
  }

  /**
   * 根据 trackId 获取一条轨迹
   */
  static async getTrackById(context: common.Context, trackId: string): Promise<TrackModel.Track | null> {
    const list = await TrackStore.getTracks(context);
    const found = list.find((t: TrackModel.Track) => t.trackId === trackId);
    return found ? found : null;
  }

  /**
   * 获取公开轨迹列表
   */
  static async getPublicTracks(context: common.Context): Promise<TrackModel.Track[]> {
    const list = await TrackStore.getTracks(context);
    return list.filter((t: TrackModel.Track) =>
      t.visibility === TrackModel.VISIBILITY_PUBLIC && t.status === TrackModel.TRACK_STATUS_DONE
    );
  }

  /**
   * 获取指定用户的轨迹
   */
  static async getTracksByUser(context: common.Context, userId: string): Promise<TrackModel.Track[]> {
    const list = await TrackStore.getTracks(context);
    return list.filter((t: TrackModel.Track) => t.ownerUserId === userId);
  }

  /**
   * 保存一条轨迹（新增或更新）
   */
  static async saveTrack(context: common.Context, track: TrackModel.Track): Promise<void> {
    try {
      const list = await TrackStore.getTracks(context);
      const idx = list.findIndex((t: TrackModel.Track) => t.trackId === track.trackId);
      if (idx >= 0) {
        list[idx] = track;
      } else {
        list.unshift(track);
      }
      const prefs = await preferences.getPreferences(context, PREF_NAME);
      await prefs.put(KEY_TRACKS, JSON.stringify(list));
      await prefs.flush();
    } catch (e) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'saveTrack: %{public}s', JSON.stringify(e));
    }
  }

  /**
   * 更新轨迹部分字段
   */
  static async updateTrack(context: common.Context, trackId: string, updates: TrackModel.TrackUpdate): Promise<void> {
    const list = await TrackStore.getTracks(context);
    const idx = list.findIndex((t: TrackModel.Track) => t.trackId === trackId);
    if (idx < 0) {
      return;
    }
    const existing = list[idx];
    list[idx] = {
      trackId: existing.trackId,
      ownerUserId: existing.ownerUserId,
      ownerDisplayName: existing.ownerDisplayName || '',
      title: updates.title !== undefined ? updates.title : existing.title,
      description: updates.description !== undefined ? updates.description : existing.description,
      visibility: updates.visibility !== undefined ? updates.visibility : existing.visibility,
      status: updates.status !== undefined ? updates.status : existing.status,
      startName: updates.startName !== undefined ? updates.startName : existing.startName,
      endName: updates.endName !== undefined ? updates.endName : existing.endName,
      startLat: updates.startLat !== undefined ? updates.startLat : existing.startLat,
      startLng: updates.startLng !== undefined ? updates.startLng : existing.startLng,
      endLat: updates.endLat !== undefined ? updates.endLat : existing.endLat,
      endLng: updates.endLng !== undefined ? updates.endLng : existing.endLng,
      totalDistance: updates.totalDistance !== undefined ? updates.totalDistance : existing.totalDistance,
      totalDuration: updates.totalDuration !== undefined ? updates.totalDuration : existing.totalDuration,
      maxAltitude: updates.maxAltitude !== undefined ? updates.maxAltitude : existing.maxAltitude,
      spotCount: updates.spotCount !== undefined ? updates.spotCount : (existing.spotCount || 0),
      coverImageUrl: updates.coverImageUrl !== undefined ? updates.coverImageUrl : existing.coverImageUrl,
      createdAt: existing.createdAt,
      updatedAt: Date.now()
    };
    try {
      const prefs = await preferences.getPreferences(context, PREF_NAME);
      await prefs.put(KEY_TRACKS, JSON.stringify(list));
      await prefs.flush();
    } catch (e) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'updateTrack: %{public}s', JSON.stringify(e));
    }
  }

  /**
   * 删除轨迹（同时删除关联的打卡点和轨迹点）
   */
  static async deleteTrack(context: common.Context, trackId: string): Promise<void> {
    try {
      // 删除轨迹
      const tracks = await TrackStore.getTracks(context);
      const filteredTracks = tracks.filter((t: TrackModel.Track) => t.trackId !== trackId);
      const prefs = await preferences.getPreferences(context, PREF_NAME);
      await prefs.put(KEY_TRACKS, JSON.stringify(filteredTracks));

      // 删除关联的打卡点
      const spots = await TrackStore.getAllTombSpots(context);
      const filteredSpots = spots.filter((s: TrackModel.TombSpot) => s.trackId !== trackId);
      await prefs.put(KEY_TOMBSPOTS, JSON.stringify(filteredSpots));

      // 删除关联的轨迹点
      const points = await TrackStore.getAllTrackPoints(context);
      const filteredPoints = points.filter((p: TrackModel.TrackPointItem) => p.pointId.startsWith(trackId));
      await prefs.put(KEY_TRACKPOINTS, JSON.stringify(filteredPoints));

      await prefs.flush();
    } catch (e) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'deleteTrack: %{public}s', JSON.stringify(e));
    }
  }

  // ==================== TombSpot CRUD ====================

  /**
   * 获取所有打卡点（内部使用）
   */
  private static async getAllTombSpots(context: common.Context): Promise<TrackModel.TombSpot[]> {
    try {
      const prefs = await preferences.getPreferences(context, PREF_NAME);
      const json = await prefs.get(KEY_TOMBSPOTS, '[]') as string;
      return (JSON.parse(json) as TrackModel.TombSpot[]) || [];
    } catch (e) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'getAllTombSpots: %{public}s', JSON.stringify(e));
      return [];
    }
  }

  /**
   * 获取某轨迹下的所有打卡点（按 orderIndex 排序）
   */
  static async getTombSpotsByTrackId(context: common.Context, trackId: string): Promise<TrackModel.TombSpot[]> {
    const all = await TrackStore.getAllTombSpots(context);
    return all
      .filter((s: TrackModel.TombSpot) => s.trackId === trackId)
      .sort((a: TrackModel.TombSpot, b: TrackModel.TombSpot) => a.orderIndex - b.orderIndex);
  }

  /**
   * 根据 tombId 获取打卡点
   */
  static async getTombSpotById(context: common.Context, tombId: string): Promise<TrackModel.TombSpot | null> {
    const all = await TrackStore.getAllTombSpots(context);
    const found = all.find((s: TrackModel.TombSpot) => s.tombId === tombId);
    return found ? found : null;
  }

  /**
   * 保存一个打卡点（新增或更新）
   */
  static async saveTombSpot(context: common.Context, spot: TrackModel.TombSpot): Promise<void> {
    try {
      const list = await TrackStore.getAllTombSpots(context);
      const idx = list.findIndex((s: TrackModel.TombSpot) => s.tombId === spot.tombId);
      if (idx >= 0) {
        list[idx] = spot;
      } else {
        list.push(spot);
      }
      const prefs = await preferences.getPreferences(context, PREF_NAME);
      await prefs.put(KEY_TOMBSPOTS, JSON.stringify(list));
      await prefs.flush();
    } catch (e) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'saveTombSpot: %{public}s', JSON.stringify(e));
    }
  }

  /**
   * 更新打卡点部分字段
   */
  static async updateTombSpot(context: common.Context, tombId: string, updates: TrackModel.TombSpotUpdate): Promise<void> {
    const list = await TrackStore.getAllTombSpots(context);
    const idx = list.findIndex((s: TrackModel.TombSpot) => s.tombId === tombId);
    if (idx < 0) {
      return;
    }
    const existing = list[idx];
    list[idx] = {
      tombId: existing.tombId,
      trackId: existing.trackId,
      orderIndex: existing.orderIndex,
      name: updates.name !== undefined ? updates.name : existing.name,
      personInfo: updates.personInfo !== undefined ? updates.personInfo : existing.personInfo,
      remark: updates.remark !== undefined ? updates.remark : existing.remark,
      latitude: updates.latitude !== undefined ? updates.latitude : existing.latitude,
      longitude: updates.longitude !== undefined ? updates.longitude : existing.longitude,
      altitude: updates.altitude !== undefined ? updates.altitude : existing.altitude,
      contentText: updates.contentText !== undefined ? updates.contentText : existing.contentText,
      imageUris: updates.imageUris !== undefined ? updates.imageUris : existing.imageUris,
      createdAt: existing.createdAt,
      updatedAt: Date.now()
    };
    try {
      const prefs = await preferences.getPreferences(context, PREF_NAME);
      await prefs.put(KEY_TOMBSPOTS, JSON.stringify(list));
      await prefs.flush();
    } catch (e) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'updateTombSpot: %{public}s', JSON.stringify(e));
    }
  }

  /**
   * 删除打卡点
   */
  static async deleteTombSpot(context: common.Context, tombId: string): Promise<void> {
    try {
      const list = await TrackStore.getAllTombSpots(context);
      const filtered = list.filter((s: TrackModel.TombSpot) => s.tombId !== tombId);
      const prefs = await preferences.getPreferences(context, PREF_NAME);
      await prefs.put(KEY_TOMBSPOTS, JSON.stringify(filtered));
      await prefs.flush();
    } catch (e) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'deleteTombSpot: %{public}s', JSON.stringify(e));
    }
  }

  // ==================== TrackPoint 批量操作 ====================

  /**
   * 获取所有轨迹点（内部使用）
   */
  private static async getAllTrackPoints(context: common.Context): Promise<TrackModel.TrackPointItem[]> {
    try {
      const prefs = await preferences.getPreferences(context, PREF_NAME);
      const json = await prefs.get(KEY_TRACKPOINTS, '[]') as string;
      return (JSON.parse(json) as TrackModel.TrackPointItem[]) || [];
    } catch (e) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'getAllTrackPoints: %{public}s', JSON.stringify(e));
      return [];
    }
  }

  /**
   * 批量保存轨迹点（追加到指定轨迹）
   */
  static async saveTrackPoints(context: common.Context, trackId: string, points: TrackModel.TrackPointItem[]): Promise<void> {
    try {
      const all = await TrackStore.getAllTrackPoints(context);
      // 用 trackId 前缀标记归属
      const newPoints = points.map((p: TrackModel.TrackPointItem): TrackModel.TrackPointItem => {
        const item: TrackModel.TrackPointItem = {
          pointId: p.pointId.length > 0 ? p.pointId : (trackId + '_pt_' + Date.now() + '_' + Math.random().toString(36).slice(2, 5)),
          latitude: p.latitude,
          longitude: p.longitude,
          altitude: p.altitude,
          accuracy: p.accuracy,
          timestamp: p.timestamp,
          syncStatus: 'pending'
        };
        return item;
      });
      const merged = all.concat(newPoints);
      const prefs = await preferences.getPreferences(context, PREF_NAME);
      await prefs.put(KEY_TRACKPOINTS, JSON.stringify(merged));
      await prefs.flush();
    } catch (e) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'saveTrackPoints: %{public}s', JSON.stringify(e));
    }
  }

  /**
   * 获取某轨迹的所有轨迹点（按时间戳排序）
   */
  static async getTrackPointsByTrackId(context: common.Context, trackId: string): Promise<TrackModel.TrackPointItem[]> {
    const all = await TrackStore.getAllTrackPoints(context);
    return all
      .filter((p: TrackModel.TrackPointItem) => p.pointId.startsWith(trackId))
      .sort((a: TrackModel.TrackPointItem, b: TrackModel.TrackPointItem) => a.timestamp - b.timestamp);
  }

  /**
   * 标记轨迹点为已同步
   */
  static async markPointsSynced(context: common.Context, trackId: string, syncedPoints: TrackModel.TrackPointItem[]): Promise<void> {
    try {
      const all = await TrackStore.getAllTrackPoints(context);
      const syncedIds: string[] = [];
      for (let i = 0; i < syncedPoints.length; i++) {
        syncedIds.push(syncedPoints[i].pointId);
      }
      for (let i = 0; i < all.length; i++) {
        if (syncedIds.indexOf(all[i].pointId) >= 0) {
          all[i].syncStatus = 'synced';
        }
      }
      const prefs = await preferences.getPreferences(context, PREF_NAME);
      await prefs.put(KEY_TRACKPOINTS, JSON.stringify(all));
      await prefs.flush();
    } catch (e) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'markPointsSynced: %{public}s', JSON.stringify(e));
    }
  }
}
