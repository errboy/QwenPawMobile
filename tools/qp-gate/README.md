# qp-gate — QwenPaw 局域网守门代理

让局域网里的手机连上**只绑回环**的 QwenPaw 桌面端后端。**桌面端零改动、手机端零改动**：
后端继续听 `127.0.0.1:<随机端口>`，本工具听 `0.0.0.0:61700`，中间这一层由它守。

## 为什么需要它

QwenPaw 桌面版（Tauri GUI 启动）硬编码只绑 `127.0.0.1`，手机直连不到。改 `entry.py`
的办法在**安装版**上无效——安装版是 PyInstaller 编译包，仓库源码改了不影响它；而且
桌面端一升级，改动就没了。所以把能力放在外面这个独立小工具里：它只依赖公开的
HTTP 接口，桌面端升级不会让它失效。

## 为什么门禁必须做在这里（重要）

转发到后端时源地址是 `127.0.0.1`，而 QwenPaw 的鉴权按**客户端 IP** 免检
（`security.allow_no_auth_hosts` 默认含回环）。也就是说在这个拓扑下后端那一层鉴权
**根本不参与**。"让桌面端开鉴权 + 代理只做转发"是假安全：代理自己就是那个免检的回环
客户端。所以本工具亲自实现鉴权面，其余路由一律带令牌才转发。

同理，**别用 `netsh interface portproxy`** 做转发：它会把来源伪装成 `127.0.0.1`，
等于把鉴权也一起绕掉。

## 快速开始（Windows）

`start.bat` 是唯一入口，它自己会找一个可用的 Python 3：

```bat
start.bat                  : 启动。gate.json 不存在时先引导设置账号与口令
start.bat password         : 换手机端登录的用户名与口令
start.bat discover         : 只看探测到的上游端口，然后退出
start.bat check            : 跑 40 项自检（自带桩上游，不碰真实配置）
start.bat firewall         : 单独添加 Windows 入站放行（会弹 UAC）
start.bat firewall-remove  : 删掉本工具加的防火墙规则
start.bat help             : 列出上面的命令
```

换口令请走 `start.bat password`，**不要用 `--init --force`**：`--init` 会重新生成
`token_secret`，已签发的令牌全部作废，手机端就得重新登录。`--init` 遇到已有的
`gate.json` 默认拒绝覆盖，也是这个原因。

口令**只在提示符下输入**，从不作为命令行参数：参数会留在进程列表和 shell 历史里，
局域网上的这台机器不该冒这个险。

或手工（与上面的子命令等价）：

```bat
python qp_gate.py --init              :: 设置手机端登录用的用户名 + 口令，并放行防火墙
python qp_gate.py                     :: 启动
python qp_gate.py --discover          :: 只看探测到的上游端口
python qp_gate.py --set-password      :: 换口令（口令只走交互输入，不做命令行参数）
python qp_gate.py --remove-firewall   :: 删掉本工具加的防火墙规则
```

手机端：登录配置页把扫描端口填 `61700`，扫描后点选这台机器，用户名/口令填 `--init`
里设的那两个，登录。

## 它做了什么

| 路由 | 行为 |
|---|---|
| `GET /api/auth/status` | 本地应答 `{"enabled": true, "has_users": true}`。客户端 `AppStore.signIn` 见到 `enabled=false` 会**直接跳过登录**存空令牌，所以这一行是登录能发生的前提 |
| `POST /api/auth/login` | 校验 PBKDF2 口令，签发本工具自己的 HMAC 令牌 |
| `POST /api/auth/register`、`/update-profile`、`/revoke-*` | **403**，只留给本机桌面端用：局域网里任何访客都不该能在别人机器上建管理员 |
| 其他全部 `/api/*` | 必须带 `Authorization: Bearer <令牌>`，否则 401；带上了就原字节转发给回环后端 |

转发是 **TCP 层逐字节搬运**，只把请求头的 `Connection` 改成 `close`（否则上游会等下一个
请求、拿不到 EOF，普通请求会挂成超时）。因此 SSE 不断流、54MB 附件不聚合进内存、二进制
预览逐字节一致——这三条都有自检兜着。

上游端口是**自动发现**的：读 `~/.qwenpaw/config.json` 的 `last_api.port`，再兜底扫回环
监听端口，每个候选都用 `/api/auth/status` 的形状验证，所以桌面端重启换端口不用改配置。
（发现过程的探测在独立线程里并发跑，不会卡住正在推的 SSE。）

## 安全边界

- 口令只存 `pbkdf2_sha256$迭代数$盐$散列`（20 万次迭代），明文不落盘、不进命令行、不进日志。
- 令牌是本工具自签的 HMAC-SHA256，默认**永久**（`token_ttl_seconds: 0`）。手机端没有
  401 自动重登逻辑（`core/Failure.ets:44` 只把 401 归成 Unauthorized 报错），所以令牌
  一过期用户就只看到报错，别把这里改成有限值除非你打算顺手加手机端的续期。
- `gate.json` 权限 600，且已被 `.gitignore` 排除——**不要提交它**。
- `allow_cidrs` 默认 `["192.168.1.0/24"]`：不在名单里的地址连 `/api/auth/status` 都摸不到。
  留空表示不限网段（仍有口令限流），启动时会告警。
- 登录按 IP 限流：默认 60 秒内 8 次失败后返回 429，窗口内即使口令正确也拒。
- 畸形请求、绝对形式请求行、`CONNECT` 隧道、超长请求头都会被拒，且单个坏请求不会让守门
  进程退出。

## 自检

```bat
python selftest.py
```

自带桩上游，不依赖桌面端，也不碰你真实的 `~/.qwenpaw`。40 项覆盖：鉴权面接管与不泄漏、
口令错误/限流、伪造与过期令牌、无令牌转发、`Connection` 改写、X-Forwarded-For、SSE 分帧
到达时间、8MB 请求体字节一致、二进制逐字节一致、畸形与隧道拒绝、网段白名单、上游发现
（含乱协议端口不能把发现流程炸掉）。改完 `qp_gate.py` 必跑。

## 已知边界

- 只做 HTTP，不做 HTTPS。令牌在局域网里是明文传输的——和桌面端自己的 `/api/console/*`
  一样的暴露面。跨机敏感场景请自己上反代 TLS。
- 手机端 `Video` 组件播放 `/files/preview` 时加不上 Authorization 头，这条路径依赖上游
  自身的可访问性，与本工具无关。
- 只放行 `/api` 前缀之外的路由没有意义：客户端所有请求都走 `{server}/api{path}`，非
  `/api` 的路径同样要求令牌。
