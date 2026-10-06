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
| `media` | 预览字节取回与解码、沙箱缓存、播放、录音 | `MediaLoader.ets`、`MediaCache.ets`、`AudioPlayer.ets`、`VoiceNote.ets` |
| `ui` / `pages` | 纯渲染 + 事件，尽量薄 | `pages/Index.ets`（登录）、`HomePage`、`ChatPage`、`SettingsPage`、`CleanupPage` |

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

对端（桌面端）发起的轮次靠 `catchUpTurn`（`state/ChatStore.ets:439`）+
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
| 沙箱缓存（`cacheDir/media` 与 `cacheDir` 根上的 `voice-*.m4a`） | 播放过的字节与录的音 | 本机副本，清理页删的就是它；系统也可以回收 |
| 不存 | 桌面端全局配置 | 手机只读那些端点 |

`key: auth_password` 是**明文**存在应用私有 Preferences 里的（`core/Prefs.ets:27,215`）。
这是一个已知取舍，理由与风险写在 [../SECURITY.md](../SECURITY.md)。

## 登录后落在哪

`Index.doLogin` 成功后 `pushUrl('pages/HomePage')`，**不往下继续跳进会话**。这里原先
有一条 `HomePage.autoJump()`：第一次 `sync()` 拿到会话列表后立刻 `openChat(前台会话)`，
于是"登录"在用户眼里变成"回到上次聊到一半的那一页"。用户明确要求登录服务器后先停在
主页（智能体选择 + 会话列表），所以那条自动跳转连同它的 `jumped` 一次性守卫一起删了；
想回上次那页，点主会话卡片上的「继续 ›」。加回来的唯一正当理由是它变成了**用户自己的
设置项**，而不是首屏行为。

## 草稿

输入框内容按会话持久化（`ChatPreference.draft` → `Prefs` → `ChatStore.saveDraft`），
返回键被拦截时先存草稿；发送成功或用户清空后清掉。用户否决过"离开时弹确认框"，
所以这里是静默保存，别再弹窗。

草稿存的是**文字**，托盘里的附件从来不进草稿。所以任何一句"这条消息会带上某个附件"
的话也不能进草稿 —— 超长引用那句说明在 `flushDraft()` 里剥掉（见「引用」），否则下次
开机恢复出来的就是一句指向不存在文件的承诺。

## 输入框：工具带与 chip 在上，输入栏在下

`Composer` 分成三层。**工具带**是最上面一条 34vp 高的窄行，只有三个小图标：A/T
（切语音/文字两态，A=audio、T=text，写的都是"点下去会落进哪一态"，字号 14fp 而不是
 ＋ 的 20fp —— 同字号时字母比全角 ＋ 高出一截，08-testing §6 有像素测量）、＋（附件菜单）、
×（清空输入框）。× **常显**：空字段时它是灰的、点下去什么都不做。第一版是"有字才出现"，
真机上被读成"清空功能不见了"——一个忽隐忽现的键，正是需要它时找不到的那个键；灰掉才
同时说清"在这儿"和"现在没得清"。有字时它是 `app_error` 那一支红（浅色 `#FF4D4F` /
深色 `#DC4446`）而不是"深一点的灰"：这一条带上只有它会**扔掉用户打的东西**，而橙色已经归
右边那颗发送键，两枚同时发亮就分不出谁是主操作；药丸底色不变，红了整块会被读成报错。
它只清文字，托盘里每个附件自带自己的 ×。**chip 行**
（loop / model / 审批三个 selector）在它下面
自占一行 —— 一开始把这两行并成一行，结果三个 chip 全被挤成省略号，所以又拆回去。
**输入栏**因此只剩两样东西：文字态是 `TextArea` + 发送，语音态是整一条「按住 说话」
—— 按住开始录、松手直接把这一段发出去、手指上滑越过 60vp 就变成「松开取消」。
走的仍是 `media/VoiceNote.ets` 那套 `AVRecorder`，松手发送走
`ChatPage.endRecord(discard, sendAfter)` 的 `sendAfter` 分支：只发这一段，
不动已输入的草稿，也不动托盘里别的东西。

这样分层的理由是同一句话：「切换图标挤占了会话栏」。图标缩到 34vp 并挪上去之后，
真机（1224px 宽）上文字态的文本框从 534px 变成 862px，语音态的说话条从 431→1144
变成整幅 80→1144。

四条刻意的取舍：

