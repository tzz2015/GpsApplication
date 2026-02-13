# 遨游轨迹 App UI 设计系统 v3.0 — 传承·山林 + 鸿蒙规范合规

> 在 v2.0 视觉基础上，**强制对齐鸿蒙设计规范与应用审核要求**，并纳入 **ui-ux-pro-max** 设计系统输出。  
> 单一真相源：`doc/prototype/prototype.html`；ArkTS 实现须同时满足本设计系统与 [华为设计指南](https://developer.huawei.com/consumer/cn/doc/design-guides/design-concepts-0000001795698445)。

---

## 一、设计原则（继承 v2.0 + 合规优先）

1. **鸿蒙规范优先**：所有导航、Tab、按钮、触控区域均按华为设计指南与 ArkTS 组件规范实现，确保应用审核通过。
2. **情感契合**：扫墓轨迹 = 家族记忆 + 山路行走；视觉保持温暖、庄重、易读（v2.0 传承·山林）。
3. **可访问与触控**：对比度 ≥ 4.5:1，可点击区域 ≥ 44vp×44vp，支持焦点与 `prefers-reduced-motion`（与 ui-ux-pro-max Accessible & Ethical 一致）。
4. **禁止 emoji 作图标**：导航、Tab、按钮等一律使用 **图片资源（PNG/SVG）或 HarmonyOS Symbol**，不得使用 emoji（如 🏠、👤）。

---

## 二、鸿蒙设计规范合规（必遵）

### 2.1 底部导航栏（TabBar）

- **组件**：使用 ArkTS **Tabs** + **TabContent**，`barPosition: BarPosition.End`，`barMode: BarMode.Fixed`。
- **高度**：`barHeight(56 + 安全区)`（单位 vp），或 56vp 内容区 + 底部安全区单独预留；总高度需包含安全区，避免内容被遮挡。
- **数量**：3–5 个入口；本项目为 2 个（首页、个人中心），符合规范。
- **每项内容**：**图标 + 文字**。图标使用 `Image` 引用 `resources/base/media/` 下资源（`ic_tab_home.svg`、`ic_tab_profile.svg`），**禁止使用 emoji**。文字建议 ≤4 个汉字（如「首页」「个人中心」）。设计稿配套 SVG 已放入 `entry/src/main/resources/base/media/`，见下文「设计稿对应 SVG 图标」。
- **参考**：[HarmonyOS 导航设计](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ui-design-navigation-icon-type)、[Tabs 组件](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-container-tabs)。

### 2.2 首页内顶 Tab（我的轨迹 | 公开轨迹）

- **组件**：使用 **Tabs**，`barPosition: BarPosition.Start`，`barMode: BarMode.Fixed`。
- **高度**：`barHeight(44)`（vp）可接受；触控区域通过 padding 保证 ≥ 44vp 高。
- **样式**：选中态主色文字 + 底部短条（如 24vp 宽、3vp 高）；未选中间色（如 label_tertiary）。文字 ≤4 个汉字。

### 2.3 触控与安全区

- **最小可点击区域**：≥ **44vp×44vp**（华为与 WCAG 一致）。
- **安全区**：顶部状态栏区域、底部安全区（如 34vp）须预留，TabBar 的 `barHeight` 或容器 `padding` 须包含底部安全区。
- **焦点**：可聚焦控件须有可见焦点环（如 2–3vp 描边）。

### 2.4 应用图标与资源

- 应用图标按华为分层规范（前景+背景），见 [应用图标规范](https://developer.huawei.com/consumer/cn/design/resource/)。
- TabBar、导航栏所用图标使用 **图片资源** 或 **HarmonyOS Symbol**，不得使用 emoji。

### 2.5 登录按钮

- 使用华为账号一键登录时，按钮颜色与文案须符合华为要求（如红色 `#CF0A2C`、官方文案）。

---

## 三、色彩系统（同 v2.0）

| 用途 | 变量名 | 色值 |
|------|--------|------|
| 主色 | primary | #A0522D |
| 主色深 | primary-dark | #8B4513 |
| 主色浅 | primary-light | #FDF5F0 |
| 强调/路径 | accent | #4A7C59 |
| 强调浅 | accent-light | #EEF5EE |
| 成功 | success | #4A7C59 |
| 警告 | warning | #B8860B |
| 危险 | danger | #A63D3D |
| 华为登录红 | — | #CF0A2C |
| 页面背景 | bg | #FAF8F5 |
| 卡片 | card | #FFFEFB |
| 主文字 | text-primary | #2C2825 |
| 次要文字 | text-secondary | #5C564D |
| 提示文字 | text-hint | #8E8880 |
| 分割线/边框 | border | #E8E4DF |

（场景渐变、字体与排版、间距与圆角、阴影同 v2.0，此处不重复。）

---

## 四、核心组件约定（含鸿蒙与 ui-ux-pro-max）

- **底部 TabBar**：Tabs `barPosition: BarPosition.End`，`barMode: BarMode.Fixed`，`barHeight(56 + bottomSafeHeight)`，每项 **Image 图标（SVG）+ Text**，图标资源来自 media，禁止 emoji。
- **首页顶 Tab**：Tabs `barPosition: BarPosition.Start`，`barHeight(44)`，选中态 primary 文字 + 底部指示条，触控区 ≥ 44vp。
- **主按钮**：高度 ≥ 44vp，圆角 24vp，背景 primary 或 accent，文字 #FFFEFB。
- **所有可点击区域**：≥ 44vp×44vp；焦点态可见。
- **图标**：统一使用 media 或 Symbol，**禁止 emoji**。

---

## 五、ui-ux-pro-max 设计系统摘要

- **本次生成**：`search.py "mobile app family memory trail nature heritage accessible" --design-system -p "遨游轨迹"`  
- **Pattern**：App Store Style Landing（落地页可参考）；应用内以 Storytelling + 清晰导航为主。  
- **Style**：**Accessible & Ethical** — 高对比、大文字（16px+）、焦点态、44×44px 触控、WCAG、reduced-motion。  
- **Colors**：Nature green + 暖色（与 v2.0 陶土褐+山林绿一致）。  
- **Avoid**：小字、复杂导航、**emoji 作图标**。  
- **Pre-Delivery Checklist**：无 emoji 图标、cursor-pointer/点击态、对比度 4.5:1、焦点可见、prefers-reduced-motion、响应式断点。

---

## 六、ArkTS 实现检查清单（审核前必查）

- [ ] 底部 TabBar 使用 **Tabs**，`barPosition: BarPosition.End`，`barMode: BarMode.Fixed`。
- [ ] 底部 Tab 每项为 **Image（图标 SVG）+ Text（文字）**，图标为 media 下 SVG 资源，**无 emoji**。
- [ ] TabBar 高度含底部安全区（如 `barHeight(56 + bottomSafeHeight)` 或等效 padding）。
- [ ] 首页内「我的轨迹」「公开轨迹」使用 Tabs 或等效，触控高 ≥ 44vp。
- [ ] 所有按钮、列表项、Tab 项可点击区域 ≥ 44vp×44vp。
- [ ] 主文字与背景对比度 ≥ 4.5:1。
- [ ] 登录按钮为华为红 #CF0A2C，文案符合华为要求。
- [ ] 无 emoji 作为 UI 图标（导航、Tab、按钮等）。

---

## 七、设计稿对应 SVG 图标（供鸿蒙 App 使用）

做设计稿时可一并生成配套 SVG 图标，便于直接用于鸿蒙工程；矢量图不占像素内存、可随 `fillColor` 着色。

### 7.1 规格与风格

- **格式**：**SVG**，单色填充（`fill="currentColor"`），便于在 ArkTS 中通过 `Image.fillColor(Resource)` 随选中态变色（如 primary / label_tertiary）。
- **风格**：传承·山林 — 简洁线型或块面，viewBox 建议 24×24，在界面中以 18–24vp 显示即可。
- **尺寸**：矢量无需固定像素，体积小、不占位图内存。

### 7.2 当前已落库的图标

| 文件名 | 用途 | 路径 |
|--------|------|------|
| `ic_tab_home.svg` | 底部 Tab「首页」 | `entry/src/main/resources/base/media/` |
| `ic_tab_profile.svg` | 底部 Tab「个人中心」 | `entry/src/main/resources/base/media/` |

以上图标已放入上述 media 目录，ArkTS 中通过 `$r('app.media.ic_tab_home')`、`$r('app.media.ic_tab_profile')` 引用；Tab 选中态可通过 `Image.fillColor($r('app.color.primary'))` 等着色。

### 7.3 后续新增图标时

- 设计阶段说明所需图标（名称、含义、风格一致），可生成对应 SVG（推荐单色 currentColor）。
- 放入 `entry/src/main/resources/base/media/`，文件名与 `$r('app.media.xxx')` 中的 `xxx` 一致（不含后缀）。
- 若需多主题，可在 `resources/zh_CN/media/`、`resources/dark/media/` 等限定词目录下放置同名文件。

---

## 八、与 v2.0 的差异

| 项目 | v2.0 | v3.0 |
|------|------|------|
| 规范优先级 | HarmonyOS 兼容 | **鸿蒙规范 + 审核合规** 明确为必遵 |
| TabBar 图标 | 未强制 | **禁止 emoji，必须图片/Symbol** |
| 触控与安全区 | 有提及 | **44vp、安全区、焦点** 明确写入并纳入检查清单 |
| ui-ux-pro-max | 事后校验 | **设计前生成 + 合规章节** 同步写入 |

---

*文档版本：v3.0 | 传承·山林 + 鸿蒙规范合规 + ui-ux-pro-max；实现与原型以本版为准。*
