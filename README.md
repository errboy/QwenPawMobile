# QwenPawMobile

QwenPaw 桌面端的鸿蒙（HarmonyOS NEXT）遥控器：在局域网里找到本机运行的 QwenPaw 后端，
收发会话、上传附件、查看工具调用，并在桌面端挂起审批时**由人按下同意/拒绝**。

> QwenPaw 的模型、工具执行与历史都在桌面端那一侧。这个 App 不内嵌 agent 运行时，
> 它是一个严格建立在桌面端公开 HTTP 接口之上的客户端。

## 它能做什么

- 登录：不敲 IP。扫本机所在 /24，逐个地址问一次 `/api/auth/status`，只列真正会说
  QwenPaw 协议的机器。
- 会话：SSE 流式渲染（含 Markdown、思考块、工具调用与输出）、停止与重发、
  图片/视频/语音/文件附件、按来源分组的 `/` 快捷指令补全、loop 模式与模型槽位选择。
  输入框上方一条工具带用 A/T 切两态（A=audio、T=text）：文字态用系统输入法（听写也归它管），
  语音态把输入框换成整一条「按住 说话」—— 按住录、松手直接把**这一段音频发出去**、
  手指上滑则丢弃，app 内不重复造一套语音转文字。
- ＋ 菜单：除了相册/文件/音频/录音/长文本，还有一行 `🧩 技能 (电脑)`，点开是一张只读列表
  （名字 + 简介 + 点下去会得到的 `/名字`，自己封顶可滚）。点一行只把 `/名字` 写进输入框 ——
  分发靠的是服务端的 slash 回退，手机上没有“开启技能”这回事。
  `🔌 MCP (电脑)` 打开一份**只读**清单，展开能看每个客户端的工具。清单只取
  key/name/description/enabled/transport 五个字段，`url`/`headers`/`env`/`args` 既不渲染也不进日志
  —— 手机屏幕是会被拍照的。开关客户端、改工具白名单都属于桌面端的全局配置，手机上不做。
- 播放：收到的图片点按全屏，视频与语音在气泡里直接播，自己发出去的 clip 也能回放。
  字节带 Authorization 头取回后落进应用沙箱，**口令不出现在任何 URL 里**。
- 引用：长按任意气泡把那条消息送回输入框。文字变成 markdown 引用块，媒体与文件带的
  是服务端已存的那个路径 —— **一个字节都不重传**。长到输入框装不下的那句**不砍半**：
  框里留一段整行收尾的预览，全文随这条消息以 `.txt` 发出，电脑端拿到的是完整原文。
  那句"原文随本条发出"跟着附件走：点掉附件它就消失，草稿也只留预览，不会留下一句指向
  不存在文件的话。
- 会话资产：顶栏 `📁 N` 列出这一会话收发过的图片/视频/语音/文件，每行标出字节现在在手机上
  还是只在电脑端；可滚回原气泡、下载到相册或选定文件夹、转给系统分享面板、或只删掉手机这一份。
  出去的三道门全是用户确认的系统界面，所以不申请任何存储权限。
- 本机存储：主页一行显示媒体缓存占用与未发送草稿条数；「清理」进入独立的清理页，
  六类本机数据分开报数、按类勾选（类别里还能「逐条」只删其中几份）、执行前二次确认，
  只删手机上的副本；
  聊天转录始终在桌面端那一侧，手机上没有可误删的历史。
- 双向：桌面端发起的轮次，手机不退出重进也能看到；手机发的消息桌面端同步可见。
- 审批：待审批卡片出现在手机上，只有人点按钮才会发出 approve/deny。**没有任何自动批准路径**。
- 多形态：手机 / 横屏 / 折叠屏内外屏 / 阔折叠 / 三折 / 平板，按窗口宽度分五个桶，
  正文行宽封顶居中。
- `tools/qp-gate`：一个单文件 Python 守门代理，让只绑回环的桌面端安全地暴露给局域网。

## 五分钟看懂代码在哪

```
AppScope/                     应用级配置与分层图标资源
entry/src/main/ets/
  core/     端点表 · 状态码 · 失败模型 · Preferences · 断点 · 日志
  net/      HTTP 传输 · SSE 解码与会话 · 局域网扫描
  api/      六个端点族门面（auth/agent/chat/composer/approval/upload）
  model/    DTO，字段名是服务端的镜像
  state/    StoreHub 组合根 + AppStore + ChatStore（唯一数据源）
  stream/   RunController 运行状态机 + StreamReducer 帧归并
  polling/  全 App 唯一的 10s 轮询器
  theme/    设计 token（颜色/字号/宽度/动效）+ 深色与系统字号跟随
  l10n/     全部用户可见文案（页面里不出现硬编码中文）
  media/    预览字节解码 · 沙箱缓存 · 播放 · 录音
  ui/ pages/组件与三个页面
tools/qp-gate/                守门代理 + 79 项自检
docs/                         下面的文档
```

