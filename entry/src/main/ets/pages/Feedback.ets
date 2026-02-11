import { promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { NavBar } from '../common/NavBar';
import { AuthStore } from '../common/AuthStore';

const PREF_NAME = 'feedback_prefs';
const KEY_LIST = 'feedback_list';

/** 单条反馈数据结构（本地存储，可选同步到云端需另加表） */
interface FeedbackItem {
  id: string;
  content: string;
  contact: string;
  userId: string;
  createdAt: number;
}

/**
 * 意见反馈页：样式与编辑个人信息页一致，卡片 + 表单
 */
@Entry
@Component
struct Feedback {
  @State content: string = '';
  @State contact: string = '';
  @State isSubmitting: boolean = false;

  private static async saveToLocal(context: common.Context, item: FeedbackItem): Promise<void> {
    const prefs = await preferences.getPreferences(context, PREF_NAME);
    const json = await prefs.get(KEY_LIST, '[]') as string;
    let list: FeedbackItem[] = [];
    try {
      list = JSON.parse(json) as FeedbackItem[];
    } catch (_e) {
      list = [];
    }
    list.unshift(item);
    await prefs.put(KEY_LIST, JSON.stringify(list));
    await prefs.flush();
  }

  private async submit(): Promise<void> {
    const trimmed = this.content.trim();
    if (trimmed.length === 0 || this.isSubmitting) {
      return;
    }
    this.isSubmitting = true;
    const context = this.getUIContext().getHostContext() as common.Context;
    const user = await AuthStore.getCurrentUser(context);
    const item: FeedbackItem = {
      id: 'fb_' + Date.now().toString(),
      content: trimmed,
      contact: this.contact.trim(),
      userId: user ? user.userId : '',
      createdAt: Date.now()
    };
    try {
      await Feedback.saveToLocal(context, item);
      try {
        promptAction.showToast({ message: '感谢反馈，已提交' });
      } catch (_t) {
      }
      this.content = '';
      this.contact = '';
    } catch (e) {
      try {
        promptAction.showToast({ message: '提交失败，请重试' });
      } catch (_t) {
      }
    }
    this.isSubmitting = false;
  }

  build() {
    Column() {
      NavBar({ title: '意见反馈', showBack: true });

      Scroll() {
        Column() {
          // 反馈内容卡片，顶部无留白
          Column({ space: 16 }) {
            Column({ space: 6 }) {
              Text($r('app.string.feedback_content_label'))
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.label_secondary'));
              TextArea({ placeholder: '请详细描述问题或建议…', text: this.content })
                .onChange((value: string) => {
                  this.content = value;
                })
                .width('100%')
                .height(120)
                .fontSize(16)
                .backgroundColor($r('app.color.app_background'))
                .borderRadius(10)
                .padding(12);
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start);

            Column({ space: 6 }) {
              Text($r('app.string.feedback_contact_label'))
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.label_secondary'));
              TextInput({ placeholder: '邮箱或手机号', text: this.contact })
                .onChange((value: string) => {
                  this.contact = value;
                })
                .width('100%')
                .height(44)
                .fontSize(16)
                .backgroundColor($r('app.color.app_background'))
                .borderRadius(10)
                .padding({ left: 12, right: 12 });
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start);
          }
          .width('100%')
          .padding(20)
          .backgroundColor($r('app.color.card_background'));
        }
        .width('100%');
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.None)
      .backgroundColor($r('app.color.app_background'));

      Button(this.isSubmitting ? '提交中…' : '提交')
        .width('90%')
        .height(50)
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor(Color.White)
        .backgroundColor($r('app.color.primary'))
        .borderRadius(25)
        .enabled(!this.isSubmitting && this.content.trim().length > 0)
        .margin({ bottom: 32 })
        .onClick(() => {
          this.submit();
        });
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.app_background'));
  }
}
