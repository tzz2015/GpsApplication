import { cloudDatabase } from '@kit.CloudFoundationKit';

/**
 * Cloud DB 对象类型：Post（打卡点图文）
 */
export class PostEntity extends cloudDatabase.DatabaseObject {
  public postId: string | undefined;
  public tombId: string | undefined;
  public trackId: string | undefined;
  public authorUserId: string | undefined;
  public contentText: string | undefined;
  public imageUrls: string | undefined;
  public isPinned: boolean | undefined;
  public createdAt: Date | undefined;
  public updatedAt: Date | undefined;

  public naturalbase_ClassName(): string {
    return 'Post';
  }
}
