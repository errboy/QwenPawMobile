# 01 · 上手

面向两类读者：想跑起来的人，和想改代码的 agent。

## QwenPawMobile 是什么

鸿蒙（HarmonyOS NEXT / API 20+）上的 QwenPaw 桌面端遥控器。它**不是**一个独立的
agent 运行时——模型、工具执行、会话历史全部在本机桌面端那一侧，手机只做三件事：

1. 在局域网里找到桌面端的 HTTP 服务并登录；
2. 收发会话（SSE 流式 + 附件上传 + 停止/重发），把桌面端已经打开的会话渲染出来；
3. 把桌面端攒出来的**待审批项**呈现在手机上，由人点"同意/拒绝"。

第 3 点是有意为之的边界：审批永远由人点，代码里没有任何自动批准路径。

手机不写桌面端的全局配置。`/workspace/running-config`、`/settings/upload-limit`
这些端点在本工程里**只读**（`core/Wire.ets:124-126` 的注释记录了原因：
PUT 是整文档替换，误点一次就把桌面端配置改写了）。

## 你需要什么

| 场景 | 最少准备 |
| --- | --- |
| 只想编译看看 | DevEco Studio 6.x + API 20 SDK。**不需要账号、不需要证书**，见 [02](02-build-and-sign.md) |
| 想装到真机 | 上面 + 华为开发者账号（自动签名）+ 一根数据线 |
| 想连上桌面端 | 上面 + 本机装着 QwenPaw 桌面版；手机和电脑在同一局域网 |
| 桌面端只绑 127.0.0.1（默认就是） | 再加 `tools/qp-gate`，见 [04](04-desktop-cooperation.md) |

## 20 分钟路径

```bash
git clone https://github.com/errboy/QwenPawMobile.git
```

在克隆出来的工程根目录里依次执行（下面假设工作目录已经是工程根）：

```bash
devecocli check arkts      # 语法闸门，秒级
devecocli build            # 无证书也能过，产出 unsigned hap
devecocli auth login       # 只有要装机时才需要
devecocli signature generate
devecocli device list      # 拿到设备序列号
devecocli run --device <序列号>
```

装好后第一次进 App 会看到登录页，它不问你 IP，而是**扫本网段**：
每个地址发一次 `GET /api/auth/status`，只有会用 QwenPaw 的话回答的才列出来
（`net/LanScan.ets:1-10` 记录了为什么这么做——让人在手机上敲 `192.168.x.x:端口`
是最糟的首次体验，而敲错一位和"服务端没开"长得一模一样）。

扫描默认端口 `61700`，也就是 qp-gate 的端口，用手机时不用再改。只有绕过网关
直连桌面端时才填 `8088`。

## 仓库结构

```
AppScope/            应用级配置与资源（分层图标的 foreground 在这里生效）
entry/src/main/ets/  ArkTS 源码，分包见 docs/05-architecture.md
tools/qp-gate/       局域网守门代理（单文件 Python + 自检）
docs/                本套文档
```

## 下一步

- **不想读实现，只想装上用** → [10-deploy-and-use.md](10-deploy-and-use.md)（含装机后每个功能怎么用）
- **让 AI 助手替你跑这套流程** → [11-agent-playbook.md](11-agent-playbook.md)
- 构建与签名细节 → [02-build-and-sign.md](02-build-and-sign.md)
- 装到真机/模拟器 → [03-run-on-device.md](03-run-on-device.md)
- 和桌面端打通 → [04-desktop-cooperation.md](04-desktop-cooperation.md)
- 安全须知（**改代码前请先读**）→ [../SECURITY.md](../SECURITY.md)
