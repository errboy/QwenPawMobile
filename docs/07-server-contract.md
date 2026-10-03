# 07 · 服务端契约

本工程对接的是 **QwenPaw v2.2.2-beta.4** 的本地 HTTP 服务。所有路径都相对
`{server}/api`，端点常量集中在 `core/Wire.ets:93-116`，页面里不出现裸 URL。

## 1. 端点表

| 方法 | 路径 | 用途 | 调用方 |
| --- | --- | --- | --- |
| GET | `/auth/status` | 是否开了鉴权、有没有用户。**登录的前置**，也是局域网扫描的探针 | `AuthApi.ets:17`、`LanScan.ets` |
| POST | `/auth/login` | 换 bearer 令牌 | `AuthApi.ets:27` |
| GET | `/agents` | 智能体列表 | `AgentApi.ets:17` |
| GET | `/chats` | 会话列表（全 App 每 10s 一次，见 §4） | `ChatApi.ets:22` |
| POST | `/chats` | 新建会话，**id 由服务端发** | `ChatApi.ets:36` |
| GET | `/chats/{id}` | 拉历史 | `ChatApi.ets:45` |
| POST | `/console/chat` | 发消息，SSE 流式返回 | `ChatApi.ets:62` |
| POST | `/console/chat/stop?chat_id=` | 停止在跑的轮次 | `ChatApi.ets:58` |
| POST | `/console/upload` | multipart 附件 | `UploadApi.ets:239` |
| GET | `/approval/list` | 待审批项 | `ApprovalApi.ets:23` |
| POST | `/approval/approve` / `/approval/deny` | 人点按钮才发 | `ApprovalApi.ets:35,43` |
| GET | `/files/preview` | 图片/文件预览 | `media/MediaLoader.ets` |
| GET | `/workspace/commands/available` | `/` 快捷指令补全 | `ComposerApi.ets:35` |
| GET | `/loops`、`/loops/status?chat_id=` | loop 模式与当前状态 | `ComposerApi.ets:56,80` |
| GET | `/models`、`/models/active?scope=effective` | 模型槽位与生效值 | `ComposerApi.ets:87,97` |
| GET | `/workspace/running-config`、`/settings/upload-limit` | 只读：显示桌面端当前默认、上传上限 | `ComposerApi.ets:113,122` |

**只读那三行是刻意的**：`PUT /workspace/running-config` 是整文档替换，
手机上误点一次就把桌面端配置改了。常量表 `core/Wire.ets:106-108` 记了这件事。

## 2. 鉴权

```
GET /api/auth/status → { "enabled": true, "has_users": true }
POST /api/auth/login → { "token": "<bearer>" }
后续请求头 Authorization: Bearer <token>
```

`enabled=false` 时客户端**跳过登录直接存空令牌**（`state/AppStore.ets:264-272`）——
这也是 qp-gate 必须本地应答 `enabled: true` 的原因，否则手机在网关后面根本不会走登录。

状态码语义（`core/Failure.ets`）：401 Unauthorized、403 Forbidden、404 NotFound、
409 Conflict、423 Locked。**401 不会触发自动重登**，只把错误归成 Unauthorized 报给用户
（`core/Failure.ets:44`）。这就是 qp-gate 的令牌默认永久不过期的原因。

## 3. 发送请求体

`POST /api/console/chat` 的 `AgentRequest`（`model/Dtos.ets:171-181`，服务端 `extra="allow"`）：

| 字段 | 含义 |
| --- | --- |
| `input` | 消息数组，含 text / image / audio / video / file parts |
| `session_id` | 会话 id |
| `stream` | 恒 `true` |
| `reconnect` | `true` = 挂到在途的 run 上并回放缓冲帧 |
| `request_context.approval_level` | 见下 |
| `model_slot_override` | 见下 |
| `user_id` | 可选 |

两个透传字段**省略 = 跟随桌面端自身默认**。审批级别取值
`STRICT / SMART / AUTO / OFF`（`core/Wire.ets:157-163`），未知值干脆不发这个字段，
让 agent 的 running-config 级别继续生效。这些偏好服务端不存，手机按会话存在本地
（`core/Prefs.ets Key.CHAT_PREFS`）。注意：`AUTO`/`OFF` 是**桌面端自己的**工具执行策略档位，
不代表手机会自动点同意——手机只在人点按钮时发 approve/deny。

## 4. SSE 帧语义（最容易踩的地方）

`stream/StreamReducer.ets:1-15` 把两条线上事实定为整个设计的前提：

1. `object=content` 帧的 `delta=true` 是增量，`delta=false` 是**该块的完整文本**。
   v1 两种都往后追加，于是块结束时整段重复印了一遍。这里每个块按
   `(msg_id, index)` 存，非 delta 帧**覆盖**。
2. **没有 `data: [DONE]`**。一轮结束的标志是 `response` 帧报告终态
   （`RunStatus.completed/failed/cancelled`，`core/Wire.ets:50-61`）；
   其他任何关闭流的方式都算掉线，`RunController` 必须把"掉线"和"结论"分开。

消息类型词表在 `core/Wire.ets:15-28`：`message`、`reasoning`、
`plugin_call`/`function_call`/`mcp_tool_call` 及各自的 `*_output`、`progress`、`result`、
`heartbeat`（心跳帧不渲染，`core/Wire.ets:26-27`）。工具族判定在 `ToolTypes`（:31-43）。

归并器只发事实（Upsert / 状态 / 标志），**不产出任何面向用户的字符串**；
所有文案由 UI 层从 `l10n/Copy.ets` 组装。

## 5. 轮询

`polling/GlobalPoller.ets:13` 定 `POLL_INTERVAL_MS = 10000`，全 App 一个定时器：
每 tick 取一次 `/api/chats` + `/api/approval/list`，把快照分发给注册过的 store。
任何 `ChatStore` 自己发 `/api/chats` 都是 bug。

## 6. 断线重连

`stream/RunController.ets:324` 起 2s → 4s → 8s 退避，上限 3 次（`MAX_RECONNECT`，:26）。
重连时重载历史但把排队中的气泡重新接回（见 [05](05-architecture.md) 规则 4）。

## 7. 服务端换了版本怎么办

先跑一遍真连接：登录 → 收发消息 → 工具调用 → 审批 → 上传 → 停止。
最可能的破坏点在 §4 的帧语义和 §1 的端点改名。契约常量都在 `core/Wire.ets`，
改名只动一处；`model/Dtos.ets` 的字段名是与服务端对齐的镜像，改它等于改契约。

`tools/qp-gate/selftest.py` 自带桩上游，覆盖网关侧的转发/鉴权/SSE 分帧，
**不覆盖**上表的业务语义。