## 文档

| 文档 | 一句话 |
| --- | --- |
| **[docs/10-deploy-and-use.md](docs/10-deploy-and-use.md)** | **只想装到手机上用？看这篇**（不讲代码，从克隆到日常操作） |
| **[docs/11-agent-playbook.md](docs/11-agent-playbook.md)** | **让 AI 助手替你跑这套流程**：哪四件事必须回到人手上、现象→动作表 |
| [docs/01-getting-started.md](docs/01-getting-started.md) | 是什么、需要什么、20 分钟跑起来 |
| [docs/02-build-and-sign.md](docs/02-build-and-sign.md) | **编译不需要证书**；签名材料为什么不在仓库里 |
| [docs/03-run-on-device.md](docs/03-run-on-device.md) | 真机/模拟器装机、锁屏、网络口径、UI 检查 |
| [docs/04-desktop-cooperation.md](docs/04-desktop-cooperation.md) | 与桌面端协同（**最重要的一篇**） |
| [docs/05-architecture.md](docs/05-architecture.md) | 分层、四条硬规则、一轮回复的完整路径 |
| [docs/06-responsive-devices.md](docs/06-responsive-devices.md) | 断点体系与折叠形态实测数据 |
| [docs/07-server-contract.md](docs/07-server-contract.md) | 对接 QwenPaw v2.2.2-beta.4 的端点与 SSE 语义 |
| [docs/08-testing.md](docs/08-testing.md) | 自动化闸门、手工回归清单、待实机清单、想加测试从哪入手 |
| [docs/09-troubleshooting.md](docs/09-troubleshooting.md) | 现象 → 原因 → 处理 |
| [SECURITY.md](SECURITY.md) | 已知安全边界（含明文口令存储这个取舍） |
| [CONTRIBUTING.md](CONTRIBUTING.md) | 代码风格、提交与 PR 约定 |
| [AGENTS.md](AGENTS.md) | 给 AI agent 的操作手册 |

## 快速开始

```bash
devecocli check arkts    # 语法闸门
devecocli build          # 干净克隆就能过，产出 unsigned hap
devecocli run --device <序列号>
```

装到真机需要签名材料（本自动生成，仓库不带）：`devecocli auth login` 然后
`devecocli signature generate`，细节见 [docs/02](docs/02-build-and-sign.md)。

连桌面端：桌面版默认只听 `127.0.0.1`，手机连不上是正常的。推荐用
`tools/qp-gate`（桌面端零改动），原因和三条路的取舍写在
[docs/04](docs/04-desktop-cooperation.md)。

上面是"我熟，给我最短路径"的写法。**第一次搞的人直接照着
[docs/10-deploy-and-use.md](docs/10-deploy-and-use.md) 从头敲到尾**——那篇把装机、签名、
网关、登录，直到 App 里每个功能怎么用都摊开写了；丢给 AI 助手让它自己跑的话指
[docs/11-agent-playbook.md](docs/11-agent-playbook.md)。

## 环境要求

| | |
| --- | --- |
| 设备 | HarmonyOS 6.0.0(20) 及以上；`deviceTypes: ["phone","tablet"]` |
| 构建 | DevEco Studio 6.x + API 20 SDK（实测 26.0.0.621） |
| CLI | 可选，`devecocli` 1.3.4 |
| 运行时依赖 | **无第三方依赖**，全部用系统 Kit |
| 服务端 | QwenPaw v2.2.2-beta.4 |

## 状态

个人项目，能日常自用，尚未发布到应用市场。已知缺口列在
[docs/08-testing.md](docs/08-testing.md#6-已知仍未覆盖) 与
[CHANGELOG.md](CHANGELOG.md)，还没上真机跑过的项集中在
[docs/08-testing.md](docs/08-testing.md#7-待实机验证)。安全相关的取舍全部写在 [SECURITY.md](SECURITY.md)，
不藏。

## 许可

Apache License 2.0，见 [LICENSE](LICENSE)。
应用图标为本项目独立设计，与任何第三方商标无关联；请勿作为 QwenPaw 桌面版的官方移动端理解。
