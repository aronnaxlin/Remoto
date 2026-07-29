# Remoto — Liquid Glass 遥控器任务清单

> 交接对象:负责 Remoto iOS 实现的 Agent。
> 目标:**原生级、大量使用 Liquid Glass、体验对齐 Apple TV 遥控器**的 iPhone 遥控器 App。
> 当前状态:本仓库为骨架;SDK(TVRemoteKit)Phase 1–5 已完成,能力齐全。隔壁 Agent 正在修 SDK 侧 review 出的 bug(见 `../TVRemoteKit/docs/review-phase1-5.md`),SDK API 面已稳定,不阻塞 UI 开发。
> 日期:2026-07-29

---

## 一、必读参考资料(按顺序)

**项目级技能(已安装到 `.claude/skills/`,2026-07-29 由 find-skills 检索安装):**

| 技能 | 来源 | 读它干什么 |
|---|---|---|
| `swiftui-liquid-glass` ⭐ | dimillian(3.7K 安装) | **Liquid Glass 主参考**:决策树、实施/审查清单、降级模式。覆盖了原技能库的空白 |
| `swiftui-expert-skill` | avdlee(27.6K 安装) | SwiftUI 专家:25+ 专题参考(状态管理、动画、性能、列表)。先读它的 `references/latest-apis.md` 防过时 API;`references/liquid-glass.md` 与上一个互补 |
| `xcode-build-fixer` | avdlee(3K 安装) | Xcode 构建报错、签名问题(免费账号 7 天证书)时查 |

**用户级技能(原有,仍有效):**

| 资料 | 位置 | 读它干什么 |
|---|---|---|
| iOS 开发技能(基线) | `skill://ios-application-dev` | HIG 基线:导航、布局、无障碍、权限时机 |
| ├ SwiftUI 设计指南 | `skill://ios-application-dev/references/swiftui-design-guidelines.md` | SwiftUI 组件与反模式 |
| ├ 系统整合 | `skill://ios-application-dev/references/system-integration.md` | **触觉反馈**(遥控器手感核心)、生命周期、权限 |
| └ 图形与动画 | `skill://ios-application-dev/references/graphics-animation.md` | 按钮按下弹性、过渡动画 |

**其他:**

| 资料 | 位置 | 读它干什么 |
|---|---|---|
| 本仓库规则 | `CLAUDE.md` | **品牌无关铁律**:UI 层零 Sony 逻辑 |
| SDK 键词汇表 | `../TVRemoteKit/docs/review-phase1-5-response.md` 末尾 + `RemoteKey.swift` | mvpCore/common/品牌键三层 |
| 真机档案 | `../TVRemoteKit/probes/sony/KD-65X8500F/` | 开发用测试电视的真实能力数据 |

**不要去找 `frontend-design`/`baoyu-design`/`theme-factory`**,那是 Web 的。Liquid Glass 以 `swiftui-liquid-glass` 技能 + 本文 §四 + Apple 官方文档为准。

---

## 二、架构铁律(违反即返工)

1. **UI 层品牌无关。** 不出现 `import TVRemoteKitSony`、不出现 "Sony"/"IRCC"/"PSK" 字样以外的品牌概念。协议 bug 去 TVRemoteKit 修,不在 App 里打补丁。
2. **UI 只认通用键。** 按钮从 `Capabilities.supportedKeys` 动态渲染,不写死。三层键集决定 UI 三层结构(见 §五)。
3. **本 App 是 SDK 的 API 设计验证器。** 哪个功能在 App 里写着别扭,说明 SDK API 设计错了 —— 提出来,不要绕。
4. **无付费开发者账号。** 不碰任何需要 entitlement 的能力(无 SSDP、无 WoL 广播)。Info.plist 需要 `NSLocalNetworkUsageDescription` + `NSBonjourServices`(`_androidtvremote._tcp`、`_googlecast._tcp`),两者都不是 entitlement。
5. **PSK 进 Keychain。** 不进源码、不进 UserDefaults、不出设备。App 除用户自家电视外不发任何网络请求。

