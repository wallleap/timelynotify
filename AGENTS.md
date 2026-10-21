# 通知推送

这是一个使用 ArkTS 开发的，适用于 HarmonyOS 6 以上系统安装的应用源代码

## 项目概览

| 属性         | 值                                                                                 |
|------------|-----------------------------------------------------------------------------------|
| **项目名称**   | TimelyNotify（及时通知）                                                                |
| **包名**     | `cn.oicode.timelynotify`                                                          |
| **技术栈**    | ArkTS + ArkUI（Stage 模型）                                                           |
| **SDK 版本** | 编译 target `26.0.0` / 兼容 `compatibleSdkVersion 6.1.0(23)`（API 23），UI 采用 Hds 沉浸光感方案 |
| **构建系统**   | Hvigor                                                                            |
| **推送服务**   | 华为 AGC Push Kit v3                                                                |
| **外部依赖**   | 无（零第三方 OHPM 依赖）                                                                   |
| **包类型**    | `entry`（HAP）                                                                      |

**核心功能**：通过 HTTP 从自建/第三方服务器拉取推送通知，支持多服务器管理、设备注册、亮/暗双主题。

## 项目架构

### 目录结构

```
entry/src/main/ets/
├── abilities/           # Ability 入口
│   ├── EntryAbility.ets          # 主 UIAbility
│   └── EntryBackupAbility.ets    # 备份扩展 Ability
├── pages/               # 路由页面（@Entry）
│   ├── Index.ets                 # 主页（Tab 导航）
│   └── SharePage.ets             # WebView 页面
├── views/               # 视图组件（Tab 内容）
│   ├── NotifyView.ets            # 通知列表视图
│   ├── ServerView.ets            # 服务与服务器管理视图
│   └── MineView.ets              # 我的（设置）视图
├── components/          # 可复用 UI 组件
│   ├── ServerSwitchDialog.ets    # 切换通知服务弹窗（首页标题，notify/ 目录）
│   ├── server/ServerList.ets     # 服务页的服务器列表管理组件
│   ├── ServerActionDialogs.ets   # 操作菜单弹窗集
│   ├── ClientTokenDialog.ets     # ClientToken 配置弹窗
│   └── showToast.ets             # Toast 提示封装
├── services/            # 业务服务层
│   ├── ServerManager.ets         # 服务器 CRUD + 持久化
│   ├── DeviceRegisterService.ets # 设备注册服务
│   └── NotifyMessageService.ets  # 通知消息拉取服务
├── model/               # 数据模型
│   ├── NotifyMessage.ets         # 通知消息模型
│   └── ServerEntry.ets           # 服务器条目模型
├── config/              # 配置
│   └── ApiConfig.ets             # API 环境配置
├── utils/               # 工具类
│   ├── HttpUtil.ets              # HTTP 请求封装
│   ├── PreferencesUtil.ets       # Preferences 持久化封装
│   ├── ServerUrlUtil.ets         # 服务器地址显示工具
│   └── ImmersiveUtil.ets         # 沉浸式/状态栏高度工具
└── common/              # 全局通用
    ├── AppContextStore.ets       # Context 存储单例
    └── Constant.ets              # 常量（含 AppStorage 刷新信号键）
```

### 数据流架构

```
┌─────────────┐     ┌──────────────────┐     ┌──────────────┐
│  EntryAbility │────▶│ AppContextStore   │────▶│ Preferences  │
│  (初始化)     │     │ (Context 单例)    │     │ (持久化)     │
└──────┬──────┘     └──────────────────┘     └──────┬───────┘
       │                                            │
       ▼                                            ▼
┌──────────────┐                           ┌──────────────────┐
│ Push Kit     │                           │ ServerManager    │
│ (getToken)   │                           │ (服务器 CRUD)    │
└──────┬──────┘                           └────────┬─────────┘
       │                                           │
       ▼                                           ▼
┌──────────────────────┐                 ┌──────────────────────┐
│ DeviceRegisterService │◀────────────────│ HTTP (HttpUtil)     │
│ (注册设备到服务器)    │                 │ (@kit.NetworkKit)   │
└──────────┬───────────┘                 └──────────────────────┘
           │
           ▼
┌──────────────────────┐
│ NotifyMessageService │
│ (轮询拉取通知消息)    │
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│ NotifyView / MineView │
│ (ArkUI 界面展示)     │
└──────────────────────┘
```

