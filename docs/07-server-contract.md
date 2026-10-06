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
| POST | `/console/upload` | multipart 附件 | `UploadApi.ets:248` |
| GET | `/approval/list` | 待审批项 | `ApprovalApi.ets:23` |
| POST | `/approval/approve` / `/approval/deny` | 人点按钮才发 | `ApprovalApi.ets:35,43` |
| GET | `/files/preview` | 图片/文件预览 | `media/MediaLoader.ets` |
| GET | `/workspace/commands/available` | `/` 快捷指令补全（`category` 决定面板分组） | `ComposerApi.ets:39` |
| GET | `/loops`、`/loops/status?chat_id=` | loop 模式与当前状态 | `ComposerApi.ets:60,83` |
| GET | `/models`、`/models/active?scope=effective` | 模型槽位与生效值 | `ComposerApi.ets:91,101` |
| GET | `/workspace/running-config`、`/settings/upload-limit` | 只读：显示桌面端当前默认、上传上限 | `ComposerApi.ets:117,126` |
| GET | `/skills` | ＋ 菜单「🧩 技能 (电脑)」点开的面板（按 `enabled` + `channels` 过滤） | `ComposerApi.ets:138` |
| GET | `/mcp`、`/mcp/tools/{key}` | 只读：电脑端挂了哪些 MCP 客户端、各自工具。**只取五个安全字段**，`url`/`headers`/`env`/`args` 不进 DTO 也不进日志 | `ComposerApi.ets:160,185` |

**只读那几行是刻意的**：`PUT /workspace/running-config` 是整文档替换，
手机上误点一次就把桌面端配置改了；`POST /mcp/toggle/{key}` 与 `PUT /mcp/tools/{key}`
同理，是桌面端的全局配置。常量表 `core/Wire.ets:124-126` 记了这件事。

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

`POST /api/console/chat` 的 `AgentRequest`（`model/Dtos.ets:194-204`，服务端 `extra="allow"`）：

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
`STRICT / SMART / AUTO / OFF`（`core/Wire.ets:214-219`），未知值干脆不发这个字段，
让 agent 的 running-config 级别继续生效。这些偏好服务端不存，手机按会话存在本地
（`core/Prefs.ets Key.CHAT_PREFS`）。注意：`AUTO`/`OFF` 是**桌面端自己的**工具执行策略档位，
不代表手机会自动点同意——手机只在人点按钮时发 approve/deny。

### 3.1 技能没有请求体字段

`AgentRequest` 里**没有**"这条消息用哪个技能"的位置：哪几个技能生效是服务端按
workspace manifest + 渠道算出来的（`runtime/builder.py` 调
`resolve_effective_skills(workspace_dir, channel)`），不接受客户端点名。手机能做的只有
把 `/<技能名> <正文>` 当普通文本发出去，由 slash 分发链的**回退**接住
（`runtime/slash_command_registry.py:48-54` 的 fallback 就是给技能留的，实现在
`runtime/builtin_commands.py:697`）：名字命中已生效技能才处理，`/名字` 不带正文时返回
那条技能的简介（不执行任何东西），带正文时把正文交给技能。桌面端自己的 `/skills`
列表也是这么教用户的（`runtime/commands/control/skills_handler.py:69-74`）。

所以手机上任何"引用技能"的样式最终都得落成 `/名字` 这段文本 —— 换成 `skills:名字`
之类的显示形式，服务端只会当成一句话。面板每行右边直接把 `/名字` 写出来，就是为了
不让界面好看的程度决定线上格式。

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

`stream/RunController.ets:327` 起 2s → 4s → 8s 退避，上限 3 次（`MAX_RECONNECT`，:26）。
重连时重载历史但把排队中的气泡重新接回（见 [05](05-architecture.md) 规则 4）。

"连接中断，N 秒后自动重连…"是这条循环在转录里留下的一句**承诺**，不是发生过的事实，所以
它必须随等待一起结束：流重新打开、对端已经不在跑、或放弃重连，三个点之一就把这句撤掉
（`NoticeTone.RETRYING` + `ChatStore.retireRetrying()`）。其余通知（"已停止"、"生成失败"）
调性是 ERROR/MUTED，永远留着 —— 历史重建故意保留通知，否则刚告诉过用户的事会被重建吃掉。

## 7. 服务端换了版本怎么办

先跑一遍真连接：登录 → 收发消息 → 工具调用 → 审批 → 上传 → 停止。
最可能的破坏点在 §4 的帧语义和 §1 的端点改名。契约常量都在 `core/Wire.ets`，
改名只动一处；`model/Dtos.ets` 的字段名是与服务端对齐的镜像，改它等于改契约。

`tools/qp-gate/selftest.py` 自带桩上游，覆盖网关侧的转发/鉴权/SSE 分帧，
**不覆盖**上表的业务语义。

## 8. 附件：三条实测出来的契约边界

