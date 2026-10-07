# 发布：从开发树到 GitHub

这篇讲**怎么把这一轮改动发出去**，不是"怎么装来用"（那看
[10](10-deploy-and-use.md)）。里面每一条都是踩过一次才写下来的，所以顺序照做，
别自行简化 —— 少跑一步的代价通常是把一个不该出去的文件发出去。

## 1. 有两棵树，只有一棵能对外

| | 是什么 | 能不能直接推 |
| --- | --- | --- |
| 开发树 | 桌面端整仓的一个子目录 `QwenPawMobile/`，本地还是个浅历史克隆 | **不能**：推它会把桌面端代码一起搬进一个名字是 Mobile 的仓库 |
| 发布树 | `https://github.com/errboy/QwenPawMobile` 的 `main` | 能，但只在用户点名时推 |

发布树在本机是同一个仓库的 linked worktree（`git worktree list` 列两条），分支叫
`qpmobile-final`，与开发树的 `main` **共用 object 库、历史互不相干**。因此在发布树里
`git branch` 看见的 `main` 就是开发树当前分支，不是"发布树里残留的 main"，删它等于删
开发树的头。判据一律用 `git merge-base --is-ancestor <分支> qpmobile-final`。

发布树没有 `external-signing-config.json`，所以在这里 `devecocli build` 出的必然是
unsigned hap —— 这正好是"陌生人克隆之后能否构建"的验证台。别为了出签名包把证书拷过去。

## 2. 两棵树的目录形状不一样

发布树的根就是应用本体，而开发树把它包在一个子目录里，所以**镜像时要做一次上提**，
并且有两条源路径：

| 开发树 | 发布树 |
| --- | --- |
| `QwenPawMobile/**` | `/**`（上提一级） |
| `tools/**`（**在开发树根，是 `QwenPawMobile/` 的兄弟**） | `tools/**` |
| `QwenPawMobile/AGENTS.md`（被外层 `.gitignore:110` 挡住，**不被跟踪**） | `AGENTS.md`（**被跟踪**） |
| `QwenPawMobile/.github/**` | `.github/**` |

漏掉第二行最典型的后果就是发出去的报告里让人跑的 `tools/doc_line_check.py` 根本不在仓库里。
第三行是镜像时最容易漏的那个文件，见 §3 末尾。

## 3. 同步按内容算，不按提交数估

发布树与开发树的提交粒度早就不是 1:1（一次同步可能只落 1 个提交，覆盖开发树 5 个提交
的内容），所以"落后多少"要看内容：

1. 导出时就把私有清单挡在命令里（别等拷的时候靠眼睛）：

   ```bash
   git -C <开发树> archive --format=tar main QwenPawMobile tools \
     ":(exclude)QwenPawMobile/maintainer" \
     ":(exclude)QwenPawMobile/_legacy_reference" \
     ":(exclude)QwenPawMobile/scratch" \
     ":(exclude,glob)QwenPawMobile/AppScope/backup_*_icons/**" \
     ":(exclude)tools/qp-gate/TODO.md" | tar -x -C <临时目录>
   ```

   临时目录放两棵树之外。导出来是带 `QwenPawMobile/` 一层的形状，按上表把它拉平再拷。
   **两种排除写法不能混**：`:(exclude)` 是**前缀**匹配，写目录名就能带走整棵子树；
   带通配符的那种要写成 `:(exclude,glob)<那个目录>/**` —— glob 的 `*` 不跨 `/`，
   少了结尾的 `/**` 就匹配不到目录里的文件，目录照样跟着出去（这句是实测出来的）。
   拷完对着临时目录数一遍，必须是 0 行：

   ```bash
   find <临时目录> \( -path "*maintainer*" -o -path "*_legacy_reference*" \
     -o -name "TODO.md" -o -path "*backup_*icons*" \) -print
   ```

2. 拷进发布树（私有清单已经在第 1 步被命令挡住了，这里不再手工挑）。
3. 核对：`diff -r --brief --strip-trailing-cr <临时目录> <发布树>`。**必须带
   `--strip-trailing-cr`**，否则 CRLF/LF 差异会把一半文件报成"不同"，`git status`
   也跟着给出几十个假 M；拿 `git hash-object` 对 HEAD 里的 blob 一比就知道是换行在骗人。