## 核心约定

### 状态管理

- **不使用** `@Provide`/`@Consume` 或 `@Link` 等高级装饰器
- **全局状态**通过单例服务类管理（`ServerManager`、`AppContextStore`）
- **持久化**统一使用 `PreferencesUtil`（基于 `@kit.ArkData` 的 `preferences` API）
    - 如果有必要，可接入关系型数据库
- **UI 状态**使用 `@State` + `@StorageLink` 绑定持久化数据

### 服务层模式

所有服务类采用**单例模式**，通过静态方法暴露：

```typescript
// ✅ 正确做法
export class ServerManager {
  static saveServers(servers: ServerEntry[]): void {
    // ...
  }

  static loadServers(): ServerEntry[] {
    // ...
  }
}

// ❌ 避免：实例化服务
```

### 数据模型

模型类使用**静态工厂方法**从原始数据构建：

```typescript
export class NotifyMessage {
  static fromRaw(raw: object): NotifyMessage {
    // ...
  }
}
```

### Context 获取

- 所有需要 Context 的地方通过 `AppContextStore.getContext()` 获取
- Context 在 `EntryAbility.onCreate` 阶段注入

### 网络请求

- 底层通过 `HttpUtil`（封装 `@kit.NetworkKit.http`）
- 生产环境 URL: `timelynotify.oicode.cn`（HTTPS）
- 开发环境支持局域网 IP（HTTP，详见 `network_security_config.json`）
- 认证方式：`X-Gotify-Key` 请求头（支持默认 Base64 Token 或用户自定义）

---

## 代码风格

### 命名规范

| 类型    | 规范               | 示例                                             |
|-------|------------------|------------------------------------------------|
| 类/接口  | PascalCase       | `ServerManager`, `NotifyMessage`               |
| 函数/方法 | camelCase        | `loadServers`, `getMessages`                   |
| 变量/属性 | camelCase        | `deviceKey`, `baseURL`                         |
| 常量    | UPPER_SNAKE_CASE | `PROD_BASE_URL`, `DEFAULT_CLIENT_TOKEN_BASE64` |
| 文件    | PascalCase       | `EntryAbility.ets`, `HttpUtil.ets`             |
| 目录    | camelCase/kebab  | `services/`, `components/`                     |

### 组件装饰器顺序

```typescript
// ✅ 标准顺序
@Component
struct
ComponentName
{
  // 1. @State / @StorageLink 等状态装饰器
  // 2. 普通属性
  // 3. 构建方法
  // 4. 生命周期方法
  // 5. build() 方法
  // 6. 其他方法
}
```

### 导入顺序

1. HarmonyOS SDK API（`@kit.*`）
2. 项目内部模块（`../model/*`, `../services/*` 等）—— 按目录分组

---

## 配置文件操作规则

### 新增页面时必须做的事

1. 创建 `.ets` 文件（如 `pages/NewPage.ets`）
2. 在 `main_pages.json` 中注册路由
3. 如需系统能力（网络等），检查 `module.json5` 中权限是否已声明

### 权限声明

当前已声明的权限（`module.json5`）：

- `ohos.permission.INTERNET`
- `ohos.permission.GET_NETWORK_INFO`

新增系统功能如需额外权限，必须同步更新 `module.json5 > requestPermissions`。

### 主题扩展

- 亮色主题色值：`resources/base/element/color.json`
- 暗色主题色值：`resources/dark/element/color.json`
- 新增色值时，必须在两套主题中都添加对应条目

### 可滚动的长弹窗

新增长内容的居中 `CustomDialog`，以 [`DecryptionSettingsDialog.ets`](entry/src/main/ets/components/DecryptionSettingsDialog.ets) 的解密设置弹窗为布局和沉浸光感参考；`bindSheet` 与全屏页面不直接套用此结构。

