import { cloudDatabase } from '@kit.CloudFoundationKit';

/**
 * Cloud DB 对象类型：Track（轨迹）
 * 必须 extends cloudDatabase.DatabaseObject
 */
export class TrackEntity extends cloudDatabase.DatabaseObject {
  public trackId: string | undefined;
  public ownerUserId: string | undefined;
  public title: string | undefined;
  public description: string | undefined;
  public startName: string | undefined;
  public endName: string | undefined;
  public visibility: string | undefined;
  public status: string | undefined;
  public coverImageUrl: string | undefined;
  public createdAt: Date | undefined;
  public updatedAt: Date | undefined;
  /** 总里程(米)、总用时(毫秒)、最高海拔；起点/终点坐标（同步与恢复用） */
  public totalDistance: number | undefined;
  public totalDuration: number | undefined;
  public maxAltitude: number | undefined;
  public startLat: number | undefined;
  public startLng: number | undefined;
  public endLat: number | undefined;
  public endLng: number | undefined;

  public naturalbase_ClassName(): string {
    return 'Track';
  }
}
