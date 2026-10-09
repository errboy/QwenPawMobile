# QwenPawMobile

专为QwenPaw 桌面端（win）开发的鸿蒙（HarmonyOS NEXT）版app：工作在局域网内，它是 QwenPaw 桌面端的延伸，非独立app。为提升QwenPaw的使用价值，特别优化和设计了很多实用的功能。

> QwenPaw 的模型、工具执行与历史都在桌面端一侧。这个 App 不内嵌 agent 运行时，
> 它是一个严格建立在桌面端公开 HTTP 接口之上的客户端。

## 它能做什么

- **协同电脑端**：登录访问局域网里运行的QwenPaw 桌面端，在app上直接会话。
- **聊天**：比直接在桌面端会话聊天更方便、更实用。
- **发送**：图片、视频、音频、文件都能发。可发送语音，"按住说话"，松手就发出去，上滑取消。语音模式在桌面端的"语音转写"中配置
- **接收**：AI 发来的文件、图片、视频、语音在手机上都看得见，点开就能看或播。在桌面端的基础上做了优化，使用更方便。
- **引用**：支持引用会话中的文本、图片、视频、音频等内容；一条消息太长时（引用的原文、自己打的都算）自动转文档发送，避开输入框字数与模型上下文限制，自己打的那条手机上另存一份全文副本，可在清理页删。
- **选技能、模型与模式**：通过app使用桌面端的skill，切换模型、loop 模式。清单只读，开关与配置权限仍在桌面端。
- **会话资产**：统一管理会话资产，可打开、下载、转发，也能删移动端缓存副本。
- **清理**：支持一键清理移动端缓存；也可以按类别选择删除。
- **审批**：支持审批功能，可设置移动端审批模式，与桌面端不冲突。
- **两端同步**：移动端可同步桌面端的会话内容，会话进度不丢失。
- **多种设备**：兼容手机、横屏、折叠内外屏、阔折叠、三折、平板等不同设备（鸿蒙（HarmonyOS NEXT）版）。
- **`tools/qp-gate`**：一个单文件 Python 小代理，桌面端和app轻松连接的桥梁。

注意：手机要连上桌面端，电脑上需要先运行 [`tools/qp-gate`](https://github.com/errboy/QwenPawMobile/blob/main/tools/qp-gate/README.md)（QwenPaw 局域网守门代理）工具

手机上的一切都是**只读或只写本地**：不改桌面端的配置、不申请存储权限、聊天历史永远在电脑那一侧。
这些边界逐条写在 [SECURITY.md](SECURITY.md) 与 [docs/04](docs/04-desktop-cooperation.md)。

## 要用它，电脑上得先跑起 `tools/qp-gate`

手机直连桌面端**必然连不上**，这不是 bug：QwenPaw 桌面版硬绑 `127.0.0.1`，端口还每次启动随机换。
所以这个仓库自带一个守门代理，**桌面端一行都不用改**，但**用手机期间它得在你电脑上跑着**：

| | |
| --- | --- |
| 它是什么 | 一个单文件 Python 3 程序，只用标准库、不装任何第三方包。听 `0.0.0.0:61700`，把手机请求转给桌面端 |
| 为什么鉴权做在它身上 | 转发到桌面端时来源是回环地址，而桌面端对回环**免鉴权** —— 所以那一层不参与，门禁必须由它亲自做。别用 `netsh portproxy` 代替，那等于把鉴权一起绕掉 |
| 手机上填什么 | 网关启动时打印一行 `手机填: http://<你电脑的局域网IP>:61700`。手机上不用敲它：登录页点 **「扫描局域网」**，列表里选中你这台电脑（扫描端口默认就是 `61700`，也就是网关的端口，不用改）。要改只有一种情况：直连桌面端、不经过网关时，去 **「登录配置」** 把它填成 `8088` |
| 不用时 | 停掉它。听的是 `0.0.0.0`，局域网里知道地址的人就只差一个登录口令 |

Windows 在工程根目录跑这一条启动，`start.bat` 自己找一个可用的 Python 3：

```bat
tools\qp-gate\start.bat
```

第一次跑它问你三件事：手机端登录用的**用户名**、**口令**、**放行哪个网段**（它把本机所在网段
作为默认值打出来，回车采用即可），然后弹一次 UAC 去防火墙放行 `61700` —— 这条放行是永久的，
不用了想删掉跑 `tools\qp-gate\start.bat firewall-remove`。常用的另外两条：

```bat
tools\qp-gate\start.bat show
tools\qp-gate\start.bat stop
```

`show` 再打一遍手机要填的那行地址和当前生效的配置；`stop` 是真的停 —— **网关窗口关了不等于
进程没了**，它被脚本拉起来时根本没有窗口。

Linux / macOS 没有 `.bat`：`python3 tools/qp-gate/qp_gate.py --init` 配置一次，之后
`python3 tools/qp-gate/qp_gate.py` 启动、`--stop` 停；防火墙那一步它不代劳，自己放行 TCP `61700`。

一步步带截图口径的装法在 [docs/10 §5](docs/10-deploy-and-use.md)，为什么非要这一层、
另外两条路的取舍在 [docs/04](docs/04-desktop-cooperation.md)，子命令全表在
`tools/qp-gate/README.md`（这个路径在开发树和发布树里位置不同，所以不给它做链接）。

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
tools/qp-gate/                守门代理 + 自带桩上游的自检
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

装到真机需要签名材料（在你本机生成，仓库不带）：`devecocli auth login` 然后
`devecocli signature generate`，细节见 [docs/02](docs/02-build-and-sign.md)。

连桌面端不在这三步里：**手机能不能连上，取决于电脑上那个守门代理跑没跑**，
起法都在前面「要用它，电脑上得先跑起 `tools/qp-gate`」那一节。

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
| 网关 | 电脑上跑 `tools/qp-gate`：Python 3 + 标准库，没有别的东西要装。不跑它手机连不上（原因见上面那一节） |

## 状态

个人项目，能日常自用，尚未发布到应用市场。已知缺口列在
[docs/08-testing.md](docs/08-testing.md#6-已知仍未覆盖) 与
[CHANGELOG.md](CHANGELOG.md)，还没上真机跑过的项集中在
[docs/08-testing.md](docs/08-testing.md#7-待实机验证)。安全相关的取舍全部写在 [SECURITY.md](SECURITY.md)，
不藏。

## 许可

Apache License 2.0，见 [LICENSE](LICENSE)。
应用图标为本项目独立设计，与任何第三方商标无关联；请勿作为 QwenPaw 桌面版的官方移动端理解。