- 弹窗背板设置在 `CustomDialogController` 的 options 上：材质获取统一使用 `ImmersiveUtil.getDialogMaterial()`，API 26+、用户开关及实例加载判断只在 util 中实现；返回材质时设置 `backgroundColor(Color.Transparent)` 且不设 blurStyle，返回 `undefined` 时走原有 `backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THIN)` 降级。`bindSheet` 使用 `getEnabledSystemMaterial('sheet')`，Menu 使用 `withImmersiveMenuMaterial()`，组件不得自行判断 SDK/设备材质能力或直接创建 `ImmersiveMaterial`。内容根节点保持透明，不在内部另铺一层模糊背景，亮暗主题都要检查。`getDialogBackgroundOptions()` 用于 `promptAction.showDialog` 系统确认框。
- 修改沉浸光感相关代码后，运行 `bash .github/scripts/check-immersive-boundary.sh`；构建检查工作流也会执行同一检查。新增入口应先扩展 `ImmersiveUtil.ets`，不要在组件中导入 `uiMaterial`、查询 SDK/设备材质能力或实例化材质。
- 标题、正文与底部操作区分成三段，各自控制留白；仅正文滚动，标题和操作按钮固定。内容根节点及按钮区域保持透明，不额外铺同色遮罩或模糊背景。
- 解密设置弹窗在沉浸分支使用 `HdsNavigation` 的 `MODAL` 标题栏，表单 `Scroller` 绑定 `GRADIENT_BLUR`；非沉浸分支保留普通标题。底部操作区仍在滚动区外，标题栏效果需经模拟器或设备实测，不能仅凭构建结果认定。
- 解密设置弹窗先按统一 controller options 打开，再在内容 `onAppear` 后异步加载配置并更新内部 `@State`。模拟器中曾观察到打开前读取 Preferences 时背板变白，而打开后读取仍透；这是该弹窗的实测时序约束，不应推断成所有弹窗或 Preferences API 的通用规律。避免为传配置引入父组件 `@Link`：该方案曾导致运行时闪退。
- 新增长弹窗须分别检查初始、滚动、回弹、底部及亮暗主题；构建通过不能替代模拟器/设备视觉验证。排查“发白/不透明”时要在同一背景下与参照弹窗对比，并同时核对材质 options、打开时序及内容背景，不要仅凭一张浅色背景截图下结论。

---

## 关键工作流

### 设备注册流程

```
EntryAbility.onCreate
  → bootstrapServerManager()（ServerManager 异步加载，并行）
  → silentRegister()
      ├─ pushService.getToken() → 与缓存 device_token 比对
      │     └─ 变更 → 遍历所有已注册 server 重绑（新 token + 旧 device_key）
      ├─ ensureRegistered：无缓存 key → 无 key 注册 → 服务端生成 device_key
      └─ syncCurrentServerKey：GET /register/:device_key 校验
            ├─ 有效 → 直接用
            ├─ 无效 → POST /register 还原（新 token + 旧 key）
            └─ 无本地 key → POST /register 重置 → 服务端生成新 key
  → per-server 持久化（自定义 server 存 server_list_json，内置 server 存
    server_builtin_device_keys），同时写全局 device_key 兼容旧链路
```

### 通知拉取流程

```
NotifyView.getMessages → GET /:device_key/message (Header: X-Gotify-Key)

全量刷新（重置列表/分页）触发点：
  - 组件初始化 / 服务器切换 / 下拉刷新
  - 切回「通知」Tab（homeTabIndex watch）
  - App 回前台 / 点击系统通知拉起（EntryAbility onForeground/onNewWant
    经 AppStorage 信号 KEY_NOTIFY_REFRESH_SIGNAL 通知 NotifyView）

增量轮询（「通知」Tab 可见期间，间隔 15s）：
  - 仅插入 id > 当前列表最大 id 的新消息（不重置分页、不打断滚动位置）
  - 启停条件：通知 Tab 可见 && 主页栈顶（Index onPageShow/onPageHide
    经 AppStorage KEY_INDEX_PAGE_VISIBLE 控制）&& App 前台

删除流水消费（syncSingleServer，deletedSince 随 meta.delCursor 持久化）：
  - 每页先按 deletions.extraIds（Bark delete=1 墓碑）删除本地 extras.id 命中的
    副本，再落库本页消息；deletions.ids/purges 绝不消费（客户端迁移后删除远程
    副本会产生同 id 墓碑，消费会把刚落库的消息误删）
  - 只要响应携带 deletions 信封就推进保存 delCursor（extraIds 为空也推进）；
    delHasMore=true 时消息翻页结束后用 limit=0 空消息页继续拉取直到 false
  - reset=true（游标过旧流水被压缩）：记 warn 继续，不清空本地库
```

