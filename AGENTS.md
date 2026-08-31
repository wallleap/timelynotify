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
│   ├── ServerSettingsPage.ets    # 服务器设置页
│   └── SharePage.ets             # WebView 页面
├── views/               # 视图组件（Tab 内容）
│   ├── NotifyView.ets            # 通知列表视图
│   └── MineView.ets              # 我的（设置）视图
├── components/          # 可复用 UI 组件
│   ├── ServerSettingsDialog.ets  # 服务器设置弹窗
│   ├── ServerSettingsContent.ets # 服务器列表管理组件
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
```

### 服务器管理流程

```
MineView / ServerSettingsContent
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

- 如果是小补丁，要在当前 tag 的基础（x.y.z）上，让 z +1，运行 `bin/release x.y.z+1`（z 最大只能是三位数）
- 如果是功能更新，直接运行 `bin/release`，会自动让 y +1，并让 z 置 0
- 如果是破坏性更新，则需要让 x +1，y、z 置 0，运行 `bin/release x+1.0.0`

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
