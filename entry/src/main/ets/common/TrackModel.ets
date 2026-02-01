
export namespace TrackModel {
  /**
   * 轨迹点（用于地图折线），与云数据库 TrackPoint 对齐。
   */
  export interface TrackPointItem {
    latitude: number;
    longitude: number;
    altitude?: number;
    timestamp?: number;
  }

  /**
   * 轨迹本地模型，与云数据库 Track 字段对齐，便于后续同步 Cloud DB。
   */
  export interface Track {
    trackId: string;
    ownerUserId?: string;
    title: string;
    description?: string;
    visibility?: string;
    status: string;
    segmentCount?: number;
    trackPoints?: TrackPointItem[];
    createdAt: number;
    updatedAt?: number;
  }

  /**
   * 轨迹更新入参：所有字段可选，用于 updateTrack 等。ArkTS 不支持 Partial<T>，故显式定义。
   */
  export interface TrackUpdate {
    trackId?: string;
    ownerUserId?: string;
    title?: string;
    description?: string;
    visibility?: string;
    status?: string;
    segmentCount?: number;
    trackPoints?: TrackPointItem[];
    createdAt?: number;
    updatedAt?: number;
  }

  export const TRACK_STATUS_EDITING = 'editing';
  export const TRACK_STATUS_DONE = 'done';
}