- **app 内不做语音转文字**。系统输入法自带听写，重复实现一遍只是给自己添一个
  离线模型；语音态覆盖的是输入法给不了的那件事 —— 把**音频本身**发出去。
- **语音态把发送键让位**。按住松手自己就发了，发送键在语音态只在托盘非空时才回来
  （`showSend()`）—— 用户从 ＋ 里挑的图片/文件总得有个地方发出去。
- **语音态不留隐形内容**。长按引用与「📝 长文本」都会把字塞进文本框，所以这两处
  先把 composer 退回文字态（`ChatPage.ets` 的 `quote()` 与 `onLongText`），否则内容
  落在一个看不见的字段里，只剩一个亮起来的发送键。
- **录音中 T 无效**（`onToggleMode` 里的 `recording` 守卫）：把说话条收起来会让人
  找不到停止键。松手上交与上滑丢弃之外还留着两条退路 —— 转录下方那条录音条的
  「停止录音 / 丢弃」，以及 ＋ 菜单里同一对开关；第一次录音时系统弹的麦克风授权框
  会吃掉手指，没有这两条退路就出不来了。

## 清理

主页那一行「清理」不直接删东西，它打开 `pages/CleanupPage.ets`
（`pages/HomePage.ets:112`）。原因是这几类本机数据的**撤销代价差得很远**：缓存的片段
重播一次就回来了，录的音发出去就不再手里有，会话偏好要重新一个个挑。所以先分六类
列出来（`StoreHub.tally`，`state/StoreHub.ets:133`），空的那类禁用并写明「没有可清的」，
勾选后还要过一层二次确认，确认文案里点名只列选中的类别（只选了类别里的几条时写
「只删其中 N 个」），再落到 `StoreHub.runCleanup`（`state/StoreHub.ets:178`）。

六类是**读一遍沙箱**得出的（`MediaCache.files()`，`media/MediaCache.ets:173`），按容器
后缀而不是 MIME 分桶：`cacheDir/media` 里的 `.mp4/.mov/…` 算看过的视频，`.m4a/.mp3/…`
算听过的音频，`.pdf/.md/…` 算打开过的文档，落不进任何一组的进「其他缓存」；
`cacheDir` 根上那些 `voice-*.m4a` 单列为「录的音」—— 它们不在 `media/` 里，早先的
一页只数 `media/`，于是发出去也留着的录音在清理页上完全是隐形的。

类别之内还能**逐条**收：类别行右侧的「▾ 逐条」把这一类的每一份副本摊开成一行。行上先是
**名字**，下面一行才是 `大小 · 最近写入时间`。名字有两种来源：副本落盘用的是
`digest(serverUrl|ref)` 加后缀，服务器那边的文件名不在盘上，这份映射当下只活在内存里 ——
`StoreHub.cachedLabels`（`state/StoreHub.ets:148`）把每个开着 store 手里仍有引用的 ref
哈希回去、和设备列出的清单对上，对得上的显示**原名**；没有任何引用剩下的副本（包括**这次
启动以来还没打开过的会话**留下的）拿不到原名，就显示它在设备上**本来就有的那个名字**
（`CleanupPage.shownName`，`pages/CleanupPage.ets:331`）：缓存副本是 `<哈希>.<后缀>`，
录音是 `voice-<毫秒时间戳>.m4a`。两边都带容器后缀，所以每一行自己说得出是什么格式，不再
有一整排「文档 / 音频」这种认不出也分不出的泛称；把那个会话打开一次，原名就回来了 ——
名字是尽力而为的提示，不是一份会过期的侧车元数据。

两层必须一眼分得出，不然「勾这一类」和「勾这一份」看起来是同一排控件。所以版式是**父子**
而不是并列：类别行是一张卡（`surface` 底、细描边、24 的圆形勾选、标题 `body` + Medium），
展开的副本挂在卡左缘那道 2vp 竖线上（`FILE_RULE`，`pages/CleanupPage.ets:40`），行自己
不再套卡——18 的浅色勾选、`caption` 字号、`text_secondary` 名字。名字过长时**从中间省略**
（`EllipsisMode.CENTER`，`ui/cleanup/CleanupFileRow.ets:52`），尾巴上的后缀因此留着：一行
再窄也说得出那是什么格式的文件。

