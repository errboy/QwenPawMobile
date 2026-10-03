# QwenPawMobile

QwenPaw 桌面端的鸿蒙（HarmonyOS NEXT）遥控器：在局域网里找到本机运行的 QwenPaw 后端，
收发会话、上传附件、查看工具调用，并在桌面端挂起审批时**由人按下同意/拒绝**。

> QwenPaw 的模型、工具执行与历史都在桌面端那一侧。这个 App 不内嵌 agent 运行时，
> 它是一个严格建立在桌面端公开 HTTP 接口之上的客户端。

## 它能做什么

- 登录：不敲 IP。扫本机所在 /24，逐个地址问一次 `/api/auth/status`，只列真正会说
  QwenPaw 协议的机器。
- 会话：SSE 流式渲染（含 Markdown、思考块、工具调用与输出）、停止与重发、
  图片/视频/语音/文件附件、`/` 快捷指令补全、loop 模式与模型槽位选择。
- 播放：收到的图片点按全屏，视频与语音在气泡里直接播，自己发出去的 clip 也能回放。
  字节带 Authorization 头取回后落进应用沙箱，**口令不出现在任何 URL 里**。
- 本机存储：主页一行显示媒体缓存占用与未发送草稿条数，一键清理只删手机上的副本；
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
tools/qp-gate/                守门代理 + 40 项自检
docs/                         下面的文档
```

## 文档

| 文档 | 一句话 |
| --- | --- |
| [docs/01-getting-started.md](docs/01-getting-started.md) | 是什么、需要什么、20 分钟跑起来 |
| [docs/02-build-and-sign.md](docs/02-build-and-sign.md) | **编译不需要证书**；签名材料为什么不在仓库里 |
| [docs/03-run-on-device.md](docs/03-run-on-device.md) | 真机/模拟器装机、锁屏、网络口径、UI 检查 |
| [docs/04-desktop-cooperation.md](docs/04-desktop-cooperation.md) | 与桌面端协同（**最重要的一篇**） |
| [docs/05-architecture.md](docs/05-architecture.md) | 分层、四条硬规则、一轮回复的完整路径 |
| [docs/06-responsive-devices.md](docs/06-responsive-devices.md) | 断点体系与折叠形态实测数据 |
| [docs/07-server-contract.md](docs/07-server-contract.md) | 对接 QwenPaw v2.2.2-beta.4 的端点与 SSE 语义 |
| [docs/08-testing.md](docs/08-testing.md) | 自动化闸门、手工回归清单、想加测试从哪入手 |
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
[CHANGELOG.md](CHANGELOG.md)。安全相关的取舍全部写在 [SECURITY.md](SECURITY.md)，
不藏。

## 许可

Apache License 2.0，见 [LICENSE](LICENSE)。
应用图标为本项目独立设计，与任何第三方商标无关联；请勿作为 QwenPaw 桌面版的官方移动端理解。
