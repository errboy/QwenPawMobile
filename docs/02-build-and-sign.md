# 02 · 从源码构建与签名

> 结论先行：**编译不需要任何账号或证书**，`devecocli build` 在干净克隆上就能过；
> 只有"装到真机"这一步需要签名材料，而签名材料是本机的、不进仓库。

## 1. 环境

| 需要 | 版本 | 说明 |
| --- | --- | --- |
| DevEco Studio | 6.x（实测 `26.0.0.621`） | 自带 hvigor、node、ohpm、SDK 管理器 |
| HarmonyOS SDK | API 20 及以上 | `build-profile.json5` 声明 `targetSdkVersion` / `compatibleSdkVersion` 均为 `6.0.0(20)` |
| DevEco CLI | 实测 `1.3.4`；**随 DevEco Studio 提供**，装了 IDE 再启用它 | 把 build / run / device / ui / log 串成一条命令，本文命令都以它为例 |

没有 CLI 也可以：全部动作用 DevEco Studio 的菜单（Build → Build Hap(s)）+ `hdc install` 完成。

**从哪儿搞到这些**：DevEco Studio 从华为官网下载（<https://cn.devecostudio.huawei.com/>，
历史版本在 <https://developer.huawei.com/consumer/cn/deveco-studio/archive/>），
装完在 Settings → OpenHarmony SDK Manager 里确认装了 **API 20** 的 SDK；
`devecocli` 是 DevEco Studio 带的命令行工具，装了 IDE 再按它的文档启用即可。
**QwenPaw 桌面版本文档不提供**——它是另一件事，本工程只当它是"你本机已经跑着的那个后端"。

## 2. 构建

```bash
devecocli build            # 产出 entry/build/default/outputs/default/*.hap
devecocli check arkts      # ArkTS 语法检查，比全量构建快，改完代码先跑它
devecocli check lint       # 代码规约（规则档位见 code-linter.json5）
```

首次构建时 hvigor 会自动执行依赖安装并生成 `oh_modules/`、`.hvigor/`、`entry/build/`，
这三者都在 `.gitignore` 里，不要提交。本工程**没有第三方运行时依赖**
（`oh-package.json5` 只有 `@ohos/hypium`、`@ohos/hamock` 两个测试期 devDependencies）。

## 3. 签名材料为什么不在仓库里

`build-profile.json5` 里的 `signingConfigs.material` 全是空串占位：

```json5
material: {
  certpath: '', keyAlias: '', keyPassword: '', profile: '',
  signAlg: 'SHA256withECDSA', storeFile: '', storePassword: '',
}
```

真实材料（keystore 绝对路径 + 口令）放在**同目录、被 git 忽略**的
`external-signing-config.json`，由 `hvigorfile.ts` 的 `localSigning` 插件在构建前
整体折叠进 build profile。这样做的原因有两条：

1. 口令一旦提交就是泄露；
2. DevEco 生成的口令是用**只存在于本机的密钥**加密的，提交出去对别人也毫无用处。

`devecocli signature generate` 会把真实配置**写回** `build-profile.json5`。
重新签名之后，请把 `signingConfigs` 挪回 `external-signing-config.json` 并还原占位，
不要让带口令的 `build-profile.json5` 进入提交。

**这个文件长什么样**（形状见仓库里的 `external-signing-config.example.json`；
`hvigorfile.ts` 用 `JSON.parse` 读它，所以必须是**严格 JSON**，不许注释、不许尾逗号）：

```json
{ "signingConfigs": [ { "name": "default", "type": "HarmonyOS",
    "material": { "certpath": "…", "keyAlias": "…", "keyPassword": "…",
                  "profile": "…", "signAlg": "SHA256withECDSA",
                  "storeFile": "…", "storePassword": "…" } } ] }
```

**别手写它**：正确的顺序是先跑一次 `devecocli signature generate`（它会把真值写进
`build-profile.json5`），把那一段 `signingConfigs` **整块复制**成
`external-signing-config.json`，再把 `build-profile.json5` 还原成空占位。
手写路径与口令基本不可能对——口令是用**只存在于本机的密钥**加密过的。

## 4. 取得签名材料

```bash
devecocli auth login                 # 登录华为开发者账号（浏览器 OAuth）
devecocli signature generate         # 生成本地 p12/csr + 云端证书 + 测试 profile
```

产物落在 `~/.ohos/config/`。或者在 DevEco Studio 里
File → Project Structure → Project → Signing Configs，勾选自动签名。

**换人用之前，先把 `AppScope/app.json5` 里的 `bundleName` 改成你自己的**
（形如 `com.<你的名字>.qwenpawmobile`：≥3 段、7–128 字符）。仓库里带的那个是**原作者的
应用标识**，而自动签名的 profile 是按"账号 + bundleName + 设备"生成的——你用自己的华为
账号去签一个不属于你的 bundleName，装机这一步就可能被拒。改完再跑 `signature generate`，
顺手把同一个文件里的 `vendor`、以及应用显示名（`label` 指向
`AppScope/resources/base/element/string.json` 的 `app_name`）一起核一遍。

**没有签名材料时的行为**：`localSigning` 会直接丢掉 `signingConfigs`，
构建照常成功，只产出 `entry-default-unsigned.hap`，并打印
`[localSigning] ... is missing; building unsigned.` 与
`No signingConfig found for product default`。
未签名包可以拿来验证编译，**装不上设备**——这是预期行为，不是工程坏了。

## 5. 装机与运行

```bash
devecocli device list                              # 看序列号；多台机器时必须显式 --device
devecocli run --device <serial>                    # 构建 + 安装 + 启动 + 冒烟检查
devecocli run --device <serial> --uninstall        # 签名证书换过、装不上时用
devecocli build clean                              # 清构建产物
```

`devecocli run` 的冒烟检查会打印 `Smoke: PASS`，失败时区分
`FAIL_CRASH`（附崩溃日志路径）与 `FAIL_BLANK`（附截图路径）。

## 6. 改代码后快速重来

| 改动类型 | 用什么 |
| --- | --- |
| `.ets` 里的方法体、UI 属性值、文本常量 | `devecocli run --apply changes.txt`（增量，秒级） |
| 资源文件（`resources/**`）、`module.json5`、native | 必须全量 `devecocli run` |
| `@State` 等状态装饰器本身 | 热重载不生效，全量重装 |

`--apply` 的改动清单写在 `.hvigor/changes.txt`（每行一个源文件路径，`#` 开头为注释）。
先用 `--skip-build` 会装旧包——改了资源又想看效果时别用它。

## 7. 下一步

装机后第一次连接桌面端见 [03-run-on-device.md](03-run-on-device.md)；
桌面端只监听回环、手机连不上时看 [04-desktop-cooperation.md](04-desktop-cooperation.md)。