名字那一行同时是**先看再删**的入口（`ui/cleanup/CleanupFileRow.ets:61`）：视频在本页
自己的浮层里放，音频和录音走全 app 那一个扬声器，文本类文档在页内读出来（`TEXT_EXT`，
`pages/CleanupPage.ets:48`）—— 读上限 32 KB（`READ_CAP`，`pages/CleanupPage.ets:37`），
更长的只显示开头、末尾写明「只显示开头 32.0 KB」，尾巴留在磁盘上；带文本后缀但含 NUL 的
二进制回退给系统打开器，其余后缀同样走系统（系统答「暂无可用打开方式」是系统的说法，
不是 app 的话术）。

这里只有一条删除路径：勾选状态是
「一组文件名 + 一个会话偏好开关」，类别复选框是**推导**出来的（本类的副本被全选时才亮），
所以「全部」只是把同一组名字一次填满的快捷方式，不是第二种删除语义。旧的
`MediaCache.clearKind()` 因此整条删掉了，留着它就有两条会在后缀上各自演化的路。
删完的回执报的是**真的删掉了几个**（`StoreHub.runCleanup` 返回 `dropFiles` 的实数）：
系统在中间回收过的文件不算数，回执就不会虚报。

四类数据**故意不在这一页**，各自的方向不同：

- **图片**：解码后的 `PixelMap` 只在内存里，从不落盘，所以没有可清的量。
- **「下载」的东西**：走 `photoAccessHelper` 进系统相册，已经出了沙箱，这一页管不着，
  也不该假装管得着。
- **未发送的草稿**：那是有人在写字，缓存清扫没资格碰。要丢草稿只在输入框里删。
- **保存的账号 / 口令 / 服务器地址**：登录配置，在登录配置页逐条删（那里每行有
  「删除」），不混进「清理缓存」这种一听就该顺手全勾的动作里。

边界要说清楚：**清理从不碰服务端历史，也不吊销会话令牌**。删会话是电脑端的决定，
手机上一划不该替所有共用这个账号的设备把它抹掉。清完之后仍然留在登录态，直到用户
自己点「退出」。

一个坑已经踩过，改这个页面时别再掉回去：类别行必须是 `@Component`
（`ui/cleanup/CleanupRow.ets:13`）而不是带普通参数的 `@Builder`。计数是异步读回来的，
`@Builder` 按值传参只渲染一次、之后不再跟随页面状态，六类会永远停在「没有可清的」。
只有组件的 `@Prop` 会跟着父级更新。逐条展开出来的副本行同理，是 `ui/cleanup/CleanupFileRow.ets`
——勾一下就要立刻反映到类别复选框和按钮上的计数，按值传参的 builder 做不到。

## 多媒体的字节从哪来

`Image`、`Video`、`AVPlayer` 都不能带请求头，而这个 App 从不把 bearer token 写进
URL —— v1 写在 URL 上，等于把凭据塞进每一条请求行、代理日志和聊天截图。所以
预览字节统一走 `ApiClient.fetchBytes()`（`net/ApiClient.ets:132`），口令在
Authorization 头里，按三种去向分流：

| 内容 | 去向 | 代码 |
| --- | --- | --- |
| 图片 | 字节解码成 `PixelMap` 直接画 | `media/MediaLoader.ets` |
| 视频 | 落沙箱一次，`Video` 用 `file://` 打开 | `media/MediaCache.ets:pathFor` |
| 语音/音频 | 落沙箱一次，`AVPlayer` 用 `fd://<fd>` 打开 | `media/AudioPlayer.ets:48` |

历史里的内联 `data:` URI 在本地解码（`Image` 画不了它），直连的 http(s) URL 原样
透传，两者都不需要口令。缓存文件名是引用的 FNV-1a 摘要 + 原容器后缀：后缀必须留着，
两个播放器都靠它选解封装器。

`AVPlayer` 是状态机：给 `url` 赋值只是**异步**上报 `initialized`，而 `prepare()`
除这个状态外哪儿都不合法。所以 `prepare()`/`play()` 都挂在 `stateChange` 回调里
（`AudioPlayer.onState()`，`media/AudioPlayer.ets:79-96`），写在原地会抢跑并报
`unsupport prepare operation`。
`play()` 因此不 reject —— 失败一律走回调冒到通知条，播放器全 App 唯一，两条气泡
不能同时出声。

## 回显与归一：附件的标注只有一份