---

## 三、任务列表

### Task 0 — 工程骨架
- [ ] Xcode 工程:SwiftUI、Swift 6 language mode、iOS 17 部署(Liquid Glass API 需要 **iOS 26 SDK 编译 + 运行时 availability 判断**,见 §四兼容性段)
- [ ] 本地 SPM 依赖 `../TVRemoteKit`,只链接 `TVRemoteKit` 产物
- [ ] Info.plist:`NSLocalNetworkUsageDescription`(文案:「用于发现并控制你家中的电视」)+ `NSBonjourServices`
- [ ] **不得出现 entitlements 文件**;Xcode 自动生成的带 multicast 的要删掉
- [ ] 免费个人 Team 签名,接受 7 天过期

### Task 1 — 遥控主界面(Liquid Glass 核心,对标 Apple TV Remote)
Apple TV 遥控器的体验要点:**大面积深色留白、触控板居中、按钮浮于玻璃之上、按下有明确的物理反馈**。
- [ ] 深色背景(近黑),内容层**不用**玻璃
- [ ] **方向触控板**:中央大圆角方形区域,支持点按四方向 + 中心确认;玻璃材质(`.glassEffect(.regular.interactive())`)
- [ ] **圆形功能键**:返回、主页、电源、静音 —— 胶囊/圆形玻璃按钮,`.interactive()` 按压态
- [ ] **音量**:拟物音量键(上下一体长条,对标实体遥控器)或 +/- 分体,玻璃材质
- [ ] 每次按键触发 `UIImpactFeedbackGenerator`(不同键不同力度:方向轻、电源重)
- [ ] 按下动画:玻璃压缩回弹(参考 graphics-animation.md)
- [ ] 按钮可见性由 `supportedKeys` 驱动,缺的键不显示(不是置灰)

### Task 1B — Click Wheel 变体布局(iPod 风格,与触控板可切换)
**为什么是可行的:** Click Wheel 的控制词汇与 SDK 通用键 1:1 对应,零 SDK 改动、天然品牌无关。

| Click Wheel | SDK 通用键 |
|---|---|
| 旋转(带步进) | `volumeUp`/`volumeDown`(或导航步进,见下) |
| 上(Menu) | `back` 或 `menu` |
| 中心 | `confirm` |
| 左/右(⏮⏭) | `rewind`/`fastForward`(媒体时)或 `left`/`right`(导航时) |
| 下(⏯) | `play`/`pause` |

- [ ] `ClickWheelView` 组件:外环 + 中心键,`DragGesture` + `atan2` 算圆心角,累加角位移过 ±π 回绕
- [ ] **步进(detent)模型**:每 ~15–20° 一个步进,跨步进触发 `UISelectionFeedbackGenerator` 的 tick —— 这就是 Click Wheel 的灵魂,不能省
- [ ] **网络节流(真实风险,必须处理)**:iPod 滚列表是本地的,我们每个步进都是一次 HTTP 请求。音量不要用旋转狂发 `volumeUp`;做法:读一次 `volumeState`,旋转只改本地值,停止/间隔 ~300ms 后发一次 `setVolume(absolute)`。导航步进则按固定频率上限(如 5 次/秒)发 `press`
- [ ] 旋转语义切换:默认音量;长按环或按上下文(音量 HUD 弹出时)切换。导航模式下旋转 = 上下步进,适合纯列表页,2D 网格页别强用
- [ ] 与 Task 1 触控板布局做成**可切换的两种皮肤**(设置里选),不是替换关系 —— Click Wheel 强在音量/快进退,弱在 2D 网格导航
- [ ] 玻璃呈现:环形 `.glassEffect(…, in: .circle)` + 中心独立玻璃圆;按下区域 morph 反馈
- [ ] 备注(不影响自用):苹果曾下架过仿 iPod 的 App(Rewound)。本项目免费签名自用无所谓;若将来想上架,皮肤要避开 iPod 商标元素(点击器音效名、iPod 字样)

