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

  public naturalbase_ClassName(): string {
    return 'Track';
  }
}