点发送的那一瞬间气泡是本地造的（`ChatStore.addUserBubble`，`state/ChatStore.ets:735`），
几秒后服务端把这一条归一回传、走 `toUi()`（同文件 `:660`）。两条路必须说出同一句话，
否则用户会看着自己那条气泡改名。所以标注只有两份真源：

| 一件事 | 唯一一处 | 两边都用它 |
| --- | --- | --- |
| 某类 part 在文字里长什么样（`[图片]` / `[语音]` / `[文件: 名]`） | `Parts.label()`（`model/Parts.ets:66`） | `Parts.displayText()` 与 `addUserBubble` |
| 一个附件算图片还是音频 | 发送层那份 `mimes[]`（`ChatStore.send` 里由 `Attachment.mime` 映射出来），判定走 `ContentType.forMime()`（`core/Wire.ets:86`） | `ChatApi.buildParts` 与 `addUserBubble` 读同一个下标 |

第二行是"同一份 mime"而不是"同一个函数"：上传回来的 `file_name` 是服务端给的，扩展名归它改，
回显要是拿它反推 MIME，服务端一改名气泡就跟请求体说的不是一回事了。

第一个上传的音频/视频/文件同时回填 `imageRef`/`videoRef`/`audioRef`/`fileRef`，气泡因此
当场就能播，而不是等归一那一下才长出播放器。**只带附件不带文字**也在这条规则里：标签就是
正文，气泡不会塌成空。想在发送层再写一遍 if 之前先回到这张表 —— 那正是这个 bug 的形状。

## 电脑端「发文件」住在工具卡的 output 里，不在 content part 里

电脑端把文件交给用户的那条路，不产生 `file` / `image` 类型的 content part。它的形状是
一张 `plugin_call_output`，`data.output` 是一个 **JSON 字符串**，解开是一份块列表：
每个文件一个 `{"type":"data","name":…,"source":{"type":"url","url":"file:///…"}}`，
内联的那一种把 `source` 换成 `{"type":"base64","data":…,"media_type":…}`，末尾跟一句
`{"type":"text","text":"File sent successfully."}`。所以"发了十二个文件"到手机上就是
十二张卡，卡片正文是一整段 JSON —— 只按 content part 找媒体的老路径一个文件也看不见，
这正是当初那个 bug 的形状。

读它的是 `Parts.toolMedia()`（`model/Parts.ets:192`）：块列表解不出来就返回空，普通工具
那句"命中 3 条结果"因此原样留在卡里，绝不会被当成半截 JSON 改写。解出来了才动两处：
文件按 mime 归成图/影/音/文档填进那四个 `*Ref` 槽（于是播放、缓存、资产面板、`📁` 角标
全部复用第「多媒体的字节从哪来」一节已有的机制，一行新渲染代码都不加），卡片正文换成
工具自己说的那句话。直播流和重进会话走的是两个入口 —— `Parts.toolMedia()` 在
`stream/StreamReducer.ets:279` 与 `state/ChatStore.ets:681` 各被调一次 ——
两边调的是同一个函数，这是本文件反复出现的那条规矩：一条消息只有一个解析处。

块里那个 `name` **不保证存在**，而且它缺不缺与 `source` 是哪一类**互相独立**：真实端两个会话
21 个数据块里 8 个没有 `name`（6 个是 `url`、2 个是 `base64`），另外还有一份 `base64` 是**带**
名字的。所以取名不能按"内联就一定无名"分派，只能三路走（`model/Parts.ets:239`）：工具给了名
就用；没给名、`source` 是 `url` 的还能从路径读叶子；两头都没有才落 `Copy.chat_file_inline`
（「内嵌文件」）—— 内联块的"路径"是整串 `data:…;base64,…`，读它的尾巴当文件名就是在屏幕上
打一串乱码，真实历史里那 2 个块正好都长这样。这条文案和别的显示文案一样只有一个
出处 —— 它经 `PartTemplates.inlineFile`（`model/Parts.ets:46`）注入，注入点在
`ChatStore.partTemplates()`（`state/ChatStore.ets:44`）里，忘了接就会显示成空。

内联那份还牵出视图层的两条，说的都是"字节已经在消息里"这一件事：
`Bubble.openable()`（`ui/chat/Bubble.ets:118`）对 `data:` 开头的引用不给「查看」，因为它
根本不在 `MediaCache` 的寻址范围内（缓存按引用算哈希找文件，`data:` 那条长串取不到任何
东西），点了只会得到一句没用的"没能取回字节" —— 这与 `quotable()` 不把 `data:` 编进
新请求体是同一条规矩。大小那一行则改用 `Parts.inlineBytes()`（`model/Parts.ets:381`）
从 base64 长度折算，不解码；否则一份明明已经在这台手机上的文件，会被写上「仅电脑端」。