#### 旋转主语义:滚动(对标初代 Apple TV 遥控器 / Siri Remote 圆环手势)

旋转的**默认语义是滚动导航,不是音量**(音量降级为次要模式,如音量 HUD 弹出时接管)。

- [ ] **步进累积器**:角位移持续累加,每过阈值(15–20°)产出一个导航步进(垂直列表:顺时针 = `down`,逆时针 = `up`)
- [ ] **有界队列 + 合并(防「手停电视不停」)**:待发送步进最多积压 2–3 个,超出丢弃;松手即清空。电视 UI 列表本身有界,丢步进比排队滞后感好得多
- [ ] **速率自适应**:发射频率随角速度缩放,上限 ~5–8 步/秒(以实测 IRCC 往返为准,队列不增长即安全)
- [ ] **2D 网格的边界**:旋转是 1D,网格页横行移动靠环的四象限点按(`left`/`right`),旋转只管纵向。别试图猜电视当前界面的方向
- [ ] 惯性滚动(快速甩一下继续滚并衰减):v2 再做,v1 松手即停
- [ ] **视频拖动(jog)的限制**:Siri Remote 圆环能拖时间轴,靠的是精确 seek。本测试机 `avContent` **没有 `setPlayPosition`**(已查 api.json 证实),绝对位置拖动做不了;降级为步进 → `rewind`/`fastForward` 点按式粗调。换机型时重查能力表再启用
- [ ] 音量作为旋转次语义:仅在音量 HUD 显示期间接管旋转,或设置里全局调换主次

### Task 2 — 设备发现页
- [ ] 启动进入发现页:Bonjour + 子网扫描(SDK `discover()`,Phase 6 若未完成先用「手动输 IP」过渡,UI 结构不变)
- [ ] 电视卡片:型号名 + 品牌 + 在线状态;玻璃卡片浮于深色背景
- [ ] **本地网络权限被拒的分支**:SDK 超时报错带 `.possiblyLocalNetworkPermissionDenied` 时,展示「设置 → 隐私与安全性 → 本地网络」引导(不是一句干巴巴的「超时」)
- [ ] 权限请求在**用户点了「搜索电视」之后**发起,不在启动时

### Task 3 — PSK 配对流程
- [ ] 首次连接触发 `.authenticationRequired` → 全屏玻璃 Sheet:电视型号、步骤指引(用 SDK `AuthHint.recoverySuggestion`)、PSK 输入框
- [ ] `.authenticationFailed`(凭据被电视拒绝)与 Required 文案区分:「PSK 不对」vs「需要 PSK」
- [ ] 成功即存 Keychain,之后自动带
- [ ] 403 响应带 `auth_url` 时展示为可点的帮助链接

### Task 4 — 远程键盘(SDK `sendText`)
- [ ] 遥控器主界面固定入口;点击展开文本输入条(玻璃材质输入框)
- [ ] 发送走 `session.sendText()`;`.unsupported` 错误 → 提示「先在电视上打开一个搜索框」
- [ ] 这是对标 Apple TV Remote「键盘自动弹出」的核心差异化功能,交互要做顺:输入中实时回显、发送后清空并给成功反馈

### Task 5 — 二级面板(更多按键)
- [ ] 底部上滑面板(`.presentationDetents`):media 控制(播放/暂停/快进等 common 键)
- [ ] 数字键盘(0–9,折叠)
- [ ] **品牌专属键区**:从 `supportedKeys` 筛 `isVendorSpecific` 的键(Netflix、YouTube…),按名字排列,不需要图标设计

### Task 6 — 状态与反馈
- [ ] 电源状态显示(开机/待机),连接状态指示
- [ ] 音量调节时的当前音量反馈(`volumeState`)
- [ ] 正在播放信息(`nowPlaying`,nil 时正常隐藏区域)
- [ ] 错误统一走 SDK 的 `TVRemoteError` 映射,UI 不解析协议错误

