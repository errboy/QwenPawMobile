# 04 · 与桌面端协同

这一篇是全项目最重要的一篇：手机能不能连上，几乎取决于桌面端**绑在哪个地址**上。

## 1. 现状：桌面端默认只听回环

QwenPaw 桌面版由 Tauri 拉起本地 Python 后端，监听地址硬编码 `127.0.0.1`，端口是随机的，
写在 `~/.qwenpaw/config.json` 的 `last_api.port`。
也就是说：**同一台机器上的浏览器能访问，局域网里的手机访问不到**。

Provider 凭据在 `~/.qwenpaw.secret`，本工程不读它、也不该读它。

## 2. 三条路，只推荐第一条

| 方案 | 桌面端改动 | 鉴权 | 结论 |
| --- | --- | --- | --- |
| `tools/qp-gate` 守门代理 | 无 | 由网关自演 | **推荐** |
| 桌面端 CLI `--host 0.0.0.0` | 换启动方式 | 取决于桌面端配置 | 谨慎 |
| `netsh interface portproxy` | 无 | 无 | **不要用** |

### 2.1 qp-gate（推荐）

`tools/qp-gate/qp_gate.py` 是单文件 Python，听 `0.0.0.0:61700`，把请求转到回环后端。
它的存在理由（`tools/qp-gate/README.md` 有完整推导，这里只说结论）：

后端按**客户端 IP** 免检，`security.allow_no_auth_hosts` 默认包含回环。
经过代理转发后，后端看到的源地址永远是 `127.0.0.1`——**后端那一层鉴权在这个拓扑里根本不参与**。
所以"让桌面端开鉴权、代理只做透明转发"是假安全，代理必须自己把鉴权面扛下来：
`/api/auth/*` 由网关本地应答，其余 `/api/*` 一律要求带令牌才转发。

也正因为如此，**`netsh portproxy` 不能用**：它同样把来源伪装成回环，等于把鉴权一起绕掉。

上手一条命令就够了（Windows，工程根目录下）。`start.bat` 自己找可用的 Python 3，
参数决定它干什么：

```bat
tools\qp-gate\start.bat                 :: 启动；gate.json 不存在时先引导设账号口令
tools\qp-gate\start.bat stop            :: 停掉正在监听的那一个（只停它认得出是自己的进程）
tools\qp-gate\start.bat config          :: 改配置：账号口令（可跳过）、两个端口、放行网段
tools\qp-gate\start.bat password        :: 只换手机端登录的用户名与口令
tools\qp-gate\start.bat show            :: 打印当前生效配置，连每一项的含义一起打
tools\qp-gate\start.bat discover        :: 只看探测到的上游端口
tools\qp-gate\start.bat check           :: 跑一遍自检，自带桩上游，不碰真实配置
tools\qp-gate\start.bat firewall        :: 单独补一次入站放行（弹 UAC）
tools\qp-gate\start.bat firewall-remove :: 删掉本工具加的防火墙规则（网关停了它还在）
tools\qp-gate\start.bat help            :: 列出全部命令
```

```bat
python tools\qp-gate\qp_gate.py --init    :: 首启：设账号口令 + 放行防火墙
python tools\qp-gate\qp_gate.py --edit    :: 日常改配置（= start.bat config）
python tools\qp-gate\qp_gate.py           :: 启动
python tools\qp-gate\qp_gate.py --stop    :: 停（只停命令行里带 qp_gate 的那个进程）
python tools\qp-gate\selftest.py          :: 跑一遍自检，自带桩上游，不碰真实配置
```

`stop` 去系统的连接表里找正在 `LISTENING` 配置端口的那个进程，**只停命令行里带着
`qp_gate` 的那一个**，杀完回头再看一次连接表才敢说停了；端口上坐着别的服务时它拒绝动手，
只把那个 PID 和它的命令行打给你看，然后返回失败。**关掉窗口不等于停了进程**——它被脚本
或后台拉起来时根本没有窗口，这条命令管的就是那一种。停止不作废手机上已签发的令牌，
也不删防火墙规则。

日常改东西只碰 `start.bat config`：每一项都把当前值当默认，一路回车等于什么都没改，
完事立刻把生效值打回来。**更高级的字段（令牌有效期、连接上限、限流窗口、监听地址）
手改 `gate.json`，改完 `start.bat show` 复核。**