`url` 那条引用带 `file://` 前缀**不是**§8.3（[07](07-server-contract.md)）里被掐掉的那种。
差别在于这句话是谁说的：content part 里的 `file:///C:\…` 是电脑端在描述**它自己屏幕上**
渲染的图，手机拿它无处可取；而工具输出里的这一条是电脑端在说"这份文件我交给你了"，
预览端点吃的恰好就是剥掉 scheme 之后的那条裸绝对路径 —— 桌面端自己也是这么做的。
`Parts.localRef()`（`model/Parts.ets:176`）就是这一刀。

视图层还有一条例外：带着文件的工具卡**不进**§158 那套连排折叠组，并且会把它所在的连排
打断（`ChatPage.carriesAsset()`，`pages/ChatPage.ets:1465`）。合组是给"一排什么都没交付"
的卡省屏幕；交付本身被折进 `×N`，用户就又只剩文字了。

同一处还管"找得到"：带文档的卡以**文件名当标题**（`Copy.chat_tool_delivery`），工具名退到
下面一行；交付那几行的底色与描边走主色（`Bubble.fileBlock(delivery)` /
`audioBlock(delivery)`，`ui/chat/Bubble.ets:256`）。`delivery` 是**调用点传进去的常量**而不是
从 `item.role` 推出来的：工具卡那条 `plugin_call_output` 的角色归服务端说，视图不该拿它当
"这是收进来的一份东西"的判据 —— 谁在渲染哪一侧，调用点自己最清楚。
标题那条只对**文档**生效，因为解析层把 `output` 里的 `name` 只写进文档一个槽位
（`stream/StreamReducer.ets:292`、`state/ChatStore.ets:693` 两处同形），图 / 影 / 音三个槽只留
ref。不能图省事把名字塞进 `fileName`：`fileBlock` 的判据是 `fileRef` 或 `fileName` 非空，那样
会在图片下面多画一张文档卡。要让媒体卡也带名字，得先给三种媒体各加一个名字字段（模型 + 偏好
持久化 + 两个解析点 + 渲染），而不只是改标题。

## 引用：把一条历史消息送回输入框

长按气泡 → `Bubble.quoteMenu()` 按这条消息实际有什么内容列出条目 → `ChatPage.quote()`
（`pages/ChatPage.ets:1008`）分两条路：

- **文字**转成 markdown 引用块（每行前缀 `> `）。电脑端按引用渲染，模型读到的也是同
  一份文本，不需要服务端为"引用"加任何字段。超过 600 字（`QUOTE_MAX`，按字计，因为
  输入框装的就是字）时不再硬截：输入框里留一段**整行收尾**的预览 + 一行说明，全文作为
  `Attachment.text` 挂在托盘里，发送时直接编进 multipart 体成为一份 `.txt`。不落临时
  文件：文件要能从"引用那一刻"活到"按下发送"，而 `cacheDir` 在系统压力下会被回收，
  留下的残骸还得另立删除规则 —— 内存里这份和托盘本身同生命周期，托盘不落盘，它也不落。
  预览切在行边界上：半行看着像渲染器断了，不像引用还有下文。
  那行说明与全文**同生同死**：`remove()` 按附件名只撤属于它的那一句（连着引用两条长
  消息时各撤各的），`flushDraft()` 落盘前把所有这类句子剥光 —— 草稿只活得过重启，
  托盘活不过，留着就是向电脑端承诺一份永远不会到的文件。屏幕上不剥，那里 chip 是真的。
- **图片/视频/语音/文件**只带一个 `Attachment.ref`，即服务端已经存着的那个路径。
  `UploadApi.upload()` 见到 `ref` 非空就直接把它当上传结果返回，一个字节都不再搬 ——
  把剪贴簿里的 clip 拉回手机再传一遍，只会在服务端留下第二份同名文件。

`Attachment.mime` 在这里填 `image/*` 这类通配是安全的：`ChatApi.buildParts()` 只看前缀
决定 part 类型，mime 本身从不上线。`data:` 开头的内联字节不可引用，那等于把整个文件
塞进请求体，所以 `Bubble.quotable()` 把它挡掉。

