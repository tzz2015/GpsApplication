import { cloudDatabase } from '@kit.CloudFoundationKit';

/**
 * Cloud DB 对象类型：Feedback（用户反馈）
 *
 * AGC 后台需创建 Object Type "Feedback"，字段如下：
 * - feedbackId: String (主键)
 * - userId: String
 * - content: String
 * - contact: String
 * - createdAt: Date
 */
export class FeedbackEntity extends cloudDatabase.DatabaseObject {
  public feedbackId: string | undefined;
  public userId: string | undefined;
  public content: string | undefined;
  public contact: string | undefined;
  public createdAt: Date | undefined;

  public naturalbase_ClassName(): string {
    return 'Feedback';
  }
}