本节全部来自 2026-10-05 那轮"手机发三个附件、电脑端只看到一坨文字"的排查。
证据取自本仓库 `src/qwenpaw/**` 的**只读副本**（v2.2.2-beta.4）—— 桌面端不在这个项目
的维护范围里，所以这里只记事实与对策，不改它一个字节。

### 8.1 自己发的媒体，历史里回不来

`runtime/message_convert.py` 的 `_request_message_metadata` 只在某个分片
`type == "file"` **且**带 `file_url` 时，才把原始分片写进
`qwenpaw_original_user_content`。image / video / audio 三条通道都没有这个待遇。

于是：**从手机上传上去的图、视频、语音，重进会话后都不是附件，而是服务端替
模型改写的那句话**（`用户上传文件，已经下载到 …\media\<name>`）。电脑端自己的
客户端同样如此 —— 这不是手机独有的缺陷，所以手机不打算把它藏起来，见下文对策的
"只贴媒体、不改文字"。

范围要划准，2026-10-06 在真实端逐条验过：

- **上传通道**（手机的 `/api/console/upload`，电脑端选文件走同一条）拿回来的是
  **五个 `text` 分片**：用户自己打的那句、一条 `<system-reminder>…`、两条
  "用户上传文件，已经下载到 …"、一条 `[Image unavailable: …]`。**零个媒体分片**。
  本小节的标题说的就是这一路。
- **例外**：分片里带 base64 `data:` 的图（电脑端把图片直接拖进气泡那一路）会在
  历史里原样活下来，回成一个 860 KB 的内联 `data:` URI。所以"回不来"不能写成
  "任何客户端任何附件"，只能写成"走上传通道的附件"。

另一半事实在 `app/chats/utils.py:agentscope_msg_to_message`：用户轮的 metadata 原样
回传，嵌在 `metadata.metadata` 下。而 `schemas.Message.id` 是
`Field(default_factory=lambda: uuid4().hex)`，历史装配时从不传 `id=` ——
**历史行的 `id` 每次请求都重铸**，不能当身份用。`schemas.Message` 是
`extra="allow"` 且 `metadata: Optional[Dict[str, Any]]`，所以手机可以往
`input[0].metadata` 里写东西并指望它回来。

同一处还吃掉了 `qwenpaw_original_user_content`：`utils.py:587-602` 读到它会用原始
分片**替换**改写后的文字，并把这把 key 从回声里摘掉。所以手机侧永远观察不到这个
字段，不是因为服务端没写，是因为服务端写进来又吃掉了 —— 别把它当契约的一部分。

`qwenpaw_client_message_id` 是服务端的一等 key，不是手机的私有发明：电脑端自己就在
发它，形状是 **uuid4（长度 36）**；手机用的是 `cm_<ts>_<seq>`，两者不可能撞。服务端
对它的唯一反应是给这一轮盖 `qwenpaw_turn_state`（`runtime/console_turn_state.py` 的
`stamp_console_turn`），真实端实测确实把 `{"status":"completed"}` 写回了手机那一轮
的 metadata 里 —— 无害，且是"我的 id 被服务端认出来了"的直接证据。

**手机侧对策（已落地）：按 `qwenpaw_client_message_id` 回显。**

1. 发一轮带媒体的消息时，手机给自己盖一个 id 到 `input[0].metadata`
   （`api/ChatApi.bodyOf()`；纯文本轮不盖，请求体和以前逐字节一致）；
2. 同一轮里，把这枚气泡**当时显示过**的媒体引用记进本机偏好
   `ChatPreference.sentMedia`（上限 20 条，`state/ChatStore.rememberSentMedia()`）；
3. 重进会话时，`ChatStore.applySentMedia()` 只认这一行：**带本机的 id** 且
   **服务端一个媒体都没给**，才把手机那份贴回去。

三条边界让它可以直接躺在桌面上不用回收：服务端给了媒体 → 不贴，不会重复一行；
电脑端发的轮次 → 没有这个 id → 不认领；哪天桌面端开始回显附件 → 记录不再命中，
手机自动改口显示服务端的答复。回显只补媒体，**不改那句服务端的话**，所以转录里
仍然是"用户当时说了什么"的原样。

两句渲染提醒，都在 `model/Parts.displayText()` 这一条漏斗上（历史与流式 Completed
帧都只经它，`state/ChatStore.ets` 与 `stream/StreamReducer.ets`）：

1. 那句改写里嵌着 `<system-reminder>…</system-reminder>`，是给模型的提示，不是给
   人看的。桌面端的渲染器把它当未知 HTML 标签丢掉，所以电脑端从来看不见；`Text`
   组件没有这条规则，会原样贴给用户，所以手机侧剥掉它。
2. 一条消息可以有多个 `text` 分片（用户自己的话，然后服务端对每个附件的一句话）。
   直接拼成一串会把两句话焊成第三个词（`…验证R6用户上传文件，…`），所以分片之间
   用换行分块。

另外，反斜杠**只在 ASCII 标点前**才算 GFM 转义（`ui/chat/Markdown.ets`），否则
Windows 路径会被啃成 `C:Users…`；桌面端的 react-markdown 就是这么处理的。

