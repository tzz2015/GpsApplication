import { cloudDatabase } from '@kit.CloudFoundationKit';

/**
 * Cloud DB 对象类型：TrackPoint（轨迹点）
 * 云数据库使用 lat/lng（本地模型使用 latitude/longitude）
 */
export class TrackPointEntity extends cloudDatabase.DatabaseObject {
  public pointId: string | undefined;
  public trackId: string | undefined;
  public orderIndex: string | undefined; // 云 schema 定义为 String 类型
  public lat: number | undefined;
  public lng: number | undefined;
  public altitude: number | undefined;
  public accuracy: number | undefined;
  public timestamp: number | undefined;
  public createdAt: Date | undefined;

  public naturalbase_ClassName(): string {
    return 'TrackPoint';
  }
}
