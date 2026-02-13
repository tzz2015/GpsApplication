# AGC 签名证书一致性检测不通过 — 排查与解决

上传软件包到 AppGallery Connect（AGC）时，若提示**签名证书一致性检测不通过**，说明当前安装包使用的签名与 AGC 中为该应用配置的证书/Profile 不一致。按下面步骤排查并修正。

---

## 一、原因说明

- **上传到 AGC 的包**必须使用**发布证书 + 发布 Profile** 签名，且该证书和 Profile 必须在 AGC 中为该应用配置并一致。
- 当前工程里使用的是**调试**材料：`gps_debug.cer`、`gps_debugDebug.p7b`（文件名中的 Debug 表示调试用）。  
- 用**调试**证书/Profile 签出来的包上传到 AGC，会触发「签名证书一致性检测不通过」。

---

## 二、解决步骤（必须用发布证书 + 发布 Profile）

### 1. 在 AGC 确认应用与包名

- 登录 [AppGallery Connect](https://developer.huawei.com/consumer/cn/service/jms/agc/index.html)
- 进入对应项目 → **我的应用** → 找到「遨游轨迹」应用（或你上传时选的应用）
- 确认**包名**与工程一致（如：`com.lyf.aoyou`，以 `entry/src/main/module.json5` 或 AppScope 配置为准）

### 2. 在 AGC 申请「发布证书」（若还没有）

- 若从未申请过**发布证书**：
  - 在 DevEco Studio：**Build → Generate Key and CSR**
  - 生成新的 `.p12` 和 `.csr`（建议单独保存，专用于发布，不要和调试混用）
- 在 AGC：**用户与访问 → 证书、APP ID 与 Profile**（或项目内「证书与 Profile」入口）
  - 点击 **新增证书**，类型选 **发布**
  - 上传上一步的 `.csr`
  - 下载生成的 **发布证书** `.cer`，保存好

### 3. 在 AGC 申请「发布 Profile」（若还没有）

- 同一 AGC 入口下，**Profile** → **添加**
  - 类型选 **发布**
  - 选择**本应用**（APP ID / 包名对应）
  - 选择上一步的**发布证书**
  - 按需勾选权限等，生成并下载 **发布 Profile** `.p7b`

### 4. 在工程中配置「发布」签名（与 AGC 一致）

- 本工程已在 **build-profile.json5** 中预留 **release** 签名配置，需你补全材料与密码：
  - 把 AGC 下载的**发布**.cer、**发布**.p7b 和发布用**.p12** 放到 `signingConfigs/`，并命名为：
    - `gps_release.p12`（发布用密钥库）
    - `gps_release.cer`（AGC 发布证书）
    - `gps_release.p7b`（AGC 发布 Profile）
  - 在 **build-profile.json5** 的 `signingConfigs` 里找到 **name 为 "release"** 的项，将：
    - `storePassword`、`keyAlias`、`keyPassword` 改为你的发布密钥库/别名/密钥密码（不要继续使用「请替换为…」占位符）。
- 若你使用其它文件名或路径，可修改该 release 配置中的 `storeFile`、`profile`、`certpath` 为实际路径。
### 5. 用「发布」配置打正式包并上传

- 在 DevEco Studio：
  - 菜单 **Build** → **Build APP(s)**（或 **Build Hap(s)/APP(s)**）
  - 在构建对话框中**选择 product 为 release**（不要选 default，default 使用调试证书）
  - 构建完成后，在工程根目录 `build/outputs/default/` 下找到生成的 `xxx-signed.app`（若选了 release 则应为 release 签名）
- 若通过命令行构建，请使用带 `-p product=release` 的构建命令。
- 将此次用 **release** 签名的 `.app` 上传到 AGC，再执行提交/检测，签名证书一致性即可通过。

---

## 三、自检清单

- [ ] AGC 中该应用的包名与工程包名一致  
- [ ] 已使用 **发布证书**（.cer）和 **发布 Profile**（.p7b），不是 debug  
- [ ] 工程中 build-profile.json5 里用于打上传包的 product 使用的是上述发布 signingConfig  
- [ ] 上传的 .app 是本次用该发布配置重新构建的，不是旧的 debug 包  

---

## 四、常见错误

| 情况 | 处理 |
|------|------|
| 仍用调试证书/Profile 打上传包 | 必须改为发布证书 + 发布 Profile，并在工程里用 release 配置打包 |
| AGC 应用包名与工程不一致 | 在 AGC 修改应用包名与工程一致，或重新创建应用并再申请发布 Profile |
| 证书与 Profile 不匹配 | Profile 申请时选的证书必须与打包用的 .cer 一致；.p12 与 .cer 需来自同一套 CSR |
| 换了电脑/密钥 | 若用新 .p12 重新在 AGC 申请了发布证书和 Profile，工程里要全部改为新 .p12、新 .cer、新 .p7b |

按上述步骤配置后，重新打 release 包再上传，签名证书一致性检测即可通过。若 AGC 有具体报错文案（如证书 SHA 不匹配），可把提示贴出以便进一步对照。
