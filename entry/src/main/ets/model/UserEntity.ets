import { cloudDatabase } from '@kit.CloudFoundationKit';

/**
 * Cloud DB 对象类型：User（用户）
 * 必须 extends cloudDatabase.DatabaseObject
 */
export class UserEntity extends cloudDatabase.DatabaseObject {
  public userId: string | undefined;
  public phone: string | undefined;
  public nickname: string | undefined;
  public avatarUrl: string | undefined;
  public familyName: string | undefined;
  public createdAt: Date | undefined;
  public updatedAt: Date | undefined;

  public naturalbase_ClassName(): string {
    return 'User';
  }
}
