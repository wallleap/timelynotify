# 服务器 API 接口

baseURL: `https://timelynotify.oicode.cn`

本地测试环境：http://localhost:18080

## 一、设备注册（必须）

**鸿蒙设备需在推送前注册，与 iOS 共享同一个 `/register` 接口，但需指定 `platform` 字段。**

| Method | Path | 认证 | 说明 |
|--------|------|------|------|
| POST | `/register` | 无 | 注册设备（body：`device_key`、`device_token`、`platform: "harmony"`） |
| GET | `/register/:device_key` | 无 | 校验 device_key 是否存在 |

```bash
# 注册鸿蒙设备
curl -X POST "http://<host>:18080/register" \
     -H 'Content-Type: application/json' \
     -d '{
  "device_key": "my-harmony-device",
  "device_token": "<harmony_push_token>",
  "platform": "harmony"
}'
```

---

## 二、推送接口（核心）

**鸿蒙与 iOS 使用完全相同的推送 API，服务端按 `platform` 字段自动路由到华为 Push Kit。**

| Method | Path | 认证 | 说明 |
|--------|------|------|------|
| POST | `/push` | 无（`device_key` 即凭证） | V2 标准 REST 推送 |
| GET/POST | `/:device_key` | 无 | V1 兼容推送（单段路径） |
| GET/POST | `/:device_key/:body`、`/:device_key/:title/:body` 等 | 无 | V1 兼容推送（多段路径） |

```bash
# HarmonyOS 推送（与 iOS 格式相同，服务端自动路由）
curl -X POST "http://<host>:18080/push" \
     -H 'Content-Type: application/json' \
     -d '{
  "device_key": "my-harmony-device",
  "title": "鸿蒙测试",
  "body": "这是一条鸿蒙推送",
  "level": "active"
}'
```

**鸿蒙特有 `level` → `click_action` 映射**：

| Bark level | 华为 click_action | 说明 |
|-----------|-------------------|------|
| 不指定 | `launch` | 全屏通知（默认） |
| `critical`/`timeSensitive` | `launch` | 全屏通知 |
| `active` | `banner` | 横幅通知 |
| 其他（如 `passive`） | `page` | 普通通知 |

---

## 三、Gotify 兼容监控（hotify-bridge 订阅用）

**设备级监控接口，需 client token 认证。用于 hotify-bridge 订阅推送历史与实时流。**

| Method | Path | 认证 | 说明 |
|--------|------|------|------|
| GET | `/:device_key/version` | 无 | 设备级探测 |
| GET | `/:device_key/message` | client token | 查询该设备的历史消息 |
| DELETE | `/:device_key/message` / `/:device_key/message/:id` | client token | 删除历史消息 |
| GET | `/:device_key/stream` | client token | WebSocket 订阅实时推送 |

```bash
# 查询历史
curl -H "X-Gotify-Key: <clientToken>" \
     "http://<host>:18080/<device_key>/message"

# WebSocket 订阅
ws://<host>:18080/<device_key>/stream?token=<clientToken>
```

---

## 四、MCP 接口（AI Agent 调用用）

**供 AI 代理通过 MCP 协议调用推送工具。**

| Method | Path | 认证 | 说明 |
|--------|------|------|------|
| ALL | `/mcp` | 无 | 需在工具参数中传 `device_key` |
| ALL | `/mcp/:device_key` | 无 | device_key 从路径预填 |

---

## 五、辅助接口

| Method | Path | 认证 | 说明 |
|--------|------|------|------|
| GET | `/` | 无 | 存活探测，返回 `"ok"` |
| GET | `/ping` | 无 | 健康检查 |
| GET | `/healthz` | 无 | 健康检查（返回 `"ok"`） |
| GET | `/info` | 无（Basic Auth 白名单） | 服务版本/构建信息 |
| GET | `/metrics` | 需 Basic Auth | Prometheus 指标 |

---

## 完整调用链路（鸿蒙场景）

```
鸿蒙 App ──① POST /register (platform=harmony)──▶ 服务端
     │                                                │
     │  返回 device_key                                │
     ▼                                                ▼
推送方 ──② POST /push (device_key + level)──▶ 服务端
                                                    │
                              按 platform=harmony   │
                              路由到华为 Push Kit   │
                                                    ▼
                                         ③ gotifyPublish（监控流）
                                                    │
                                                    ▼
hotify-bridge ──④ GET /:device_key/stream?token──▶ WebSocket 订阅
```

**关键要点**：鸿蒙推送与 iOS 推送共用同一套 API，只是在注册时指定 `platform: "harmony"`，推送时服务端自动选择华为通道，调用方无需额外区分。
