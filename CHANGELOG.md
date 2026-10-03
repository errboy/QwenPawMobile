# Changelog

遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，版本号按
[SemVer](https://semver.org/lang/zh-CN/) 理解，但**尚未有稳定发布**：
`1.0.0` 指"第一次公开开源"，不指"功能冻结"。

## [Unreleased]

### Added
- 文档站：`docs/01`…`docs/09`，覆盖构建、签名、装机、桌面端协同、架构、
  断点体系、服务端契约、测试与排障。
- `SECURITY.md` / `CONTRIBUTING.md` / `AGENTS.md` 与 issue/PR 模板。

### Changed
- `hvigorfile.ts`：`external-signing-config.json` 不存在时**丢掉签名配置继续构建**，
  产出 unsigned hap。干净克隆现在能直接 `devecocli build` 通过；此前会卡在
  `hvigor 00303116`（空口令占位让 hvigor 仍尝试签名）。
- 仓库内的示例地址全部泛化（不再有真实局域网 IP 与真实设备名）。

### Known gaps
- `xs` 断点桶（分屏/悬浮窗挤窄）未做完整回归。
- 深色模式 + 系统大字号在 `lg`/`xl` 上未回归。
- `compatibleSdkVersion: 6.0.0(20)` 的下界只用更高版本设备验证过。
- 真折叠屏（非模拟器）对 `deviceTypes: ["phone","tablet"]` 的接受度未验证。
- 无 UI 自动化测试；`@ohos/hypium` 声明了但暂无用例文件。

## [1.0.0] - 2026-10-03

第一次作为独立仓库开源。此前是一次完整的 v1 → v2 重写：
组合根 + 单一数据源 + 唯一轮询器 + 帧归并器取代 v1 的模块级全局 client，
并把 v1 能力 1:1 平移过来。

### Added
- 登录页改为**局域网地址列表**：扫本机 /24，逐个探 `GET /api/auth/status`，
  只列会说 QwenPaw 协议的机器；另有独立的登录配置页（保存地址、扫描端口）。
- 会话能力：SSE 流式渲染、Markdown 气泡、思考块与工具调用/输出、停止与重发、
  图片/视频/音频/文件附件、语音录制发送、`/` 快捷指令补全、loop 模式选择器、
  模型槽位选择器、审批级别选择器。
- 审批卡片：`/api/approval/list` 出现在手机上，由人点同意/拒绝；批准按字面目标记录
  （最小权限）。
- 新建会话（`POST /api/chats`，id 由服务端发）、主页紧凑视图、主会话切换。
- 双向同步：桌面端发起的轮次在手机端**不需要退出重进**即可出现
  （10 秒统一轮询 + 进入会话时追帧）。
- 草稿保护：输入未发送的文本按会话持久化，返回拦截时静默保存（不弹确认框）。
- 响应式：`xs/sm/md/lg/xl` 五个窗口宽度桶 + 正文行宽封顶居中；手机允许横屏。
- 分层应用图标（独立设计的蛋壳 + Q 前景，橙色渐变背景）。
- `tools/qp-gate`：单文件 Python 守门代理，让只绑回环的桌面端安全暴露给局域网；
  自演鉴权面、PBKDF2 口令、HMAC 令牌、CIDR 白名单、登录限流、上游端口自动发现；
  配套 `selftest.py` 40 项自检（自带桩上游，不依赖桌面端）。

### Changed
- 签名口令从 `build-profile.json5` 外置到被 git 忽略的 `external-signing-config.json`，
  由 `hvigorfile.ts` 的 `localSigning` 折叠进构建配置。
- 日志统一走 `core/Log.ets`（user 版系统会裁 INFO 级日志）。
- 冷启动即在页面加载前发布宽度桶，消除平板首帧 sm→lg 闪跳。

### Fixed
- 逐 token 内容不再在块结束时重印（`delta=false` 帧是完整块文本，必须覆盖而非追加）。
- 重连不再抹掉排队中的气泡。
- 回复结束后流式光标残留。
- qp-gate 在中文 Windows 控制台（ACP=936）上启动失败。
- 应用图标前景素材自带假棋盘 alpha，导致透明无效。

## 历史说明

更早的提交是重写过程中的中间状态。本仓库的提交历史是从上游主仓库按路径切出来的，
因此**不含**桌面端（QwenPaw 主程序）的任何提交。
