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
 * 意见反馈页
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
          // 顶部引导区
          Column({ space: 8 }) {
            Image($r('app.media.ic_chat'))
              .width(44)
              .height(44)
              .fillColor($r('app.color.primary'));
            Text('我们想听听你的想法')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.label_primary'));
            Text('你的每一条建议都能帮助我们做得更好')
              .fontSize(13)
              .fontColor($r('app.color.label_tertiary'));
          }
          .width('100%')
          .padding({ top: 28, bottom: 24 })
          .alignItems(HorizontalAlign.Center);

          // 表单卡片
          Column({ space: 20 }) {
            // 反馈内容
            Column({ space: 8 }) {
              Text('问题或建议')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.label_primary'));
              TextArea({ placeholder: '请描述你遇到的问题，或者你希望增加的功能…', text: this.content })
                .onChange((value: string) => {
                  this.content = value;
                })
                .width('100%')
                .height(140)
                .fontSize(15)
                .backgroundColor($r('app.color.app_background'))
                .borderRadius(12)
                .padding(14);
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start);

            // 联系方式
            Column({ space: 8 }) {
              Text('联系方式（选填）')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.label_primary'));
              TextInput({ placeholder: '邮箱或手机号，方便我们联系你', text: this.contact })
                .onChange((value: string) => {
                  this.contact = value;
                })
                .width('100%')
                .height(46)
                .fontSize(15)
                .backgroundColor($r('app.color.app_background'))
                .borderRadius(12)
                .padding({ left: 14, right: 14 });
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start);

            // 提交按钮（内联在表单内）
            Button(this.isSubmitting ? '提交中…' : '提交反馈')
              .width('100%')
              .height(46)
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(Color.White)
              .backgroundColor($r('app.color.primary'))
              .borderRadius(23)
              .enabled(!this.isSubmitting && this.content.trim().length > 0)
              .opacity(!this.isSubmitting && this.content.trim().length > 0 ? 1 : 0.5)
              .margin({ top: 4 })
              .onClick(() => {
                this.submit();
              });
          }
          .padding(20)
          .backgroundColor($r('app.color.card_background'))
          .borderRadius(16)
          .margin({ left: 20, right: 20 });

          // 底部提示
          Text('反馈将保存在本地，后续版本将支持云端同步')
            .fontSize(12)
            .fontColor($r('app.color.label_tertiary'))
            .margin({ top: 16, bottom: 40 });
        }
        .width('100%');
      }
      .layoutWeight(1)
      .width('100%')
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .backgroundColor($r('app.color.app_background'));
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.app_background'));
  }
}
