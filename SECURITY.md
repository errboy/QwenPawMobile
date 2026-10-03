# Security Policy

这个 App 把"能执行工具的桌面端 agent"暴露在一块随身设备上，所以安全边界值得写清楚。
下面既写设计，也写**已知取舍和已知弱点**——不粉饰。

## 1. 报告漏洞

通过 GitHub 的 **Private vulnerability reporting**（仓库 Security 页 → Report a vulnerability），
不要开公开 issue。会尽量 7 天内回应。

## 2. 这个 App 的威胁模型

手机不是可信网络里的一台普通客户端：它能让桌面上的 agent 干活。因此三条原则是硬约束：

1. **审批必须有人在場**。`ui/chat/ApprovalCard.ets` 只在用户点击后发
   `/api/approval/approve`。代码里没有自动批准、没有超时默认同意、没有"记住这次都同意"。
   审批范围取最小权限（`ApprovalScope.EXACT`，`core/Wire.ets:145-149`：批准只记录字面目标）。
2. **手机不写桌面端全局配置**。`/workspace/running-config`、`/settings/upload-limit`
   等一律只读（`core/Wire.ets:106-108` 记录了原因）。
3. **网络权限最小**。只有 `INTERNET`、`GET_NETWORK_INFO`、`MICROPHONE`
   （`entry/src/main/module.json5:14-31`）。没有位置、通讯录、文件全量访问。

## 3. 已知取舍与弱点（请如实阅读）

### 3.1 登录口令在手机上明文存于应用私有 Preferences

`core/Prefs.ets:27` 的 `auth_password`，写入在 `:208 savePassword`。
它和 bearer 令牌、服务器地址、用户名存在同一个偏好文件（`qwenpaw_store`）里。

- 为什么这么做：免登录体验——重开 App 直接进主页，不必每次敲口令；
  而这个口令本来就是**局域网内一台自己家的机器**用的。
- 风险：能读到应用沙箱内 Preferences 的人（root 过的设备、备份提取）能同时拿到
  地址 + 账号 + 口令 + 令牌。
- 现状缓解：Preferences 是应用私有目录，其他应用读不到；系统备份是否包含它取决于设备与用户设置。
- **未做**：密钥库（HUKS）封装、生物识别解锁后回填、令牌失效即删口令。
  如果你的场景把这台手机借给他人、或设备可能离开你的控制，请**不要保存口令**
  （设置页留空，每次手输），或者干脆别用这个 App。

### 3.2 全程 HTTP，没有 TLS

局域网内明文传输，令牌可被同网段抓包者读取。这与桌面端自身的暴露面一致。
要跨机敏感场景请自行上反向代理 TLS。

### 3.3 令牌默认永不过期

qp-gate 签发的 HMAC 令牌 `token_ttl_seconds: 0`。理由是手机端**没有 401 自动重登**
（`core/Failure.ets:44` 只把 401 归成错误报给用户），令牌一过期用户只会看到报错。
代价：令牌泄露后长期有效。想换策略就同时给手机端加续期，别只改网关。

### 3.4 "把桌面端绑到 0.0.0.0"是危险的，文档不推荐

`/api/console/*` 默认无鉴权，其中包含让 agent 执行命令的能力。安装版桌面端硬编码只听
`127.0.0.1`，这是**保护**而不是缺陷。

反过来，为什么 qp-gate 必须自己扛鉴权：后端按**客户端 IP** 免检
（`security.allow_no_auth_hosts` 默认含回环），经代理转发后源地址永远是 `127.0.0.1`，
后端那一层鉴权在这个拓扑里**根本不参与**。所以：

- "桌面端开鉴权 + 代理只做透明转发"是假安全；
- `netsh interface portproxy` 不能用，它同样把来源伪装成回环，等于把鉴权一起绕掉；
- qp-gate 因此亲自应答 `/api/auth/*`（其余路由无令牌即 401），并把注册/改档案类端点固定回 403
  ——局域网里任何访客都不该能在别人机器上建管理员。

### 3.5 qp-gate 的边界

- 口令只存 `pbkdf2_sha256$迭代数$盐$散列`，20 万次迭代（`qp_gate.py:44`），明文不落盘、不进命令行、不进日志。
- `allow_cidrs` 默认只放行一个 /24；不在名单里的地址连 `/api/auth/status` 都摸不到。
- 登录按 IP 限流（默认 60 秒 8 次失败后 429，窗口内即使口令正确也拒）。
- 拒畸形请求、绝对形式请求行、`CONNECT` 隧道、超长请求头；单个坏请求不会让守门进程退出。
- `gate.json` 权限 600，且被 git 排除。
- 上游端口自动发现，因此不需要把桌面端端口写死在配置里。

### 3.6 播放过的 clip 会以明文字节留在应用沙箱

视频与语音为了能被 `Video`/`AVPlayer` 打开，必须先落进 `cacheDir/media`（应用私有目录，
按引用哈希命名）。这是这个 App 唯一在手机上留下的**内容**副本 —— 聊天转录仍在桌面端。
系统可以自行回收该目录，用户也可以随时在主页点「清理」立刻删掉，媒体缓存的字节数
就显示在那颗按钮旁边。取字节全程带 Authorization 头，**口令不进 URL、不进请求行、
不进代理日志**（v1 是拼进 URL 的，那才是真问题）。

## 4. 绝不进仓库的东西

| 路径 | 内容 |
| --- | --- |
| `tools/qp-gate/gate.json` | 真实账号口令散列 + 令牌密钥 |
| `QwenPawMobile/external-signing-config.json` | keystore 路径与口令 |
| `entry/src/main/resources/**` 里的任何证书/口令 | 永远不要往这里放 |
| `/screenshots/` | 真机截图，含真实会话内容与本机 IP |
| `local.properties`、`oh_modules/`、`.hvigor/`、`**/build` | 构建产物与本机路径 |

`build-profile.json5` 里的 `signingConfigs.material` 只留空串占位；真实材料由
`hvigorfile.ts` 的 `localSigning` 从上面那个被忽略的文件折叠进来。
**没有签名材料时构建仍然成功**，只产出 unsigned hap（不是失败），这样干净克隆也能验证编译。

提交前自查：

```bash
git log --all --name-only --oneline | grep -Ei "gate\.json|external-signing|\.p12|\.p7b|\.cer"
git grep -nEi "(storePassword|keyPassword)[\"']?\s*[:=]\s*[\"'][^\"']+" -- '*.json5' '*.json'
```

两条都该只匹配到空占位和文档里的说明文字。

## 5. 隐私

- 除用户填写的服务器地址外，App 不向任何第三方发起网络请求，没有埋点、没有广告 SDK。
- 本地存：服务器地址列表、账号、令牌、会话偏好、草稿、主题与布局开关，以及为播放而缓存的
  媒体字节（§3.6）。后者在主页一键可清。
- 登录页的局域网扫描只在用户主动点扫描时进行，探测包是标准的 `GET /api/auth/status`。
