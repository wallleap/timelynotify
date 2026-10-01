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