4. 反过来定位"发布树等于开发树哪个提交"：对差异文件跑 `git hash-object`，再到开发树
   `git log --find-object=<sha> -- <路径>`。凭 `git log` 数提交会误判成落后几十个。

| 私有清单（不进发布树） | 为什么 | archive 会不会自动带出去 |
| --- | --- | --- |
| `external-signing-config.json`、`local.properties`、`tools/qp-gate/gate.json` | 签名材料、本机 SDK 路径、含口令的本机网关配置 | **不会**，它们不被跟踪 |
| `_legacy_reference/`、`AppScope/backup_*_icons/`、`tools/qp-gate/TODO.md`、两个 `scratch/`、`maintainer/` | 旧实现、图标备份、未定稿待办、验证脚本与日志摘录、只给维护者看的验证台账与开发日志细节 | **会**，它们**被跟踪着**，必须用第 1 步的 `:(exclude)` 点名挡掉 |

这一行的区别不是吹毛求疵：`git archive` 从 HEAD 导出，`.gitignore` 对它没有任何约束力，
所以"ignore 里有它"≠"它不会跟着出去"。判断事实只有一条命令：`git ls-files <路径>`。
上面第二行由第 1 步那条 `archive … :(exclude)…` 命令挡住；发布树 `.gitignore` 里也要同步点名，
让"整目录复制过来"这条路下次同样走不通。新增私有目录时**两处都要加**（命令与 `.gitignore`），
只加一处迟早有一次带出去。

临时写的验证清单、抓下来的布局 dump 之类，只要从没被 `git add` 过就安全（`QwenPawMobile/scratch/`
现在既被 `/scratch` 忽略、又有两个早于该规则的历史文件被跟踪 —— 新文件不会自己进仓库，
但别顺手 `git add -f`）。

**最容易漏的一个文件是 `AGENTS.md`。** 它在开发树被外层 `.gitignore` 挡住、不被跟踪，所以
`git archive` 不会带它，`git status` 也永远不会报它；照 status 列出的单子拷贝，发布树就会
停在旧内容（真发生过：开发树的自检项数已改，发布树还写着上一个数）。它要从工作目录直接拷，
镜像清单里显式加一条，事后逐文件 `cmp`。注意 `docs/01-getting-started.md` 在两棵树里换行符
不同，**按内容比，别按字节比**。

## 4. 闸门要在发布树再跑一遍，不是只跑开发树

| 命令（在发布树裸跑） | 期望 |
| --- | --- |
| `devecocli check arkts` | 0 error |
| `devecocli check lint` | 0 error（存量 warning 不算回归） |
| `devecocli build --build-mode debug` | 成功，产物 `entry-default-unsigned.hap` |
| `python tools/qp-gate/selftest.py` | 全过（项数随功能涨，别照抄旧文档里的数字） |
| `python tools/doc_line_check.py` | 0 problems |

最后一条换树跑的理由很具体：它检查 markdown 相对链接，而"文档指向一个故意不发布的
私有文件"这类断链**在开发树里是好的**，只有发布树才 404（`tools/qp-gate/README.md`
曾链向 `TODO.md`，就是这么抓出来的）。凡是文档里"命令/路径"形态的句子，都要在发布树
实地跑一遍，别只靠肉眼看。

`doc_line_check.py` 管代码行引用、相对链接、`Copy.fill*` 占位符数量三件事，**不管散文
漂移**：同一条规则在 `04`/`07`/`09`/`11` 各写了一遍，哪天口径分叉它不会响，改的时候
要手工对齐。行引用它按"落在所属函数范围内"来容忍，所以过了不代表行号是准的。

## 5. 版本号

- 三处必须一致：`AppScope/app.json5`（`versionCode` + `versionName`）、
  `entry/oh-package.json5`、`CHANGELOG.md` 的 `## [x.y.z] - <日期>`。
- **打 tag 前先 `grep '^## \[' CHANGELOG.md`。** 不发版只进 `main` 的提交，`Unreleased`
  就该留着别动。
- 从产物反证，别只信清单：`unzip -p <hap> module.json` 里读到的
  `versionName` / `versionCode` 才算数。
- 装了包之后**不要**拿 `versionCode` 当"跑的是不是新代码"的判据，认
  `bm dump -n <bundleName>` 的 `updateTime`（见 [03](03-run-on-device.md)）。