### 服务器管理流程

```
ServerView / server/ServerList
  → ServerManager.addServer(name, url) → 保存到 Preferences
  → ServerManager.removeServer(id) → 保存到 Preferences
  → ServerManager.loadServers() → 刷新 UI
```

---

## 构建与验证

```bash
# 构建命令
hvigorw assembleHap

# 常见检查方式
# 使用 builtin_check_editor_errors 检查语法错误
# 使用 builtin_execute_build_command 编译验证
```

### 常见构建问题

- **模块未注册**：新页面未在 `main_pages.json` 中注册
- **权限未声明**：使用了需要权限的 API 但未在 `module.json5` 声明
- **API 版本不兼容**：使用了高于兼容版本 `6.1.0(23)`（API 23）的运行时 API（编译 target 26.0.0 的 Hds/beta UI API
  除外，低版本设备需运行时兼容分支）
- **类型未声明/不正确**

---

## Git 操作

大小写不敏感，要改例如 `mineView` 为 `MineView`，需要先改成其它的，例 `mineView` → `tempView` → `MineView`

### 开发

main 为保护分支，编写代码之前，必须保证在 main 分支 pull 同步了最新代码，然后根据需求创建/切换分支（switch）

**新功能、需求开发**

分支名 `feature/xxx`，例 `feature/tab-immersive`，拆分多次 commit，不要累积到一起再 commit，功能开发测试完成 push

**普通 bug**

分支名 `bugfix/xxx`，例 `bugfix/text-display`，多次 commit，修复测试完 push

**紧急修复 bug**

分支名 `hotfix/xxx`，例 `hotfix/mineView-crash`，修复完立即 commit push，线上立即 merge 并发版

> feature、bugfix 不着急 merge；如果 coding 时发现 main 已修改，要及时 pull main 到本分支并处理冲突；feature/bugfix/hotfix
> 分支在 PR/MR 合并到 main 分支之后按需删除

### 发版

本地不修改版本号

使用 `bin/release` 脚本发版，会自动切 main 分支，打 tag

- 运行 `bin/release`，在菜单中选择 major/minor/patch（最近 tag 为 beta 时还可选 current），然后选择 beta 测试版或 stable 正式版；每个选项会显示目标版本号
- 不再手动传版本号；非交互模式需同时指定 `--bump`、`--stage` 与 `-y`，可先加 `--dry-run` 预览
- beta 自动顺延 `-beta.n`（最多 98），正式版无后缀；两者共用双位 versionCode slot，正式版为 99
- AGC 包内 `versionName` 不使用 `-beta`：测试版 `v1.2.0-beta.1` 映射为 `1.2.0.1`，正式版 `v1.2.0` 仍为 `1.2.0`

打完 tag 自动 push，GitHub 自动注入版本号，签名构建，传到 AGC、Release

---

## AI 助手操作规范

1. **修改前先读**：始终先读取目标文件的完整内容后再修改
2. **匹配代码风格**：严格遵循上述命名规范和装饰器顺序
3. **配置同步**：任何结构性变更（新页面、新权限、新模块）必须同步更新对应的配置文件
4. **主题一致性**：UI 颜色变更必须同时更新亮色和暗色两套主题
5. **Context 安全**：不要尝试在其他地方创建 Context，始终使用 `AppContextStore`
6. **单例模式**：服务层始终使用静态方法，不实例化服务类
7. **零外部依赖**：项目当前无外部 OHPM 依赖，引入新依赖前需确认必要性
8. **网络安全**：局域网 HTTP 请求需确认 `network_security_config.json` 中已允许目标域名/IP
9. **写代码前先询问**：有不清楚的地方不要先写代码，先引导询问，获得明确答复再开始
10. **代码注释**：所有新增代码必须包含必要的注释，包括函数、类、变量等
11. **先查找文档并输出链接，用户确认后再写代码**：在写代码前，先查找相关文档/案例，确认无误后再开始写代码

---

## 相关链接

- **API 文档**：本仓库 [SERVER_API.md](SERVER_API.md)
- **HarmonyOS 文档**：编译 target 26.0.0 / compatibleSdkVersion 6.1.0(23)

<!-- aoci:begin -->
## AOCI 仓库认知