一个 ArkUI 坑：`Image`/`Video`/语音 chip 自带点击手势，长按会被它们吃掉，父 Column 上的
`bindContextMenu` 就只剩气泡边缘几像素能触发 —— 所以同一份 builder 也挂在这些子节点上。

## 会话资产：查看、下载、转发、删掉本机副本

服务端没有"本会话资产清单"这种端点，也不需要：转录本身就是清单。`ChatPage.collectAssets()`
（`pages/ChatPage.ets:1101`）扫 `this.items` 的四类 ref，产出一张 `AssetRow` 视图
（`model/Asset.ets`）—— 它不是第二个存储，所以永远不会和屏幕上的气泡说法不一。
表头的 `📁 N` 由 `countAssets()` 维护，那个函数**不碰文件系统**：它在每一帧流式回复后都会
跑一遍；`statSync` 只发生在打开面板的那一刻。

四扇门全是用户亲手打开的系统界面，所以整个功能不申请任何权限（`media/Export.ets`）：

| 动作 | 走哪 | 备注 |
| --- | --- | --- |
| 图片/视频下载 | `photoAccessHelper.showAssetsCreationDialog` | 相册不收音频和文档 |
| 语音/文件下载 | `picker.DocumentViewPicker.save` | 目标目录由用户选 |
| 转发 | `systemShare.ShareController` | utd 由后缀查，写死类型会让面板一个候选都不列 |
| 打开（文件气泡上的「查看 ›」） | `ctx.startAbility` + `ohos.want.action.viewData` | 交给系统按类型匹配阅读器 |

用户在系统弹窗里按"取消"是正常结果，不是失败，所以那种情况回空串、状态行留空。
把字节写进这些 URI 时要 `fs.OpenMode.READ_WRITE`：相册给回来的 URI 不接受只写打开。

「打开」这一扇（`media/Export.ets:192`）和转发共用同一个后缀查表（`utdOf()`，
`media/Export.ets:64`），但**查不到类型时的处理相反**：转发查不到就直接告诉用户"不认识的
类型"，打开则把 `type` 整个省掉，让系统自己去读 URI 后缀 —— `want.type` 写了却不匹配文件，
才是每个候选应用都退出匹配的原因。`getUniformDataTypeByFilenameExtension` 的第二个参数
`belongsTo` 可选且**没有默认值**，传 `''` 抛的是 `Parameter error`，不是返回空串，所以那行
只能省略、不能填空。交接本身还要过系统那道「"QwenPaw"想要打开"<应用>"」确认（模拟器实测会弹，
`取消` / `允许`）—— 那是 OS 的跨应用启动闸门，app 无权代点，也因此这一扇仍然不申请权限。

文件气泡只负责"看"（`ui/chat/Bubble.ets:232` 的 `fileBlock()`）：两行卡片（名字 + `类型 · 字节在哪`）
加一个 `查看 ›`，点下去先由 `state/ChatStore.ets:341` 的 `openFile()` 经 `media.localPath()`
把字节取进 `MediaCache`（和资产面板同一份），再拉起外部应用。**删仍然只在资产面板与清理页** ——
气泡上不放删除键，避免手滑。名字显示前
过 `Parts.leafOf()`（`model/Parts.ets:115`），因为真实端给的是整条 Windows 路径。

"删除副本"删的是 `MediaCache` 里那一份（`MediaCache.drop()`，`media/MediaCache.ets:137`），
电脑端原件不动，下次播放重新取一次 —— 面板上那行"仅电脑端"就是它真实的处境。图片在存下来之前一直显示
"仅电脑端"，因为解码路径只产 `PixelMap`，从不落盘。

## `/` 面板按来源分组

`/workspace/commands/available` 每条都带 `category`，那是桌面端注册表记录的**来源**
（`builtin` / `conversation` / `control` / `daemon` / `skill` / `auto` / `user` / `mode` /
`custom_loop` / `plugin`，PawApp 还会发 `pawapp:<id>`）。桌面控制台把这些拼成一个平铺菜单，
手机不照抄：`Composer.slashGroups()` 按 category 切块，`Copy.slashGroup()` 出中文表头。

四条刻意的取舍：

- **不重排**。分组只切块，块内和块间的顺序都还是注册表顺序 —— 手机端没有资格判定
  哪条命令比另一条更重要。