### Task 7 — 打磨
- [ ] Dynamic Type、VoiceOver 标签(每个玻璃按钮都有)、Reduce Motion 下关闭玻璃弹性动画
- [ ] 横屏布局(触控板居左、按钮居右)
- [ ] 真机回归:发现 → 配对 → 全键可用 → 打字 → 后台 15 分钟回前台再按 Home 仍成功(验证 SDK 的 13 分钟唤醒)

---

## 四、Liquid Glass API 速查(2026-07 检索核实,iOS 26+)

```swift
// 基础:默认 .regular 变体 + 胶囊形
Text("Hello").padding().glassEffect()

// 定制:变体 .regular/.clear/.identity,可加 tint、interactive(按压交互)
Text("Key").glassEffect(.regular.tint(.blue).interactive(), in: .rect(cornerRadius: 16))

// 多个玻璃元素要融合/变形时,必须放进容器
GlassEffectContainer(spacing: 20) {
    HStack(spacing: 20) { /* glass buttons */ }
}

// 变形过渡三件套(配 @Namespace)
.glassEffectID("key", in: ns)        // 给元素身份,同 ID 可互相 morph
.glassEffectUnion(id: "g", in: ns)   // 多元素并成一块玻璃
.glassEffectTransition(...)          // 出现/消失方式
```

**设计守则(Apple HIG):**
- 玻璃只用于**功能层**(按钮、工具栏、导航、浮动控件);内容层(列表、正文、媒体)**不要**用
- 不要给所有元素都上玻璃 —— 大面积低对比会很脏
- 重叠的多个玻璃元素用 `GlassEffectContainer`,比独立 `.glassEffect()` 性能好且视觉连贯

**兼容性:** API 为 iOS 26+。部署目标 iOS 17 意味着所有玻璃调用要 `if #available(iOS 26, *)` 包裹并提供 `.regularMaterial`(ultraThinMaterial)降级样式 —— 抽一个 `GlassButton` 组件统一封装,不要散落各处判断。**或者直接把部署目标定 iOS 26**,取决于你的测试机系统版本,开工前确认。

---

## 五、键词汇表 → UI 结构映射

SDK 的通用键(品牌无关)正好对应 UI 三层:

| SDK 层 | 键 | UI 位置 |
|---|---|---|
| `mvpCore`(13) | 方向4 + 确认/返回/主页 + 电源3 + 音量3 | Task 1 主界面 |
| `common` 其余(13) | menu/options/exit、播放控制7、频道/输入3 | Task 5 二级面板 |
| `digit(0–9)`(10) | 数字 | Task 5 折叠数字键盘 |
| 品牌专属(动态) | `sony.Netflix` 等,由 `supportedKeys` 筛出 | Task 5 品牌键区 |

**所有按钮是否渲染,以设备实际 `capabilities.supportedKeys` 为准**,不要假设 36 个全有。

---

## 六、SDK 接口速查(已稳定,可直接依赖)

```swift
import TVRemoteKit   // 唯一 import,不要 import TVRemoteKitSony

let devices = try await TVRemoteKit.discover()          // Task 2(Phase 6 完成后)
let session = try await driver.connect(...)              // 由 discover 结果或手动 IP
try await session.press(.home)                           // Task 1
try await session.setVolume(30) / setMuted(true)
try await session.powerState() / setPower(true)
try await session.sendText("流浪地球")                    // Task 4
try await session.nowPlaying()                           // nil = 没在播,不是错误
let caps = try await session.capabilities()              // 按钮显隐的唯一依据
```

错误处理:`.authenticationRequired(AuthHint)` / `.authenticationFailed` / `.timedOut(hint:)`(hint 带权限引导)/ `.devicePoweredOff` / `.unsupported(feature:)` —— 全部有用户可读的映射,UI 只做展示不做解析。
