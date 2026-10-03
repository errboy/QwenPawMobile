# 05 · 架构

`entry/src/main/ets` 下的分包按"谁依赖谁"而不是"功能像不像"。箭头方向就是允许的唯一依赖方向：

```
pages  ──►  ui  ──►  state  ──►  api  ──►  net  ──►  core
                     ▲                        ▲
                   stream                    model
                     ▲                        ▲
                   polling ─► state          theme / l10n / media
```

## 各包职责

| 包 | 职责 | 关键文件 |
| --- | --- | --- |
| `core` | 不依赖任何上层的地基：端点表、状态码、失败模型、偏好存储、断点、日志 | `Wire.ets`、`Failure.ets`、`Prefs.ets`、`Breakpoint.ets`、`Log.ets` |
| `net` | 传输：HTTP、SSE 解码与会话、局域网扫描 | `Transport.ets`（接口）、`HttpTransport.ets`、`SseDecoder.ets`、`SseSession.ets`、`ApiClient.ets` |
| `api` | 一个端点族一个门面，只做"发请求 / 解 DTO" | `AuthApi`、`AgentApi`、`ChatApi`、`ComposerApi`、`ApprovalApi`、`UploadApi` |
| `model` | DTO 与请求体形状，字段名对齐服务端 | `Dtos.ets`（`AgentRequest` 在 :171-181） |
| `state` | 唯一数据源 | `StoreHub.ets`、`AppStore.ets`、`ChatStore.ets`、`UiMessage.ets` |
| `stream` | 一轮回复的运行状态机与帧归并 | `RunController.ets`、`StreamReducer.ets` |
| `polling` | 全 App 唯一的轮询器 | `GlobalPoller.ets`（`POLL_INTERVAL_MS = 10000`，:13） |
| `theme` | 设计 token 与深色/字号跟随 | `Theme.ets`、`ThemeManager.ets` |
| `l10n` | 文案集中，禁止页面内硬编码中文 | `Copy.ets` |
| `media` | 头像/预览加载、录音 | `MediaLoader.ets`、`VoiceNote.ets` |
| `ui` / `pages` | 纯渲染 + 事件，尽量薄 | `pages/Index.ets`（登录）、`HomePage`、`ChatPage`、`SettingsPage` |

## 四条硬规则

这四条是从 v1 的具体缺陷倒推出来的，写在文件头注释里，改动前先读那段注释。

1. **组合根只有一个**：`StoreHub` 拥有 transport、六个 api 门面、两个 store 和轮询器。
   构造函数接收 `Transport`，所以测试可以塞一个假 transport 而不需要设备
   （`state/StoreHub.ets:1-8`）。页面不 import 全局 client。
2. **数组换引用，内容原地改**：成员变化必须发布**新数组**（否则 `@State` 不重绘）；
   逐 token 的内容变化在原地的 `@Observed UiMessage` 上改（否则一个 token 重建整个列表）。
   见 `state/ChatStore.ets:4-8`。
3. **只有轮询器发 `/api/chats`**：`ChatStore` 不自己轮。页面把自己注册进
   `GlobalPoller` 并接收快照，一轮 tick 全 App 只取一次会话列表。
4. **重连不清队列**：重连会重载历史，但把已排队的气泡**重新接回**而不是抹掉
   ——v1 每次重试就丢一条插进去的消息。

## 一轮回复的完整路径

```
Composer 发送
  └► ChatStore.send() → AgentRequest（stream: true，可选 reconnect / model_slot_override / request_context）
       └► SseSession 建流 ──► SseDecoder 切帧 ──► StreamReducer 归并成 UiMessage 增量
            └► RunController 管状态：running / done / error，断线 2-4-8s 退避、最多 3 次
                 └► ChatStore 落到 @Observed UiMessage ──► Bubble 渲染（含 Markdown）
```

对端（桌面端）发起的轮次靠 `catchUpTurn`（`state/ChatStore.ets:347`）+
`GlobalPoller` 追平，所以不需要退出重进。

## 停止与重发

`POST /api/console/chat/stop?chat_id=…` 之后本端把 run 标成已停止；
"重发"是把同一条用户消息再走一次发送路径，不做原地改写，因此历史里留下两条，
与桌面端的行为一致。

## 状态与持久化边界

| 存在哪 | 存什么 | 说明 |
| --- | --- | --- |
| Preferences（`qwenpaw_store`，`core/Prefs.ets:14-32`） | 服务器地址列表、令牌、账号、会话偏好、主题、扫描端口、主页紧凑开关 | 设备级，登出不删登录配置 |
| 内存 | 消息列表、run 状态、审批卡片 | 全量以服务端为准，重启后从 `/api/chats/{id}` 重载 |
| 不存 | 桌面端全局配置 | 手机只读那些端点 |

`key: auth_password` 是**明文**存在应用私有 Preferences 里的（`core/Prefs.ets:27,208`）。
这是一个已知取舍，理由与风险写在 [../SECURITY.md](../SECURITY.md)。

## 草稿

输入框内容按会话持久化（`ChatPreference.draft` → `Prefs` → `ChatStore.saveDraft`），
返回键被拦截时先存草稿；发送成功或用户清空后清掉。用户否决过"离开时弹确认框"，
所以这里是静默保存，别再弹窗。

## 想加功能的人应该改哪里

| 想做的事 | 动哪 | 别动哪 |
| --- | --- | --- |
| 新端点 | `core/Wire.ets` 加常量 → `api/` 对应门面 → `model/Dtos.ets` 加形状 | 不要在页面里拼 URL |
| 新的输入能力 | `ui/chat/Composer.ets` + `ChatStore.send` | 不要让 Composer 直接发 HTTP |
| 新断点布局 | `core/Breakpoint.ets` + 页面里按 `Bp.KEY` 分桶 | 不要按设备型号判断 |
| 新文案 | `l10n/Copy.ets` | 不要硬编码在组件里 |
