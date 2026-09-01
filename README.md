# 及时通知

TimelyNotify 是使用 arkTS 开发的鸿蒙端消息通知 App。

下载链接：<https://appgallery.huawei.com/link/invite-test-wap?taskId=8121c9f6a1255c454c2016bea2f7cce9>

服务器端 [timelynotify-server](https://github.com/wallleap/timelynotify-server) 修改自 Bark-server，因此可以只部署这个服务，实现一个
push 链接同时发送到 iOS 和 HarmonyOS。

> 强烈建议自建服务，相关文档：<https://docs.timelynotify.oicode.cn/deploy/>

TODO:

- [ ] 加密
- [ ] 多语言
- [ ] 等 PushKit API 完善点，实现更多推送参数
    - 实测结论：鸿蒙 Push Kit 通知点击仅支持 `actionType` 0（应用首页）/ 1（应用内页 + params 传数据），无通知栏操作按钮（复制等只能在
      App 内实现）；服务端可扩展 `actionType 1 + abilityAction.params` 传递 messageId/url，客户端按参数分发跳转
- [ ] 内容处理（例如整体复制、复制链接/验证码）

## 功能说明

- 兼容 bark 的所有接口（`/register`、`/push` 等）
- ⚠ 由于鸿蒙 PushKit 只有推送后台消息可以不用保活应用存储消息，但是约束有点多，就只能在服务器端存储消息了

## 应用流程

```text
┌─────────────────────────────────────────────────────────────────┐
│                        应用冷启动                                 │
└─────────────────────────────────────────────────────────────────┘
  EntryAbility.onCreate
    ├─ bootstrapServerManager()          ← ServerManager 异步 load（并行）
    └─ silentRegister()
         ├─ 注入 tokenProvider (pushService.getToken)
         ├─ ① refreshTokenIfNeeded()
         │     ├─ getToken() 与缓存 KEY_DEVICE_TOKEN 比对
         │     ├─ 相同 → 跳过
         │     └─ 变更 → 更新缓存
         │            └─ 遍历所有有 deviceKey 的 server
         │                 └─ 逐个"还原"注册（新 token + 旧 key 重绑）
         ├─ ② ensureRegistered()
         │     ├─ 全局 KEY_DEVICE_KEY 有缓存 → 直接用
         │     └─ 无缓存 → doRegister()（无 key 注册）
         │            └─ 写全局 KEY_DEVICE_KEY + 同步当前 server per-server
         └─ ③ syncCurrentServerKey()
               └─ await ensureLoaded → 取当前 server
                     └─ syncKeyForServer()（见下）

┌─────────────────────────────────────────────────────────────────┐
│              syncKeyForServer（核心 key 同步）                    │
└─────────────────────────────────────────────────────────────────┘
  输入：serverId + baseURL + savedDeviceKey
         │
         ├─ savedKey 非空？
         │     ├─ 是 → GET /register/:key 验证
         │     │     ├─ 有效 → 直接用（0 次写接口）
         │     │     └─ 无效 → POST 还原（token+platform+key）
         │     │           ├─ 成功 → 用还原的 key
         │     │           └─ 失败 → 保留原 key（不重置）
         │     └─ 否 → POST 重置（token+platform）→ 服务端生成新 key
         │
         └─ 拿到 key 后：
               ├─ updateServerDeviceKey → per-server 持久化
               │     ├─ 自定义 server → server_list_json
               │     └─ 内置 server → server_builtin_device_keys（id→key 映射）
               └─ 写全局 KEY_DEVICE_KEY（向后兼容）

┌─────────────────────────────────────────────────────────────────┐
│                    切换 Server                                    │
└─────────────────────────────────────────────────────────────────┘
  ServerSettingsContent → switchTo(id)
    ├─ currentId = id → persist → emitChange（UI 刷新标题）
    └─ 异步 syncKeyForServer（新 server 的 key 验证/还原/重置）

┌─────────────────────────────────────────────────────────────────┐
│               拉取/删除消息（NotifyMessageService）               │
└─────────────────────────────────────────────────────────────────┘
  getMessages / deleteMessage / deleteAllMessages
    └─ ServerManager.getCurrentDeviceKey()
          ├─ 当前 server 的 per-server deviceKey 非空 → 直接用
          └─ 为空（刚切换/首次）→ 内联 syncKeyForServer → 拿到 key
    └─ resolveURL(`/{key}/message...`) → 请求当前 server

┌─────────────────────────────────────────────────────────────────┐
│                  通知列表刷新（NotifyView）                      │
└─────────────────────────────────────────────────────────────────┘
  全量刷新 getMessages（重置列表/分页）：
    ├─ 组件初始化 / 服务器切换 / 下拉刷新
    ├─ 切回「通知」Tab（homeTabIndex watch）
    └─ App 回前台 / 点击系统通知拉起
          └─ EntryAbility.onForeground / onNewWant
             → AppStorage KEY_NOTIFY_REFRESH_SIGNAL 信号

  增量轮询（「通知」Tab 可见期间，间隔 15s）：
    ├─ 仅插入 id > 当前列表最大 id 的新消息（不打断滚动/分页）
    └─ 启停：通知 Tab 可见 && 主页栈顶 && App 前台
         └─ 主页栈顶可见性：Index.onPageShow/onPageHide
            → AppStorage KEY_INDEX_PAGE_VISIBLE

┌─────────────────────────────────────────────────────────────────┐
│                         存储结构                                 │
└─────────────────────────────────────────────────────────────────┘
  Preferences (timelynotify_prefs)
    ├─ device_key                    全局 key（旧链路兼容，ensureRegistered 缓存）
    ├─ device_token                  Push token（refreshTokenIfNeeded 比对基准）
    ├─ server_list_json              [{id,name,baseURL,isBuiltIn,deviceKey,clientToken}]（仅自定义）
    ├─ server_builtin_device_keys    {builtinId: deviceKey}（内置 key 专用）
    ├─ server_builtin_client_tokens  {builtinId: clientToken}（内置 token 专用）
    ├─ server_current_id             当前选中 server
    ├─ server_deleted_builtin        已删除内置 id 列表
    ├─ color_mode                    主题颜色模式（system/light/dark）
    ├─ notify_enabled                通知开关
    └─ client_token                  旧版全局 token：仅作迁移源，迁移进 per-server 后删除
```

## 发版

版本号唯一来源是 git tag，构建时（CI/CD）自动注入 `AppScope/app.json5`，仓库文件保持占位值不变。

| 脚本                  | 用法                                                                    | 说明                                                                                                             |
|---------------------|-----------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------|
| `bin/build`         | `bin/build [[v]x.y.z]`                                                | 本地构建：自动注入版本号 + 构建溯源信息（tag 或手动指定）→ hvigor 构建 → 自动还原 `app.json5` / `BuildInfo.ets`，产出 `entry-default-signed.hap` |
| `bin/release-check` | `bin/release-check [--with-build] [--with-ci] [--skip-net] [-q] [-y]` | **发版前一键环境预检**：工具链/Git 状态/凭证权限/Secrets 缺失/AGC 连通性，三态输出 ✅/⚠️/❌ + 修复建议，0 FAIL 才建议发版                               |
| `bin/release`       | `bin/release [-y] [--dry-run] [[v]x.y.z]`                             | 发版：自动切到 main 并同步 → 确定版本号（倒退/冲突校验）→ 交互确认 → 打 annotated tag 并推送，触发 CI 构建 → 签名 → 上传 AGC                           |

- 自动模式：最近 tag 的 minor +1、patch 清零（如 1.2.3 → 1.3.0，minor 满千进位到 major）；无历史 tag 时默认发 1.0.0
- versionCode = `x*1000000 + y*1000 + z`，必须大于上一个版本（AGC 要求单调递增）
- 发版流程：PR 合并进 main → 任意分支执行 `bin/release`（结束后自动切回原分支）
- `--dry-run`：预览发版流程（版本号计算与各项校验结果），零副作用（不切分支、不打 tag、不推送），可与 `-y`/版本号任意组合
- CI 构建环境：托管 runner 使用自建镜像 `ghcr.io/wallleap/harmonyos-ci`（预装 DevEco Command Line Tools for Linux
  26.0.0.821 + JDK17——与项目 `targetSdkVersion 26.0.0` 配套，由 [docker-image.yml](.github/workflows/docker-image.yml)
  从 [docker/ci/Dockerfile](docker/ci/Dockerfile) 构建推送；首次推送后需在 GitHub → Packages 中将包可见性改为
  Public）。流水线定义：[release.yml](.github/workflows/release.yml)（tag 触发：构建 → 重签名 → 上传 AGC → GitHub
  Release）、[build-check.yml](.github/workflows/build-check.yml)（push/PR 构建检查）

## 防伪校验

构建时（CI/本地 `bin/build`）自动生成 [BuildInfo.ets](entry/src/main/ets/generated/BuildInfo.ets)，App「我的 → 关于 →
构建信息」行展示
`Build #编号 · commit 前 7 位 · 指纹尾 8 位`，点击可打开云端构建记录页比对。

| 锚点         | 原理                                                        | 用户操作                                                    |
|------------|-----------------------------------------------------------|---------------------------------------------------------|
| **签名证书指纹** | 伪造包没有发布私钥，重签名必然换证书 → 指纹必变                                 | 比对 App 内指纹尾 8 位与下方公布的指纹                                 |
| **云端构建记录** | 伪造者可抄字符串，但无法在本仓库创建对应 Actions run                          | App「构建信息」行点击打开 run 页，核对编号/commit/tag                    |
| **文件校验和**  | 包被篡改即失配                                                   | `shasum -a 256 -c timelynotify-x.y.z-signed.hap.sha256` |
| **构建溯源证明** | GitHub 官方密钥签名的 SLSA provenance（`attest-build-provenance`） | `gh attestation verify <hap> -R wallleap/timelynotify`  |

**官方发布签名证书指纹（SHA-256）**——发布证书申请后从 Release 附件 `*-cert-fingerprint.txt` 获取并填入：

```
（待发布证书申请后填入：64 位十六进制，来源 GitHub Release 附件或 keytool -printcert -file release.cer）
```

> 注：本地 `bin/build` 使用调试证书签名，App 内指纹与上述发布指纹不同属正常现象；只有 CI 产出的正式包与 AGC 商店包指纹一致。

## color 色值

在 `color.json` 中定义半透明色值，需要使用 `ARGB` 格式（`#AARRGGBB`），其中前两位 `AA` 为透明度通道，取值范围 `00`（完全透明）到
`FF`（完全不透明），后六位 `RRGGBB` 为 RGB 颜色值。

<details>

<summary>透明度对照表</summary>

| 不透明度 | Alpha 值 | 示例（黑色）      | 说明          |
|------|---------|-------------|-------------|
| 100% | FF      | `#FF000000` | 完全不透明       |
| 90%  | E6      | `#E6000000` |             |
| 80%  | CC      | `#CC000000` |             |
| 70%  | B3      | `#B3000000` |             |
| 60%  | 99      | `#99000000` | 系统二级文本/图标色1 |
| 50%  | 80      | `#80000000` | 半透明         |
| 40%  | 66      | `#66000000` | 系统三级文本/图标色1 |
| 30%  | 4D      | `#4D000000` |             |
| 20%  | 33      | `#33000000` | 系统四级文本/图标色1 |
| 10%  | 1A      | `#1A000000` |             |
| 0%   | 00      | `#00000000` | 完全透明        |

</details>

## 参考文档

**消息 通知**

- [Push Kit Guide](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/push-kit-guide)
- [Notification Kit](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/notification-kit)
- [发送通知消息（点击消息动作）](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/push-send-alert)
- [场景化消息 API 参数（clickAction）](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/push-scenariozed-api-request-param)

**沉浸光感**

- [沉浸光感-最佳实践](https://developer.huawei.com/consumer/cn/doc/best-practices/bpta-spatiality-immersive#section1789710511464)
- [沉浸光感-指南](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ui-design-hds-component-material)
- [Hds 组件 API](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ui-design-arkts-component)
- [HarmonyOS 7 沉浸光感深度实战](https://developer.huawei.com/consumer/cn/blog/topic/03221220048444078)
- [HarmonyOS下HdsNavigation与HdsTabs实现滚动模糊及沉浸光感材质效果的解决方案](https://developer.huawei.com/consumer/cn/doc/harmonyos-faqs/faqs-arkui-1095)

**CI/CD**

- [准备打包所需配置文件](https://developer.huawei.com/consumer/cn/doc/app/agc-help-internal-test-prepare-0000002262046566)
- [申请发布证书](https://developer.huawei.com/consumer/cn/doc/app/agc-help-release-cert-0000002283336729)
- [申请发布 Profile](https://developer.huawei.com/consumer/cn/doc/app/agc-help-release-profile-0000002248341090)
- [编译打包应用](https://developer.huawei.com/consumer/cn/doc/app/agc-help-internal-test-build-app-0000002295372093)
- [AGC 开放能力](https://developer.huawei.com/consumer/cn/doc/best-practices/bpta-spatiality-immersive#section1789710511464)
- [上架完整踩坑清单](https://developer.huawei.com/consumer/cn/blog/topic/03222785860809218)
- [鸿蒙上架避坑手册](https://developer.huawei.com/consumer/cn/blog/topic/03217070922107125)

CLT: <https://developer.huawei.com/consumer/cn/download/command-line-tools-for-hmos>

需要使用 CLT/DevEco Release 打包，不要用 Beta

**WebView**

- [CacheMode](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/arkts-basic-components-web-e#cachemode)

**其它**

- [拉起指定类型的应用](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/specified-type-app-redirection)
- [基于 Service Account 开放鉴权](https://developer.huawei.com/consumer/cn/doc/HMSCore-Guides/open-platform-service-account-0000001053509221)
