# 09 · 排障

先分清是哪一层：`手机上没反应` 可能是 App、网关、桌面端、网络四者之一。
按下面顺序二分，比读代码快。

## 1. 构建期

| 现象 | 原因 | 处理 |
| --- | --- | --- |
| `hvigor ERROR 00303116: storePassword ... less than 32` | 签名占位是空串而 `external-signing-config.json` 不存在 | 现版 `hvigorfile.ts` 已修：没材料就丢掉 `signingConfigs` 出 unsigned hap。若仍出现，说明 `build-profile.json5` 被改回带空口令的配置 |
| 构建报非法资源路径 / 把某目录当成资源 | 备份图片放进了 `resources/**` 子目录 | 素材备份必须放在 `resources` **之外**（hvigor 资源扫描器不接受资源目录里的子目录） |
| 只改了 `.ets` 但 `--apply` 不生效 | 改动含资源/`module.json5`/`@State` 装饰器本身 | 全量 `devecocli run`，别用 `--apply`/`--skip-build` |
| ArkTS 检查报错但 IDE 里"看着没问题" | ArkTS 比 TS 严：禁 `any`、对象字面量需形状 | 按报错行号改；`devecocli check arkts --fix` 先补高置信度问题 |

## 2. 装机与启动

| 现象 | 原因 | 处理 |
| --- | --- | --- |
| `Error Code:10106102 ... device screen is locked` | 包已装上，启动被锁屏挡住 | 唤醒 + 上滑解锁：见 [03](03-run-on-device.md) §2 |
| 装机失败、提示签名不一致 | 换过证书 | `devecocli run --device <序列号> --uninstall` |
| `Smoke: FAIL_BLANK` | 首屏白 | 看输出里 `screenshot:` 指向的图，再 `devecocli log --crash` |
| 一条 INFO 日志都没有 | user 版系统裁 INFO | `devecocli log --level W --bundle-name com.liaocaosix.qwenpawmobile` |
| 命令报"多设备" | 同时连了真机和模拟器 | 所有设备类命令显式 `--device <序列号>` |

## 3. 连接（最常见的一层）

**先确定测的是谁**：真桌面端还是桩。mock 通过不代表联调通过。

| 现象 | 最可能的原因 | 怎么确认 |
| --- | --- | --- |
| 扫描列表空的 | 网关/桌面端没在跑；端口不对（扫描默认 8088，qp-gate 是 61700）；手机不在同网段 | 电脑浏览器打开 `http://127.0.0.1:<端口>/api/auth/status`，有 JSON 说明后端活着 |
| 扫描到的地址连不上 | 扫的是网关的另一个口，或防火墙拦了 61700 | `python tools/qp-gate/qp_gate.py --init` 会放行防火墙；手工核对 Windows 防火墙入站规则 |
| 模拟器怎么都连不上宿主 | 用了 `127.0.0.1` 或宿主机局域网 IP | 模拟器访问宿主用 `10.0.2.2`；且**不要指望局域网扫描**——它扫的是 `10.0.2.x` |
| 登录后立刻 401 | 令牌被网关拒（口令换过、`allow_cidrs` 变了） | 手机没有 401 自动重登（`core/Failure.ets:44`），重新登录一次；仍失败就 `python tools/qp-gate/selftest.py` 验网关 |
| 网关启动报端口被占 | 已经有一个实例在跑 | 先看进程，不要改端口——两个网关会抢上游发现。`qp-gate` 拒绝回环地址接入，这是设计 |
| 流式回复卡住不结束 | 中间有代理改了/吞了 `Connection` 头，或做了响应缓冲 | qp-gate 只在 TCP 层逐字节搬运并改写 `Connection: close`；换成别的转发方式就要自己验 SSE 分帧 |
| 图片能看，视频放不出来 | `Video` 组件加不上 `Authorization` 头 | 已知边界（`tools/qp-gate/README.md`）。要么该路径可匿名访问，要么接受看不了 |
| 上传失败 | 超过 `GET /api/settings/upload-limit` | 手机端按这个上限先拦，别改服务端配置 |
| 手机端什么都是 403 | 后端开了鉴权但手机走的是"跳过登录"分支 | `GET /api/auth/status` 必须回 `enabled: true`；qp-gate 自演这一面正是为此 |

## 4. 布局

| 现象 | 原因 |
| --- | --- |
| 平板/折叠屏上正文横贯整屏 | 没走 `AppMeasure.text/panel`，直接写了 `100%`（见 [06](06-responsive-devices.md) §3） |
| 冷启动闪一下宽度 | 首帧没预发布分桶，`Breakpoint.publish()` 太晚 |
| 横屏没变化 | 手机模拟器 `emulator rotate` 是空操作；真机请物理转或用大屏形态验 |

## 5. Windows 上的脚本

- `.bat` 必须是 **CRLF + 纯 ASCII**。用带 LF 或中文的工具写 `.bat`，`cmd` 会把整段炸掉（本机 ACP=936）。
- `.ps1` 里带中文必须存成 **UTF-8 with BOM**，否则 PowerShell 读成乱码。
- Python 不需要装任何第三方包：`qp_gate.py` 与 `selftest.py` 只用标准库。

## 6. 还是不行

按 [../.github/ISSUE_TEMPLATE](../.github/ISSUE_TEMPLATE) 里的模板提 issue，务必带：
设备与系统版本、断点桶、`devecocli log --level W` 片段、是真实端还是桩、
以及"这台机器上 `GET /api/auth/status` 的原始返回"。
