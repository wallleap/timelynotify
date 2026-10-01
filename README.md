# 及时通知

通知图片保留 Bark 语义：`icon` 在列表和详情标题区左侧显示，`image` 在列表右侧显示缩略图，并在详情正文下方显示大图。从旧版本升级时，已缓存的图标会自动迁移到
`icon` 字段。

TimelyNotify 是使用 ArkTS 开发的鸿蒙端通知 App。

下载链接：<https://appgallery.huawei.com/link/invite-test-wap?taskId=8121c9f6a1255c454c2016bea2f7cce9>

服务器端 [timelynotify-server](https://github.com/wallleap/timelynotify-server) 修改自 Bark-server，因此可以只部署这个服务，实现一个
push 链接同时发送到 iOS 和 HarmonyOS。

> 强烈建议自建服务，相关文档：<https://docs.timelynotify.oicode.cn/deploy/>

TODO:

- [x] 客户端端到端解密（AES128/AES192/AES256，CBC/ECB/GCM，按服务器独立配置）
- [ ] 多语言
- [ ] 等 PushKit API 完善点，实现更多推送参数
    - 鸿蒙 Push Kit 通知点击使用 `actionType=0` 携带定位数据：`action=alert`（默认）同步后打开对应详情，
      单服务器视图会切到来源服务；`none` 只回通知首页，`url` 优先。通知栏不提供复制等操作按钮。
- [ ] 内容处理（例如整体复制、复制链接/验证码）

## 功能说明

- 底部「服务」页提供「使用指南」「推送参数」「常见问答」入口，均在应用内打开对应页面
- 「服务 → 推送测试」可单独选择目标服务器（不改变通知列表当前服务器），查看或复制含该服务器地址与设备 Key 的多行 GET/POST
  `curl` 命令（GET 以原文展示标题与正文、保留 `?参数&参数` URL 形式，执行时需要 `jq` 编码路径；POST 使用 JSON
  请求体）；示例与「发送通知」按钮共用 title、body、icon、group、ttl、sound 参数。卡片的分段按钮主区域复制设备 Key，右侧菜单可复制服务器地址或完整的推送地址（地址和 Key）
- 兼容 bark 的所有接口（`/register`、`/push` 等）
- 服务端暂存待同步的通知；客户端同步并写入本地历史后删除远程副本。通知列表和「导出通知」均读取本地历史。服务端 `delete=1`
  推送删除会写入 `extraIds` 墓碑，客户端按此同步清理本地已同步副本
- 大量待同步通知按每页最多 100 条拉取，并在本地数据库中整页事务提交；成功后才清理该页远端副本。每页提交后列表和「已处理 N 条」进度会更新；「全部」视图最多同时同步 2 个服务器。中断或写入失败时，尚未清理的远端通知会在下次进入或轮询时重试；密钥缺失、解密失败或解密后本地通知发布失败时保留远端密文并提示检查配置。手动删除解密失败的通知时，会先核对服务器当前持久化实例 ID，再清理其远端密文；无法确认实例或远端删除失败的条目留在本地供重试。自动复制只保留本轮最新候选，不缓存整批通知
- 同步由应用前台生命周期管理：离开通知页、切到「服务」「我的」或其它应用内页面时仍会完成当前同步；进入系统后台后暂停后续分页与轮询，回前台自动续拉。正常服务器在通知 Tab 约每 3 秒、其它 Tab 约每 15 秒轮询；失败服务器各自按 15 秒至 5 分钟退避自动重试，改动该服务器配置后立即重试，下拉刷新可主动重试全部。错误 Banner 保留到对应服务器同步成功或被删除；没有实际处理通知的连接探测不显示全局同步进度。同步失败的远端副本保留以待重试。
- 本地历史按服务端返回的数据库实例 ID、`device_key` 与数字消息 ID 共同标识；服务器重建数据库后即使数字 ID 重复，也不会覆盖旧通知或误打开另一条详情。旧版服务器没有实例 ID 时仍可同步，按服务器配置隔离新缓存。升级前已保存的旧通知继续保留；若同一个旧 `device_key` 曾属于多个服务器，来源无法判定的旧记录仅在「全部」视图显示，不误归入单服务器。
- 加密配置按服务器分别保存在 Harmony 客户端；Key 可明文输入或点击重置图标安全随机生成，并使用 Asset Store 安全存储、禁止设备/云同步，普通
  Preferences 只保存非敏感配置。生成的新 Key 在保存前仅为候选值；保存变更过的 Key、算法或模式时会提醒先备份旧 Key
  并同步更新发送端，旧密文不保证继续可解密。服务器暂存 `ciphertext` 和 `iv` 供客户端同步，并向 Harmony 通知栏发送固定安全占位内容，不持有
  Key、不解密明文
- 通知原始数据携带 `ciphertext` 时，客户端先解密再落库：本地同时保存解密明文、原始 `ciphertext`/`iv`
  和“加密”状态标签，便于远程记录删除后仍可更换配置重新解密
- 支持 Bark `isArchive` 与 `ttl`：缺省或 `isArchive=1` 的通知保存到本地历史，显式关闭时同步完成后只清理远端、不落本地；正整数
  `ttl` 会按服务端通知时间计算本地过期时间，进入或刷新列表时自动清理
- TTL 展示保持轻量：剩余不足 1 小时时列表显示“即将过期”标签；详情页不足 1 小时显示约 N 分钟、1～24 小时显示约 N 小时、超过 24
  小时显示具体过期时间；不使用秒级倒计时
- 对“密文且不归档”的通知，客户端成功解密后会通过 Notification Kit 逐条发布真实内容。个性化设置中的“加密通知重发”开关默认关闭；开启后，新同步且成功解密的归档加密通知也会补发本地通知，但 `isArchive` 决定的本地历史留存不变，已迁移完成的旧通知不会追溯重发。需要补发的通知发布成功后才删除远程密文，失败则保留并在下次同步重试；同一消息使用稳定标识更新，不会因删除重试重复堆叠
- “个性化设置”按“外观”和“通知行为”分组：主题模式、沉浸光感位于外观分组，加密通知重发位于通知行为分组；内容区可上下滚动，标题栏保持固定。
- 「我的 → 导出通知」从本地数据库导出当前服务器的全部未过期通知，包括尚未加载到列表的历史；不再以已被同步清理的服务器历史作为导出来源。文件为
  JSON 数组，包含本地保存的解密正文、图片 URL、原始密文和过期时间；请妥善保管导出文件
- 通知列表多选时，点击单条或分组复选框均会同步更新已选数量及底部导出、删除数量；分组复选框仅作用于当前已加载的组内通知
- CBC 使用发送端携带的 16 字节 IV，GCM 使用 12 字节 IV，ECB 不使用 IV；GCM 密文格式为
  `Base64(ciphertext || 16-byte authTag)`，不使用 AAD
- 当前实际链路为：系统通知显示固定安全占位内容，用户打开 App 后拉取消息历史并在本地解密。RemoteNotification 扩展解密代码作为未来取得
  `push-type: 2` 权益后的预留能力保留，当前普通 `push-type: 0` 推送不会进入该扩展

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
  首页标题 →「切换通知服务」弹窗（ServerSwitchDialog，单选列表）
    ├─ 首项「全部通知」→ setViewAllMode(true)（聚合所有服务器）
    └─ 服务器项 → setViewAllMode(false) + switchTo(id)（只看该服务器）
  服务 → 服务器列表 ServerList → 选择服务器 → switchTo(id)
    ├─ currentId = id → persist → emitChange（UI 刷新标题）
    └─ 异步 syncKeyForServer（新 server 的 key 验证/还原/重置）

┌─────────────────────────────────────────────────────────────────┐
│               迁移远程消息（NotifyMessageService）               │
└─────────────────────────────────────────────────────────────────┘
  getMessages
    └─ ServerManager.getCurrentDeviceKey()
          ├─ 当前 server 的 per-server deviceKey 非空 → 直接用
          └─ 为空（刚切换/首次）→ 内联 syncKeyForServer → 拿到 key
    └─ resolveURL(`/{key}/message...`) → 请求当前 server
          └─ 每页：解密 → 应用 isArchive/ttl
                ├─ 归档 → 明文+密文写入本地；开启“加密通知重发”时也补发本地通知
                └─ 密文且不归档 → Notification Kit 逐条发布真实内容
                     → 处理成功后删除对应远程记录
                └─ 远程删除失败 → 保留服务器副本，下次从 after=0 幂等重试

┌─────────────────────────────────────────────────────────────────┐
│              应用级通知同步（NotifySyncService）                │
└─────────────────────────────────────────────────────────────────┘
  后台迁移 getMessages（每次从远程待迁移队列 after=0 开始）：
    ├─ EntryAbility.onForeground 启动/续拉；onBackground 暂停后续分页
    ├─ 下拉刷新、服务器切换和点击系统通知可触发额外同步
    └─ 每页落库后通过 AppStorage revision 刷新可见通知列表

  前台轮询（不依赖 NotifyView 是否挂载）：
    ├─ 新消息写入本地后删除远程副本（不打断滚动/分页）
    └─ 正常服务器：通知 Tab 3 秒、其它 Tab 15 秒；失败服务器独立退避 15 秒至 5 分钟；系统后台停止

  同步错误 Banner：点击后按错误类型打开对应服务器的 Token、Key 或操作弹窗；
    操作弹窗中的解密设置、重命名、删除直接作用于该服务器，不仅切换到「服务」Tab

  历史保留：
    ├─ isArchive 缺省/1 → 保存本地；其它值 → 不保存本地
    └─ ttl 正整数秒 → 保存绝对过期时间，进入/刷新列表时清理到期记录

  用户删除：已迁移通知仅删本地；解密失败通知先删当前实例的远端副本，失败则保留本地
    ├─ 单条/多选/清空均明确提示“删除后无法恢复”；详情 Sheet 底部固定「删除」按钮，API 26+ 使用 Button 系统材质、旧系统使用模糊降级，确认成功后关闭详情
    │  详情 Sheet 容器和内容统一由 ImmersiveUtil 判断：API 26+ 且开关开启时采用沉浸布局，材质实例预创建后经 getEnabledSystemMaterial('sheet') 提供系统背板；未加载时保留模糊降级。设备 supported 查询仅用于诊断，不再单独决定 Sheet、Dialog 或 Menu 的渲染分支。
    │  全部居中 CustomDialog 的材质由 ImmersiveUtil.getDialogMaterial() 统一获取，Menu 由 withImmersiveMenuMaterial() 构造 options，Toast 和 Sheet 由 getEnabledSystemMaterial() 获取；这些入口共用 API 版本、用户开关和实例加载判断。材质可用时透明背板、不叠 blur；不可用时使用原有模糊降级。组件不直接查询 SDK 版本、设备 supported 状态或自行创建 ImmersiveMaterial。切换通知服务弹窗的 HDS 列表卡片样式由 shouldUseLoadedMaterialStyle() 决定。
    │  弹窗内部表面同步玻璃化（仅用于弹窗内部；背板效果取决于系统材质支持与降级路径）：TextInput/选择行用 color_bg_input_glass（85% 不透明，亮 #D9E4E8EE 加深灰蓝/暗 #D9141920 同色系深炭——内凹槽语义：亮背板压暗一档、暗背板再压深一档；暗色切忌比背板浅的偏蓝灰，会像浅蓝补丁显脏）、次级按钮（取消等）为透明幽灵按钮（Color.Transparent 无底，60% 玻璃灰叠白背板会显发白方块故弃用 color_bg_control_glass）、内嵌卡片/服务器行用 color_bg_surface_glass、选中态用 color_bg_selected_glass（20% 品牌橙，含算法/模式 Menu 选中行）；例外：「切换通知服务」弹窗 HDS 列表行在沉浸材质生效时保留 HDS 默认卡片表面，仅降级分支玻璃化；主 CTA（添加/保存）保持实色品牌橙不变
    │  「解密设置」由 DecryptionSettingsDialog.ets 实现，为居中的 CustomDialog：标题、表单和底部按钮分别控制留白，标题与取消/保存按钮固定，表单在弹窗最大高度内独立滚动。背板由 getDialogMaterial() 统一提供 ULTRA_THIN 材质，未加载或开关关闭时走原有组件模糊降级；弹窗打开后读取配置，校验、生成 Key、保存和清除配置沿用 EncryptionConfigService。
    │  「切换通知服务」弹窗同样在 API 26+ 沉浸分支使用 HdsNavigation MODAL 左对齐固定标题、叠放的右上角描边透明关闭按钮，并将服务器卡片的单一 Scroll 绑定到 GRADIENT_BLUR；无底部操作区。关闭按钮沿用通知页玻璃描边色值，弹窗背板已有模糊，按钮自身不再叠加浅色模糊底以免亮色下成为实心白圆。降级分支保留左对齐普通固定标题与关闭图标，弹窗随列表项数增加至上限高度后内部滚动。
    │  通知页同步错误 Banner 遇到非 Token/设备类错误时打开的「服务器操作」弹窗，标题下显示当前目标服务器的名称与域名（无名称时只显示域名）；API 26+ 沉浸分支用 HdsNavigation MODAL 固定标题、绑定菜单 Scroll 呈现渐变模糊，降级分支也将普通标题固定在滚动区外。右上角关闭按钮使用透明背景、主题主文字色和 color_border_glass 描边；背板按 Sheet 的 API 26+ 与开关条件传材质参数，菜单行为不变。
    │  服务器操作弹窗与切换通知服务弹窗最早采用上述统一背板路径，客户端 Token、重置/还原 Key、解密设置、重命名、添加服务器等弹窗已全部与之对齐：API 26+ 且沉浸光感开关开启时即传入 ULTRA_THIN 材质参数，不以设备 supported 结果拦截；设备不支持材质时实际视觉效果以系统渲染为准。旧系统或开关关闭时使用轻量组件模糊（COMPONENT_ULTRA_THIN），不叠加背景色。
    ├─ 删除分组按 group_key 一次删除数据库中的全部通知（含未加载部分）
    └─ 展开的分组删到真实总数只剩 1 条时自动收起回普通卡片
       （仍有未加载历史时保留展开，避免看不到“加载更多”入口）

┌─────────────────────────────────────────────────────────────────┐
│                         存储结构                                 │
└─────────────────────────────────────────────────────────────────┘
  Preferences (timelynotify_prefs)
    ├─ device_key                    全局 key（旧链路兼容，ensureRegistered 缓存）
    ├─ device_token                  Push token（refreshTokenIfNeeded 比对基准）
    ├─ server_list_json              [{id,name,baseURL,isBuiltIn,deviceKey,clientToken}]（仅自定义）
    ├─ server_builtin_device_keys    {builtinId: deviceKey}（内置 key 专用）
    ├─ server_builtin_client_tokens  {builtinId: clientToken}（内置 token 专用）
    ├─ server_encryption_configs     {serverId: {enabled,algorithm,mode,padding,deviceKey}}（不含 Key）
    ├─ server_current_id             当前选中 server
    ├─ server_deleted_builtin        已删除内置 id 列表
    ├─ color_mode                    主题颜色模式（system/light/dark；“我的”标题栏与“个性化设置”选择器实时同步）
    ├─ encrypted_notification_resend 归档加密通知重发开关（true/false，默认 false）
    ├─ notify_enabled                通知开关
    └─ client_token                  旧版全局 token：仅作迁移源，迁移进 per-server 后删除

  Asset Store（关键资产安全存储，SYNC_TYPE.NEVER）
    └─ timelynotify.encryption.{serverId}  各服务器的端到端解密 Key
```

## 发版

沉浸光感的能力判断和原始材质创建集中在 `entry/src/main/ets/utils/ImmersiveUtil.ets`。开发时可运行
`bash .github/scripts/check-immersive-boundary.sh` 检查组件是否绕过该工具；PR 构建检查会自动执行。

版本号唯一来源是 git tag，构建时（CI/CD）自动注入 `AppScope/app.json5`，仓库文件保持占位值不变。

| 脚本                  | 用法                                                                    | 说明                                                                                                             |
|---------------------|-----------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------|
| `bin/build`         | `bin/build [[v]x.y.z[-beta.n]]`                                      | 本地构建：自动注入版本号 + 构建溯源信息（tag 或手动指定）→ hvigor 构建 → 自动还原 `app.json5` / `BuildInfo.ets`，产出 `entry-default-signed.hap` |
| `bin/release-check` | `bin/release-check [--with-build] [--with-ci] [--skip-net] [-q] [-y]` | **发版前一键环境预检**：工具链/Git 状态/凭证权限/Secrets 缺失/AGC 连通性，三态输出 ✅/⚠️/❌ + 修复建议，0 FAIL 才建议发版                               |
| `bin/release`       | `bin/release [--dry-run] [--bump major\|minor\|patch\|current] [--stage beta\|stable] [-y]` | 发版：从带目标版本号的菜单选择增量和阶段；不接受手填版本号 → 校验后打 annotated tag 并推送，触发 CI 构建与上传 AGC |

- 版本增量：major → `x+1.0.0`、minor → `x.y+1.0`、patch → `x.y.z+1`；最近 tag 是 beta 时还有 `current`，可继续发 `-beta.n+1` 或转正式版。minor/patch 满千自动进位。
- 阶段：beta 自动顺延序号 `1–98`，正式版不带后缀。例如 `1.2.0-beta.1` → `1.2.0-beta.2` → `1.2.0`。
- Git tag/Release 名称保留 `-beta.n`，但 AGC 包内 `versionName` 仅使用数字和点：`v1.2.0-beta.1` 对应 `1.2.0.1`，`v1.2.0-beta.2` 对应 `1.2.0.2`；正式版 `v1.2.0` 对应 `1.2.0`。不要直接把含 `-beta` 的名称写进 `app.json5`。
- versionCode = `(x*1000000 + y*1000 + z)*100 + slot`；beta 的 slot 为 `01–98`，正式版为 `99`，必须严格递增且不超过 31 位非负整数上限。旧版已发布包的编号不变，新版从双位 slot 规则继续。
- beta tag 在 AGC 使用 HarmonyOS 测试发布类型，在 GitHub 标记为预发布且不设为 latest；正式版使用 AGC 全量发布类型及 GitHub 正式 Release。手动触发 workflow 可覆盖 AGC 发布类型。
- 发版流程：PR 合并进 main → 任意分支执行 `bin/release`（结束后自动切回原分支）
- `--dry-run`：预览发版流程（版本号计算与各项校验结果），不切分支、不打 tag、不推送；仍会只读地 fetch 远端 tag。
- 非交互调用示例：`bin/release --bump minor --stage beta --dry-run -y`。`-y` 必须同时给出增量和阶段。
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