- **只有一组时不出表头**。`/c` 只剩一条 `/compact`，配一行"会话"是噪音。
- **认不得的 category 原样显示**，空 category 落到"其他"。注册表的词表会长（`pawapp:`
  就是后加的），电脑端升级不该让手机上某半菜单突然没有标题。
- **一次最多 20 条，面板自己封顶可滚**。`MAX_SLASH_ROWS`（`pages/ChatPage.ets:46`）只 bound
  节点数，看得见多少交给一层封顶 176vp 的 `Scroll`（`ui/chat/Composer.ets`）。这两件事都是
  真机 + 真实注册表才逼出来的：早期是"6 条 + 不能滚"，而真机上那台桌面端的注册表有 5 组、
  表头读作「控制 / 会话 / 自动 / 后台 / 内置」，靠后的几组在手机上压根够不着 —— mock 的词表
  太短，模拟器上永远看不见这个形状。

手机自己补进去的 loop 模式标成 `category='loop'`（`pages/ChatPage.ets:660`），
所以它总是排在注册表条目之后。

一个 ArkUI 坑：`ForEach` 的 key 必须带上"这组有没有表头"（`ui/chat/Composer.ets`）。
只按 category 出 key，`/` → `/c` 时活下来的那组 key 没变，缓存下来的旧子树会**继续显示
已经不该出现的表头**——实测复现过，模拟器上肉眼可见。

## ＋ 菜单：技能与 MCP

两个入口挨在一起，性质却相反：技能是**要发出去的一条消息**，MCP 是**一份只读事实**。

两行的名字用后缀式（`🧩 技能 (电脑)` / `🔌 MCP (电脑)`），面板标题用长写法（`电脑端的技能` /
`电脑端的 MCP`）：菜单是一眼扫过的来源清单，尾巴要短；进了面板，"手机 vs 电脑"才是被读的那件事。

**技能**读 `GET /api/skills`，`ComposerApi.skills()`（`api/ComposerApi.ets:137`）只留下
`enabled` 且渠道可达的条目 —— 渠道判定在 `Channel.reachable()`（`core/Wire.ets:159`）：
`channels` 为空算不限渠道，否则要出现 `all` 或 `console`。菜单里只有**一行**「🧩 技能
(电脑)」，点开是 `ui/chat/SkillPanel.ets`：一行一个技能，左边 `emoji + 名字`、右边写清点下去
会得到的 `/名字`、下面两行简介。点一行只做一件事：把 `/名字` 写进输入框
（`ChatPage.pickSkill()`，`pages/ChatPage.ets:249`），剩下的分发靠服务端那条 slash 回退。
手机上**没有"启用技能"这个动作**，那是桌面端的全局配置。

技能为什么是面板不是菜单里的若干行：一条 SDK 事实决定了 `bindMenu` 挂不了二级菜单
（这个 API 的 `MenuElement` 只有 `value` / `icon` / `symbolIcon` / `enabled` / `action`，
**没有 `children`**，`Sdk/.../ets-loader/declarations/common.d.ts:16083`），所以"技能子列表"
只能是自己的一层面板。而平铺进 ＋ 菜单在真机上被证伪了：那台桌面端有 **18 条**技能，
菜单变成一堵墙，且菜单行放不下简介。形状于是照 `McpPanel` 抄 —— 同一套遮罩、卡片、
「关闭」，用户认得。一个技能都不剩时 ＋ 菜单留一行灰掉的「电脑端没有可用的技能」：
整行不见会被读成手机没加载出来，而这行说的是**菜单里有什么**、不是**为什么没有** ——
读失败与电脑端真的一条没启用会落到同一个空数组上，那行没资格替人判断是哪一种。

**MCP** 读 `GET /api/mcp` 与 `GET /api/mcp/tools/{key}`，面板是 `ui/chat/McpPanel.ets`。
DTO 只声明 `key` / `name` / `description` / `enabled` / `transport`（工具那层再加
`name` / `description` / `enabled`）；`url`、`headers`、`command`、`args`、`env`、`cwd`、
`input_schema` 在 `model/Dtos.ets` 里连字段都不写，`api/ComposerApi.ets` 的 `mcpClients()`
（`api/ComposerApi.ets:154`）与 `mcpTools()`（`api/ComposerApi.ets:176`）也只把上面那几个字段一个个挑出来，
多一个都不读。
理由很直白：那几个位置正是 bearer token 和 API key 的常见落点，而**手机屏幕是会被拍照的**。
回归时 mock 故意在 `env`/`headers`/`url` 里塞了带 `FAKE-NEVER-RENDER` 字样的假凭据，
再用可访问性树（它包含每一条渲染出的文本，比截图严）扫全树，零命中。