**不落地的 patch（只写不发）。** 真正的修法在服务端：把那个判定从"`file` 且带
`file_url`"放宽到"本轮含任意媒体分片"。形状大致是 ——

```diff
--- a/src/qwenpaw/runtime/message_convert.py
+++ b/src/qwenpaw/runtime/message_convert.py
@@ _request_message_metadata
-        if part.get("type") == "file" and part.get("file_url"):
+        # Any media part is worth restoring, not just `file`: an uploaded image
+        # is the user's own attachment, and the model-facing sentence is a
+        # substitute for the model, not for the client that sent it.
+        if part.get("type") in {"file", "image", "video", "audio"} and any(
+            part.get(k) for k in ("file_url", "image_url", "video_url", "data")
+        ):
             metadata[QWENPAW_USER_CONTENT_KEY] = ...
```

它**故意不进本仓库的提交**：桌面端维护不在这个项目的职责内，`src/qwenpaw/**` 与
`tests/**` 一个字节都不改。留在这里是为了下次排查的人不必再从头推一遍，也方便真的
有人提 PR 时直接引用。

三条被否掉的本机绕路，记下来免得再被想起：

1. **把整段文字也回显成手机当时显示的**：越界。桌面端显示的就是那句改写，手机单独
   不一样只会让两端对不上，而且用户真正丢的是缩略图，不是那句话。
2. **为这份记录单开一个清理类别或按钮**：计划里禁止加新按钮；它就是会话偏好的一部分，
   已经并进"会话偏好"那一类一起清。
3. **拿历史行的 `id` 当身份**：上面已经证伪，id 每次请求重铸。

### 8.2 MPO 照片：手机传得上去，桌面端不显示

`/api/console/upload` 收 MPO（Pillow 的 `Image.verify()` 放行），但
`image_freezing.py:23-31,99-124` 的 MIME 白名单里没有 `image/mpo`，模型侧最终拿到
`[Image unavailable: …]`。手机**不做转码**：不为此引一个图像库，也不在手机上重编码
用户按下的那张照片。这条边界同样只在服务端能真正解决。

2026-10-06 真机 + 真实端各取了一次证据，两边独立指向同一结论：电脑端那个 agent
自己报的是"图片可看 ⚠️ 直接内联失败（MPO），转码后可看 —— 管线未修"，而同一张
MPO 在手机的回显气泡里被 ArkUI 正常解码出来。也就是说**解码能力不是瓶颈，白名单
才是**。

### 8.3 `file:` 前缀与"裸绝对路径"的分界

预览端点吃的是 `/api/console/upload` 返回的**裸绝对路径**（`C:\…\media\x.jpg`），
`encodePreviewPath`（`net/ApiClient.ets:55-67`）负责 `\`→`/`、去前导斜杠、丢掉
`.` 与 `..`、逐段转义。桌面端的工具还会回 `file:///…` 这种引用，它指向的是**电脑
那个文件系统**，这台手机取不到一个字节。

手机侧只掐 `file:` 前缀（`Parts.reachable()`），其余一律放行 —— 包括那个裸 Windows
路径。**这条是过滤的红线**：每轮回归都要真发一次附件，确认缩略图照常出来。

被过滤掉的引用：气泡不出图/影/音、顶栏 `📁` 不数它、资产面板不列它的行。但转录里
那句 `[图片]` 标签**留着** —— 那一轮确实带了个图，抹掉等于改写用户发过的东西。
`file` 分片同理：取不到的 URL 抹掉，文件名留着。

文件名本身也常常是**整条路径**（电脑端从它自己的文件系统里带出来的 `…\media\patch-notes.md`）。
只在**显示**上截成最后一段（`Parts.leafOf()`，`model/Parts.ets:115`）；发去预览端点的那个 URL
一个字符都不动 —— 截错那一刀就是 404。

同一个 `file:///…` 前缀在**工具输出**里是另一回事，那里不掐它。电脑端的发文件工具把
文件写在 `plugin_call_output` 的 `data.output`（一份序列化成字符串的块列表）里，每条
`source.url` 都带 `file://` —— 而预览端点吃的恰好就是剥掉 scheme 之后那条裸绝对路径，
桌面端自己取字节时也是先剥前缀再 GET。于是这一处 `file:` 不是"手机够不到的引用"，
而是"电脑端刚刚交给你的那份文件"：`Parts.localRef()`（`model/Parts.ets:176`）剥前缀，
剥完走的就是本节上面那条 `encodePreviewPath`。判定谁是交付很简单：块列表里有带 `source`
的 `data` 块，而 content part 里没有 —— **`name` 不在判据里，也不能当判据用**：真实历史里
21 个数据块有 8 个压根没有这个字段（6 个 `url` 型、2 个 `base64` 内联），同时另有 1 个**带名字**
的内联块，"缺不缺名字"与"字节是内联还是路径"是两件独立的事。工具卡那条路的形状与验证见
[05](05-architecture.md)「电脑端「发文件」住在工具卡的 output 里」。

