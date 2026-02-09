import { cloudDatabase } from '@kit.CloudFoundationKit';

/**
 * Cloud DB 对象类型：TombSpot（打卡点/墓地点）
 */
export class TombSpotEntity extends cloudDatabase.DatabaseObject {
  public tombId: string | undefined;
  public segmentId: string | undefined; // 云 schema 中有此字段
  public trackId: string | undefined;
  public orderIndex: number | undefined;
  public name: string | undefined;
  public personInfo: string | undefined;
  public remark: string | undefined;
  public lat: number | undefined;
  public lng: number | undefined;
  public altitude: number | undefined;
  public createdAt: Date | undefined;
  public updatedAt: Date | undefined;

  public naturalbase_ClassName(): string {
    return 'TombSpot';
  }
}
