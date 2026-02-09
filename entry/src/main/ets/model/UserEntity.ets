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
  public updatedAt: string | undefined; // 云 schema 定义为 String 类型

  public naturalbase_ClassName(): string {
    return 'User';
  }
}