**防火墙那条入站规则是永久的**：`--init` / `config` 换端口时加的规则（`name=qp-gate`，
只放行那**一个**端口）不随网关停止、不随重启消失——**关掉网关窗口（Ctrl+C）也不会删它**。
不想再让局域网进这台机器时，明确地删掉它：

```bat
tools\qp-gate\start.bat firewall-remove
```

它按规则名删，而这个名字只有本工具在用，所以一次会带走**这个名下所有端口**的规则
（换过端口的话，旧端口那条也一起没了）——想留着现在这个口只清历史遗留，就别用它，
在管理员命令行里按端口删：`netsh advfirewall firewall delete rule name=qp-gate protocol=tcp localport=<旧端口>`。
加与删都会**回头看规则状态**再报成败（拉起提权进程返回 0 不等于放行成功）。

`--edit` 与 `--init` 有一条要紧的区别：**改端口配置不会作废已签发的令牌**，而 `--init --force`
会重新生成 `token_secret`，把手机端全部踢下线重来。所以换口令用 `start.bat password`、
改配置用 `start.bat config`，**别拿 `--init --force` 当"改配置"用**。这两个入口的口令都只在
交互提示里输入，不会进命令行、也就不会留在进程列表和 shell 历史里。

手机端登录页把扫描端口填 `61700`，扫出来的那台机器就是它，账号口令填 `--init` 里设的。

**凭据归属**：`gate.json` 里的账号口令由使用者在本机自己设，仓库不带、也不该带。
`gate.example.json` 只是字段样例。上游端口自动发现，桌面端重启换端口不用改配置。

### 2.2 让桌面端直接听 0.0.0.0

桌面版（安装版是 PyInstaller 编译包）改源码无效，只能换成 CLI 启动并加 `--host 0.0.0.0`。
代价要清楚知道：

- `/api/console/*` 这条线**默认无鉴权**，其中包含让 agent 执行命令的能力。绑到 0.0.0.0
  就是把这个能力交给同网段所有设备。
- 升级安装版会覆盖任何本地改动，所以这条路不适合长期。
- 只在你自己信得过的网络里、并且用完就关的前提下考虑。

需要给外部 agent 做端到端联调时，推荐另起一个隔离实例并显式指定运行时
（`--runtime-provider openai-env`），不要去改桌面端自身的配置。

### 2.3 已安装桌面版 + 不想动它

就用 2.1。qp-gate 只依赖公开的 HTTP 接口，桌面端升级不影响它。

## 3. 会话是双向的

手机和桌面端操作同一个 chat 时：

- 桌面端发起的新一轮，手机**不需要退出重进**就能看到对端消息。链路是
  10 秒一次的统一轮询（`polling/GlobalPoller.ets`）+ 进入会话时的追帧
  （`state/ChatStore.ets:408 catchUpTurn`）。
- 手机上点发送后如果对方正在跑，本端会 attach 到在途的 run 并回放缓冲帧
  （请求体里 `reconnect: true`，见 [07](07-server-contract.md)）。
- 断线重连按 2/4/8 秒退避，最多 3 次（`stream/RunController.ets:26,324`）。

## 4. 审批：卡片只在手机上由人点

桌面端把工具执行挂起后，手机主页/聊天页出现待审批卡片（`ui/chat/ApprovalCard.ets`），
只有人点了"同意"才会 POST `/api/approval/approve`，批准范围取最小权限。
"代码里不许留自动批准、测试时必须有人在场"这条为什么是硬约束，写在
[SECURITY.md](../SECURITY.md) §2；agent 那侧的操作口径在 [11](11-agent-playbook.md)。

## 5. 附件与预览

上传走 `POST /api/console/upload`（multipart，逐块，不把大文件聚合进内存）。
上限从 `GET /api/settings/upload-limit` 读。
预览走 `/api/files/preview`：普通图片可以带 Authorization 头加载；
`Video` 组件加不上请求头，这条路径依赖上游自身可访问性——在只走 qp-gate 的拓扑里，
视频预览可能加载不了，这是已知边界（`tools/qp-gate/README.md` 末尾也记了）。
