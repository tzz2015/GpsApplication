import { NavBar } from '../common/NavBar';

/**
 * 隐私政策（基于当前 App 功能编写）
 */
@Entry
@Component
struct PrivacyPolicy {
  build() {
    Column() {
      NavBar({ title: '隐私政策', showBack: true });

      Scroll() {
        Column() {
          Column({ space: 16 }) {
            Text(
              '遨游轨迹（以下简称「本应用」）尊重并保护您的隐私。本政策说明我们如何收集、使用、存储与保护您的信息。\n\n' +
              '一、我们收集的信息\n\n' +
              '1. 账号与资料：当您使用华为账号登录时，我们会获取并存储您的用户标识（openID/unionID）、昵称、头像及您主动填写的家族称谓等信息，用于个人中心展示与云端同步。\n\n' +
              '2. 位置与轨迹数据：为提供轨迹记录、打卡点与起终点定位功能，我们会收集并存储您的实时位置、轨迹点序列、海拔及时间戳。上述数据仅在您主动「记录轨迹」「添加打卡点」时产生，并用于绘制路线、统计里程与恢复数据。\n\n' +
              '3. 轨迹内容：您创建的轨迹标题、简介、打卡点名称、人物信息、图文记录及上传的图片，会存储在您的设备本地，并在您登录且联网时同步至华为 AppGallery Connect 云数据库与云存储，用于多设备恢复与（若您选择公开）公开展示。\n\n' +
              '4. 意见反馈：当您使用「意见反馈」时，我们会保存您提交的反馈内容与可选的联系方式，仅用于处理您的意见与改进产品。\n\n' +
              '二、信息的用途\n\n' +
              '· 提供轨迹记录、地图展示、打卡点管理、云端同步与恢复；\n' +
              '· 在您同意的情况下展示公开轨迹；\n' +
              '· 改进产品体验与处理反馈。\n\n' +
              '三、信息的存储与删除\n\n' +
              '· 本地数据存储在您的设备上，卸载应用后将随应用数据清除。\n' +
              '· 云端数据存储在华为云服务（AGC），受其隐私与安全政策约束。您可在应用内删除轨迹或打卡点，相应云端记录将被删除或不再与您账号关联。\n\n' +
              '四、信息共享与披露\n\n' +
              '我们不会出售您的个人信息。仅在以下情况可能披露：法律要求、为保护本应用与用户安全所必需，或经您明确同意。\n\n' +
              '五、权限说明\n\n' +
              '· 位置权限：用于记录轨迹、定位起点/终点与打卡点，以及在地图上显示路线。\n' +
              '· 网络权限：用于云端同步、图片上传与下载。\n' +
              '· 存储/相册（选图）：用于选择打卡点图片并上传至云端。\n\n' +
              '六、未成年人保护\n\n' +
              '若您为未成年人，请在监护人同意下使用本应用。我们不会主动收集未成年人的敏感信息。\n\n' +
              '七、政策更新\n\n' +
              '我们可能适时更新本政策，更新后的版本将在应用内公布。继续使用即视为接受更新后的政策。\n\n' +
              '八、联系我们\n\n' +
              '如有疑问或投诉，请通过应用内「意见反馈」或您留存的联系方式与我们联系。'
            )
              .fontSize(15)
              .fontColor($r('app.color.label_primary'))
              .lineHeight(24)
              .padding(16);
          }
          .backgroundColor($r('app.color.card_background'))
          .borderRadius(12);
        }
        .width('100%')
        .padding(16);
      }
      .layoutWeight(1)
      .width('100%')
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .backgroundColor($r('app.color.app_background'));
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.app_background'));
  }
}