AOCI 为本仓库维护一个稳定、可版本化、可增量更新的仓库级认知层，供模型跨任务复用对系统的理解。

`aoci.txt` 是面向模型的结构化认知索引。它以每个受管理文件、数据库表或其他受管理对象一条独立 Entry 的方式，用符号标签与 F/R/A/S 语义表达对象的核心职责、重要关系、对外契约，以及理解或修改系统时必须知道的非显然约束和设计决策。

Header、目录段和全部 Entry 共同组成完整仓库索引，可以覆盖前端、后端、配置、数据库结构及其他受管理内容。受管理内容发生变化时，通常只需维护受影响的认知条目，不需要重新生成整个索引。

AOCI 提供系统架构、对象职责、重要关系、对外契约和关键约束的高密度视图。

### 工作原理

AOCI 采用“模型生成、模型读取”的认知闭环。

Header、Entry 和 Curation 语义的创作只按当前机器签发的 Plan 与实时 Guide 执行；由 Host 模型基于当前绑定证据独立完成。

Entry 的语义必须来自模型对真实证据的理解。不得仅依据路径、文件名、扩展名、AST、符号列表、依赖扫描、正则、固定模板或规则引擎推导、预填、拼接或改写索引语义。

对 Fresh Bootstrap，只按当前机器签发的 Plan 和实时 Guide 执行。当它们要求创作时，Host 模型创作 Root、Meta、Tag 和 F/R/A/S，提供 authoring-run 声明，并把它绑定到 Plan、Evidence 与完整 Candidate。不得要求 AOCI 填写 `origin=host_model`、制造 Receipt 或把程序生成的 Framework 当作语义。本文件不自行重建 Onboarding 流程。内部批次不是用户决策；只有遇到既有批准边界或真实的安全、漂移、CAS、Recovery 条件才停止。

### 最小使用入口

- `aoci_rules`：取得当前AOCI版本的会话运行合同。
- `aoci_overview`：建立或恢复本仓库的完整认知。
- `aoci_maintain`：受管理对象达到最终稳定状态后检查认知是否需要维护。
- `aoci_update_entry`：提交与当前证据和源码摘要绑定的完整语义更新批次。
- `aoci_report`：仅当当前布局和工具状态支持时，在证据不足、无法可靠生成语义时登记待办，不猜写。

其他MCP工具、CLI命令、参数和专项流程，以当前工具说明、Guide和 `--help` 返回内容为准，不在本文件中重复完整手册。

本区块只规定仓库接入、认知使用和收尾原则。`aoci_rules` 承载当前会话合同，Guide实时输出承载当前Plan的执行顺序与停点，工具Schema、Spec和Validator承载机器结构与判据；Prompt、Description、README和静态文档不能覆盖这些机器事实。

### 建立、生成和恢复认知

1. 每个新的 Agent Run 开始时，应先判断：

   - 本仓库是否已经存在可用的完整AOCI索引；
   - 当前上下文中是否已有与本仓库根、当前索引版本和当前AOCI服务相匹配，并且模型仍可可靠使用的完整仓库认知。

