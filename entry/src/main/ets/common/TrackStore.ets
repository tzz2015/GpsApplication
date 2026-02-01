
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { TrackModel, type TrackModel as TrackModelType } from './TrackModel';

const PREF_NAME = 'track_prefs';
const KEY_TRACKS_LIST = 'tracks_list';

/**
 * 轨迹本地存储（Preferences），先写本地，后续可同步 Cloud DB。
 */
export class TrackStore {
  /**
   * 获取当前用户轨迹列表（按创建时间倒序）
   */
  static async getTracks(context: common.Context): Promise<TrackModel.Track[]> {
    try {
      const prefs = await preferences.getPreferences(context, PREF_NAME);
      const json = await prefs.get(KEY_TRACKS_LIST, '[]') as string;
      const list = JSON.parse(json) as TrackModel.Track[];
      return (list || []).sort((a, b) => b.createdAt - a.createdAt);
    } catch (e) {
      console.error('TrackStore getTracks: ' + JSON.stringify(e));
      return [];
    }
  }

  /**
   * 保存一条轨迹（新增或覆盖）
   */
  static async saveTrack(context: common.Context, track: TrackModel.Track): Promise<void> {
    try {
      const list = await TrackStore.getTracks(context);
      const idx = list.findIndex(t => t.trackId === track.trackId);
      const newTrack: TrackModel.Track = {
        trackId: track.trackId,
        ownerUserId: track.ownerUserId,
        title: track.title,
        description: track.description,
        visibility: track.visibility,
        status: track.status,
        segmentCount: track.segmentCount,
        trackPoints: track.trackPoints,
        createdAt: track.createdAt,
        updatedAt: Date.now()
      };
      if (idx >= 0) {
        const existingTrack = list[idx];
        list[idx] = {
          trackId: newTrack.trackId || existingTrack.trackId,
          ownerUserId: newTrack.ownerUserId || existingTrack.ownerUserId,
          title: newTrack.title || existingTrack.title,
          description: newTrack.description || existingTrack.description,
          visibility: newTrack.visibility || existingTrack.visibility,
          status: newTrack.status || existingTrack.status,
          segmentCount: newTrack.segmentCount || existingTrack.segmentCount,
          trackPoints: newTrack.trackPoints || existingTrack.trackPoints,
          createdAt: existingTrack.createdAt,
          updatedAt: newTrack.updatedAt
        };
      } else {
        list.unshift(newTrack);
      }
      const prefs = await preferences.getPreferences(context, PREF_NAME);
      await prefs.put(KEY_TRACKS_LIST, JSON.stringify(list));
      await prefs.flush();
    } catch (e) {
      console.error('TrackStore saveTrack: ' + JSON.stringify(e));
    }
  }

  /**
   * 更新轨迹部分字段
   */
  static async updateTrack(
    context: common.Context,
    trackId: string,
    updates: TrackModel.TrackUpdate
  ): Promise<void> {
    const list = await TrackStore.getTracks(context);
    const idx = list.findIndex(t => t.trackId === trackId);
    if (idx < 0) return;
    const existingTrack = list[idx];
    list[idx] = {
      trackId: existingTrack.trackId,
      ownerUserId: updates.ownerUserId || existingTrack.ownerUserId,
      title: updates.title || existingTrack.title,
      description: updates.description || existingTrack.description,
      visibility: updates.visibility || existingTrack.visibility,
      status: updates.status || existingTrack.status,
      segmentCount: updates.segmentCount || existingTrack.segmentCount,
      trackPoints: updates.trackPoints || existingTrack.trackPoints,
      createdAt: existingTrack.createdAt,
      updatedAt: Date.now()
    };
    try {
      const prefs = await preferences.getPreferences(context, PREF_NAME);
      await prefs.put(KEY_TRACKS_LIST, JSON.stringify(list));
      await prefs.flush();
    } catch (e) {
      console.error('TrackStore updateTrack: ' + JSON.stringify(e));
    }
  }

  /**
   * 根据 trackId 获取一条轨迹
   */
  static async getTrackById(context: common.Context, trackId: string): Promise<TrackModel.Track | null> {
    const list = await TrackStore.getTracks(context);
    return list.find(t => t.trackId === trackId) ?? null;
  }
}
