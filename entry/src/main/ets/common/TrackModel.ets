/**
 * 轨迹数据模型，与云数据库字段对齐
 * V1.0：一条轨迹 = 起点 + 若干打卡点(TombSpot) + 终点，不拆分多段
 */
export namespace TrackModel {

  /** 轨迹状态 */
  export const TRACK_STATUS_EDITING = 'editing';
  export const TRACK_STATUS_DONE = 'done';

  /** 可见范围 */
  export const VISIBILITY_PRIVATE = 'PRIVATE';
  export const VISIBILITY_PUBLIC = 'PUBLIC';

  /**
   * 轨迹点：GPS 坐标 + 海拔 + 时间戳
   */
  export interface TrackPointItem {
    pointId: string;
    latitude: number;
    longitude: number;
    altitude: number;
    accuracy: number;
    timestamp: number;
    syncStatus: string; // 'pending' | 'synced'
  }

  /**
   * 打卡点（墓地点）：对应云数据库 TombSpot
   */
  export interface TombSpot {
    tombId: string;
    trackId: string;
    orderIndex: number;
    name: string;
    personInfo: string;
    remark: string;
    latitude: number;
    longitude: number;
    altitude: number;
    contentText: string;
    imageUris: string;  // JSON 数组字符串 '["uri1","uri2"]'
    createdAt: number;
    updatedAt: number;
  }

  /**
   * 轨迹：对应云数据库 Track
   */
  export interface Track {
    trackId: string;
    ownerUserId: string;
    ownerDisplayName: string; // 创建者昵称（公开轨迹展示用）
    title: string;
    description: string;
    visibility: string;   // 'PRIVATE' | 'PUBLIC'
    status: string;       // 'editing' | 'done'
    startName: string;
    endName: string;
    startLat: number;
    startLng: number;
    endLat: number;
    endLng: number;
    totalDistance: number; // 总里程(米)
    totalDuration: number; // 总用时(毫秒)
    maxAltitude: number;  // 最高海拔
    spotCount: number;    // 打卡点数
    coverImageUrl: string;
    createdAt: number;
    updatedAt: number;
  }

  /**
   * 轨迹更新入参：所有字段可选
   */
  export interface TrackUpdate {
    title?: string;
    description?: string;
    visibility?: string;
    status?: string;
    startName?: string;
    endName?: string;
    startLat?: number;
    startLng?: number;
    endLat?: number;
    endLng?: number;
    totalDistance?: number;
    totalDuration?: number;
    maxAltitude?: number;
    spotCount?: number;
    coverImageUrl?: string;
  }

  /**
   * 打卡点更新入参
   */
  export interface TombSpotUpdate {
    name?: string;
    personInfo?: string;
    remark?: string;
    contentText?: string;
    imageUris?: string;
    latitude?: number;
    longitude?: number;
    altitude?: number;
  }

  /**
   * 生成唯一 ID
   */
  export function generateId(prefix: string): string {
    return prefix + '_' + Date.now().toString() + '_' + Math.random().toString(36).slice(2, 9);
  }

  /**
   * 计算两点之间的距离（米）- Haversine 公式
   */
  export function calculateDistance(lat1: number, lng1: number, lat2: number, lng2: number): number {
    const R = 6371000; // 地球半径(米)
    const dLat = (lat2 - lat1) * Math.PI / 180;
    const dLng = (lng2 - lng1) * Math.PI / 180;
    const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
      Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
      Math.sin(dLng / 2) * Math.sin(dLng / 2);
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    return R * c;
  }

  /**
   * 格式化距离（米 → km/m）
   */
  export function formatDistance(meters: number): string {
    if (meters >= 1000) {
      return (meters / 1000).toFixed(1) + ' km';
    }
    return Math.round(meters).toString() + ' m';
  }

  /**
   * 格式化时长（毫秒 → 时:分:秒）
   */
  export function formatDuration(ms: number): string {
    const totalSeconds = Math.floor(ms / 1000);
    const hours = Math.floor(totalSeconds / 3600);
    const minutes = Math.floor((totalSeconds % 3600) / 60);
    const seconds = totalSeconds % 60;
    if (hours > 0) {
      return `${hours}:${minutes.toString().padStart(2, '0')}:${seconds.toString().padStart(2, '0')}`;
    }
    return `${minutes.toString().padStart(2, '0')}:${seconds.toString().padStart(2, '0')}`;
  }

  /**
   * 格式化日期
   */
  export function formatDate(timestamp: number): string {
    const d = new Date(timestamp);
    const y = d.getFullYear();
    const m = (d.getMonth() + 1).toString().padStart(2, '0');
    const day = d.getDate().toString().padStart(2, '0');
    const h = d.getHours().toString().padStart(2, '0');
    const min = d.getMinutes().toString().padStart(2, '0');
    return `${y}-${m}-${day} ${h}:${min}`;
  }
}