2. 仓库已经存在可用的完整索引，但当前Run没有可靠完整认知时，先调用 `aoci_rules`，再调用 `aoci_overview`。

   完整认知仍可靠时直接复用。局部不确定本身不要求机械重读系统全貌。

   本Run从已知Host上下文压缩恢复时（包括宿主注入的压缩摘要），必须把此前模型认知视为不可靠。压缩handoff不得保留或摘要正式Whole-Index，也不得保留或摘要任何Overview Header、Entry、Chunk、Challenge或Attestation正文；只能保留安全续接所需的receipt身份、未完成write或Recovery状态，以及立即重载指令。复制进handoff的Whole-Index语义或receipt不能证明恢复后模型的当前认知可靠。若当前上下文已无法可靠保留运行合同，先调用 `aoci_rules`。继续业务任务前，使用 `refresh_reasons=["context_compaction"]` 和新的 `refresh_event_id` 调用普通完整Whole-Index `aoci_overview`（不设置 `check_only` 或设为false）；不得使用 `check_only` 或认知probe。原样跟随每个 `next_cursor` 直到 `completed=true`，确认交付，并且只基于新交付正文提交一次Attestation。完成这次新的完整传输后，即使Attestation为partial或fail也消费该generation，并按既有合同继续source-bound任务，不再自动调用第二次Overview。

   AOCI可以针对 `context_compaction`、项目 `cognition_refresh_threshold` 下的机器 `semantic_threshold` 或主要 `phase_transition` 提供checkpoint与认知状态事实。只需要这些紧凑事实时使用 `check_only=true`；这些事实只向Agent提供建议，不替模型决定是否需要系统全貌。

   Agent显式调用普通 `aoci_overview`（未设置 `check_only` 或为false）时，只要能形成一致的CognitionSet，AOCI必须完整交付请求scope。不得因为已有receipt、阈值未达到或没有待处理刷新原因而抑制正文。正式认知Dirty或Stale时仍交付正文，但必须标记不可靠。存在未决恢复或无法形成一致snapshot时失败关闭，不返回混合正文。

   普通Overview返回 `continuation_required=true` 时，必须原样提交 `next_cursor` 并自动继续到 `completed=true`。不得询问用户、开始业务任务或给出阶段性系统结论。Host截断、缺块、重复、乱序、cursor失败、Index变化或`chunk_tokens`变化时停止本次认知链。Attestation完成前不得用Memory、源码、Spec、`aoci.txt`、历史会话、scope、search或Entry读取修补或补充Whole-Index认知。Challenge ordinal是正式Entry序列中的1-based位置；Header内容、注释、空行、Section/Overview/Chunk Marker、Receipt与Metadata均不计数，Chunk Receipt ordinal使用同一序列。Attestation必须原样回绑本次Challenge发布的当前`index_sha256`、`entry_sequence_sha256`与`entry_count`；旧Index、旧Entry序列、旧数量或旧Attestation均无效。完整链结束后只正式提交一次既有模型认知Attestation；同一响应只允许一次不改变语义答案的JSON Schema或字段格式修正。对象、Tag或F不匹配即失败且认知吸收不确定，不得语义重试或旁路补答。首次认知失败时还不得执行Root/Meta、Migration、全局布局或其他未重新绑定的系统级决策。上下文压缩刷新若传输完整、认知身份不变、治理对齐且没有Recovery或第三方冲突，即使Attestation为partial或fail也消耗该refresh generation，并继续原任务，不再自动重读Overview。`system_mastery_percent`只自评系统框架——架构、职责、强关系、稳定外部契约以及高熵安全和维护约束——不表示完整实现或运行实况知识；机器索引覆盖率必须分开。默认只向用户输出由本次真实覆盖率、Challenge、块数、Token和掌握度生成的规定成功或失败一句话。Host截断时提示用户把 `overview_delivery.chunk_tokens` 设置为更小的合法值后重新开始，不得自动修改。

   加法认知等级必须与严格证明字段分开解释。`delivery_verified`表示已加载Index且Host交付已确认，但完整认知验证仍未完成；应表达为“已加载且交付已验证”，不得描述为“没有认知”或“没有理解系统”。`cognition_verified`要求Attestation通过（Challenge至少80%的ordinal完全正确且对象身份至多失手一处），`cognition_governed`还要求治理对齐。通用完整读取失败句只用于真实交付故障。

   当Overview响应包含可选`cognition-state/v2`投影时，必须分别解释各维度。其Level止于`model_cognition_usable`；`strict_attestation_verified`、`governance_aligned`与`current_system_cognition_reliable`都是独立状态，绝不参与该Level。ordinal、对象身份、Tag或核心F不匹配可以导致严格Attestation失败，而模型认知仍然可用；不得仅凭这种不匹配就宣称模型没有理解系统。只有`current_system_cognition_reliable=true`允许无保留地声称当前完整系统认知可靠。投影缺失时继续使用上述Legacy解释。

   普通的只读审计、分析、检查、不修改代码或不提交、不push，不自动等于严格零写入，也不改变上述认知有效性判断。Codex Memory和历史Skill只能辅助恢复经验、用户偏好与调查方向，不能替代与当前仓库根、索引摘要、AOCI服务身份和认知范围匹配的当前认知收据；项目AGENTS和当前AOCI身份在AOCI状态上优先于历史Memory。

   只有用户明确禁止Ledger、元数据、`.aoci`运行资产及任何文件写入时，才按严格零写入处理。若必要的认知建立与该边界冲突，必须报告冲突并请求用户裁决或建议使用隔离副本，不得静默以Memory替代当前仓库认知。