面板只读：开关客户端（`POST /api/mcp/toggle/{key}`）与改工具白名单
（`PUT /api/mcp/tools/{key}`）都是桌面端的全局配置，手机一个都不发；mock 把这三条路径的
非 GET 一律 405，好让"哪天手滑写了"在开发机上就响。停用的客户端返回空工具表，面板显式写
「客户端已停用，读不到工具」，不让它被读成"这台服务器没有工具"。

## 定时任务：为什么手机上不做

服务端有完整的 cron 能力（`src/qwenpaw/app/crons/`，`POST /api/cron/jobs` + 暂停/恢复/
立即执行/历史），桌面控制台有编辑器。手机**故意不做**这一面，两个理由：

1. `CronJobSpec` 不是"一条命令加一个时间"。它要 `dispatch.target`（真实存在的
   `user_id` + `session_id`）、cron 表达式或 `once`+`run_at`+时区+repeat 约束，
   错一项就是 422。手机上做等于把桌面端那个表单页重写一遍。
2. 更要紧的是 `runtime.tool_safety` 默认 **False**，注释写得很清楚：所有工具**不经审批**
   直接执行。定时任务是在没有人的时候跑的，而本 App 的整条安全线是"审批只能由人点按钮"。
   从手机开一个无人值守、默认免审批的任务，正好是这条线最不该被绕开的地方。

要加的话，正确的第一步是只读（列出电脑端已建的任务 + 暂停/恢复），不是编辑器。

## 气泡里的 markdown

桌面端用 react-markdown 渲染整份 GFM，手机不能塞一个 webview 进去，所以
`ui/chat/Markdown.ets` 只认 agent 真的会写出来的那几样：围栏代码、标题、无序/有序
列表、引用、分隔线、段落，行内是粗体/斜体/删除线/行内码/链接，**外加表格**
（`Markdown.parse` 的 `tableAt` 分支，`ui/chat/Markdown.ets:346`）。

一条硬契约贯穿整个文件：**认不出来的东西原样当文字显示，绝不显示成垃圾**。
表格那三条判定都从这里来——必须有分隔行（`| --- | :-: |`）、行首必须有竖号、
超过 6 列（`Markdown.MAX_COLS`，`ui/chat/Markdown.ets:323`）不认。所以
`a | b` 这种写在句子里的竖号、7 列的宽表，屏幕上就是一行普通文字，跟没做表格
之前一模一样。

表格是这里唯一一个**父容器必须知道子内容形状**的地方：网格要按列分宽度，而
ArkUI 的百分比是照着"传下来的约束"算的，一个靠内容定宽的气泡给不出这个数——
于是三列的表能长到屏幕宽、直接走出自己的气泡（实测过）。修法是气泡先看一眼
这份文字里有没有表（`Markdown.hasTable`，`ui/chat/Markdown.ets:330`），有就直接
吃满自己的宽度上限，没有才继续按内容收缩（`Bubble.bodyW`，
`ui/chat/Bubble.ets:133`）。渲染那一头，`MarkdownView.tableBlock`
（`ui/chat/MarkdownView.ets:194`）用等宽列 + 每格自己的对齐，流式光标落在最后
一格，`sig()` 把每格文字长度算进 key，否则长出来的格子不会重绘。

## 想加功能的人应该改哪里

| 想做的事 | 动哪 | 别动哪 |
| --- | --- | --- |
| 新端点 | `core/Wire.ets` 加常量 → `api/` 对应门面 → `model/Dtos.ets` 加形状 | 不要在页面里拼 URL |
| 新的输入能力 | `ui/chat/Composer.ets` + `ChatStore.send` | 不要让 Composer 直接发 HTTP |
| 气泡多认一种 markdown | `ui/chat/Markdown.ets` 解析 + `MarkdownView.ets` 渲染 | 别让不认识的形状变成垃圾，降级成原文 |
| 新断点布局 | `core/Breakpoint.ets` + 页面里按 `Bp.KEY` 分桶 | 不要按设备型号判断 |
| 新文案 | `l10n/Copy.ets` | 不要硬编码在组件里 |