- 版本号不是接口稳定承诺，这个口径写在 `CHANGELOG.md` 头部，发新版时照它解释：
  第一个号指第一次公开开源，往后每个号指一轮功能与修复的收口。

## 6. 推法：快进还是 MR

- **推前先确认是快进**：`git ls-remote <url> refs/heads/main`，远端 SHA 必须等于本地
  HEAD 的父亲。不是的话改走 MR，**不要用 `--force`**。
- **走 MR**：新能力、契约变更、任何对外有争议面的改动。先推分支
  （`git push <url> <分支>:<分支>`，风险远低于推 main），PR 正文照
  `.github/PULL_REQUEST_TEMPLATE.md` 的六个固定段落填（改了什么 / 为什么 / 验证 /
  闸门 / 影响面 / 没做的）。「验证」里写清**真实端还是桩**与设备形态，「没做的」如实写。
  合并用 **merge 而不是 squash**：这样 `main^{tree}` 等于本地跑过闸门那份 tree，
  发出去的字节就是验过的字节。
- **走快进**：纯收口、工具、文档（`chore(release)` 那一类）。
- **403 不是凭据坏了**。`origin` 是组织仓库，认证通过但拒绝写入；别去折腾 credential
  helper，也不要反复重试同一条 push。
- commit 与 push 是两件事。本地提交就是安全备份，别把"没推上去"说成"没保存"。

## 7. 三件事必须本人在场，委托不解除

1. **建 PR**。`create_pull_request` 每次只弹一张交互表单，工具结果自己写着"PR 尚未
   创建，等用户点 Submit"。判断 PR 存不存在只有列 PR 的读接口说了算，别把"表单弹过了"
   当成"建好了"；表单连着不生效时先自证网络无责（`git ls-remote`、打 API 与站点的
   HTTP 码、一次只读 MCP 调用），再把比较页链接
   `https://github.com/errboy/QwenPawMobile/compare/main...<分支>?expand=1` 摆出来，
   正文写成两棵树之外的本地文件让他整份复制。用系统浏览器打开该链接，别用
   `cmd /c start` —— git-bash 会在 `?` 与 `&` 处把命令折断。
2. **建 Release**。GitHub 侧只有 release 的读接口，本机也没装 `gh`，创建只能在网页。
   Release 的 assets 为空是**有意的**：签名材料不进仓库，发布树上只能出 unsigned hap，
   挂上去既装不了也没意义。
3. **真机操作与执行清理**。系统确认框、审批按钮、清理的二次确认都归人点，
   见 [11](11-agent-playbook.md)。

## 8. 合入之后

1. 本地 `qpmobile-final` 快进到远端那个 merge commit。
2. 删远端临时分支要用户点名；`git push <url> --delete <分支>`，删完确认只剩 `main`。
3. 一次性导出目录在两棵树之外，用完删。
4. 泄露扫描**只扫新增行**：`git diff -U0 <范围> | grep '^+'` 再比禁值清单（局域网 IP、
   设备调试地址、后端端口、任何个人主目录路径、任何口令）。输出别接 `head`，否则会误以为
   没命中。`.gitignore` 里有它 ≠ 它没被跟踪，事实看 `git ls-files`。设备型号与错误码
   **不算**泄露，别顺手删掉诊断信息。
5. `LICENSE` 末尾那行版权占位由仓库所有者自己署名，任何一轮都不代填。

## 9. 一轮发布的顺序

1. 开发树：闸门全绿 + 至少一个设备形态实测 + `CHANGELOG.md` 的 Unreleased 有行 → commit。
2. 按 §3 同步到发布树，按 §4 在发布树重跑闸门。
3. 按 §8 第 4 条跑泄露扫描，两棵树的新增行都扫。
4. 用户点名 → 按 §6 推分支或快进。
5. 要发新版本才走 §5（版本号三处改齐 + grep 确认没重复），然后 annotated tag
   （`git -c user.name=… -c user.email=… tag -a`）→ 推 tag → 网页建 Release（§7）。
6. 回来快进 `qpmobile-final`，清临时目录。

## 为什么这篇不写在 CONTRIBUTING 里

`CONTRIBUTING.md` 面向从 fork 提 PR 的外部贡献者：他们没有开发树，不碰镜像、tag 和
Release。这一篇的前提是手里同时有两棵树，它是维护者的手册。