3. 仓库没有可用的完整索引，或当前只有最小骨架、Header不完整、Entries未完成、必要Curation尚未裁决时，如果需要建立正式完整AOCI索引，先取得 `aoci_rules`，然后进入当前AOCI Guide。由Guide依据仓库真实状态决定下一阶段并完成必要安全步骤。

   `aoci_maintain` 不替代索引建立流程。

   不在本文件中自行重建或硬编码完整索引生成状态机。

4. 在长程任务中，模型负责保留当前认知收据并正确使用刷新门禁：

   - Host报告上下文压缩或模型已知系统全貌丢失时，执行上述强制 `context_compaction` 重载规则；AOCI不能自行推断Host事件；
   - 进入真正的主要阶段时声明 `phase_transition`，不得把函数、测试运行或小步骤当作阶段；
   - 在有用的稳定检查点通过 `check_only=true` 取得机器语义计数；
   - 除已知压缩的强制重载外，由Agent判断当前任务是否需要再次显式获取指定scope或完整Overview；
   - 在维护和对齐完成前，保留AOCI报告的Dirty或Stale可靠性状态。

### 任务收尾与认知维护

5. 纯只读问答、分析、版本核验，或没有产生受AOCI管理对象变化的任务，不需要调用维护工具。当前AOCI版本是任意`aoci_overview` check_only或`aoci_maintain`响应里的`cognition_receipt.mcp_service_version`；二进制路径是项目`.mcp.json`里的`command`，CLI不必在PATH上。

6. 发生受AOCI管理对象变化时，待其达到本次任务的最终稳定状态后，只调用一次 `aoci_maintain`。不要在每次中间修改后逐文件维护。

7. 若维护结果返回真实语义候选，Host 模型必须基于每个候选绑定的对象和必要证据，独立创作完整标签与F/R/A/S更新。通过 `aoci_update_entry` 一次提交当前机器签发批次的完整候选集合，同时原样保留每项 `source_sha256`、`candidate_id` 与对应domain批次身份。`max_entries`只限制单次请求和原子事务，不限制logical plan、Whole-Index或Managed Scope。`remaining`非零时，在当前批次成功Apply后重新调用Maintain并从新preimage继续；绝不能为满足transport上限缩减Index覆盖或自行截取返回批次。

   没有足够证据且当前布局支持 `aoci_report` 时，使用它而不猜测、套用模板或为消除待办而生成缺乏证据的认知。

8. 必须遵守工具返回的结构化状态和安全边界：

   - `repair_required`：只修复明确命中的候选，再重新提交当前机器签发的完整批次；
   - `stopped`：结束当前写入尝试并检查 `failed_step`、错误、正式写入证据与Recovery。auto模式下，已证明零写入则记录closure并重新Plan；完整Intent和可证明postimage则Resume；策略要求Rollback且preimage可证明则精确恢复后重新Plan。只有证据不足、第三方正式字节冲突、需要审批或外部动作，或命中其他真实安全边界时，才停止整个用户任务；
   - 冲突、审批、人工裁决、权限和安全信号不得忽略；
   - 已经对齐后不得重复维护或重复写入；`refresh_ready_for_overview` 是checkpoint事实，由Agent决定是否为下一阶段请求普通完整Overview。

   维护完成后如果又修改了任何受管理对象，之前的维护结果失效，应在新的最终稳定状态重新完成收尾。

9. 用户只限制业务文件范围，但没有明确禁止仓库托管资产时，AOCI托管资产可以在收尾阶段为保持认知一致而更新，并应在审计和提交中与业务文件区分。

   用户明确禁止修改 `aoci.txt`、`.aoci`、元数据或任何额外文件时，以用户限制为准，不得写入，并如实报告剩余不一致。

### 专项流程

初始化、完整索引生成、Header生成、Entries生成、数据库结构索引、Curation、人工评审和故障恢复，只按当前AOCI Guide或工具在对应阶段返回的指令、命令和安全停点执行。

不预加载、不猜测，也不自行重建这些专项流程。平台调用方式、请求格式、批次上限、审批规则、索引格式细节和恢复步骤由对应Guide、工具说明、模型Prompt和CLI帮助按需提供。
<!-- aoci:end -->
