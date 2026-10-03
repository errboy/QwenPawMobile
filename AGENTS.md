# AGENTS.md

给在这个仓库里干活的 AI agent 的操作手册。人类读者可以先看
[README.md](README.md) 与 [docs/01](docs/01-getting-started.md)。

## 1. 这个项目到底是什么

HarmonyOS（ArkTS / API 20+）客户端，遥控同一局域网里运行的 QwenPaw **桌面端**后端。
桌面端不在本仓库里。本仓库根目录就是 DevEco 工程根；`tools/qp-gate/` 是配套的
Python 守门代理（纯标准库）。

## 2. 日常命令

```bash
devecocli check arkts --fix   # 一轮编辑结束、构建之前跑一次，不要每个 edit 都跑
devecocli check lint          # 规约
devecocli build               # 干净克隆、无证书也应成功
devecocli device list         # 序列号；多台设备时所有设备命令必须显式 --device
devecocli run --device <序列号>
python tools/qp-gate/selftest.py   # 改过 qp_gate.py 必跑，40 项
```

给用户的命令请写成**可直接整行粘贴的绝对路径单行**，不要拆成"先 cd 再执行"的多段。

## 3. 四条不许违反的规则

1. **审批必须由人在场点按钮**。不得实现自动批准、超时默认同意、"本次都同意"，
   也不得代替用户点击。测试审批流程时要明确说明需要用户操作。
2. **汇报必须标明测的是真实桌面端还是桩/mock**。mock 通过不算联调通过；
   用户会拿本机桌面客户端的数据核对。
3. **不写桌面端的全局配置**。`/workspace/running-config` 等只读；
   `PUT` 是整文档替换，一次误点就改写别人的桌面端。
4. **未经明确请求不 commit、不 push**。提交只暂存你改过的具体路径，禁止 `git add -A`。

## 4. 绝不提交

| 路径 | 为什么 |
| --- | --- |
| `tools/qp-gate/gate.json` | 真实口令散列 + 令牌密钥（`gate.example.json` 才是模板） |
| `external-signing-config.json` | keystore 路径与口令 |
| `screenshots/` | 真机截图含真实会话内容与本机 IP |
| `local.properties`、`oh_modules/`、`.hvigor/`、`**/build/` | 本机路径与产物 |
| 带真实局域网 IP / 真实设备名的示例 | 隐私 |

`build-profile.json5` 的 `signingConfigs.material` 必须保持**空串占位**；真实材料由
`hvigorfile.ts` 的 `localSigning` 从 `external-signing-config.json` 折叠进来。
`devecocli signature generate` 会把真实配置**写回** `build-profile.json5` ——
签名之后要手工还原占位并把材料挪回外置文件，否则要么泄露口令，要么破坏干净克隆的构建。

## 5. 代码约定

- ArkTS 严格：禁 `any`/`unknown`，对象字面量需形状。
- 常量用 `export class X { static readonly … }`。
- 注释用英文、写"为什么"（多数是 v1 具体缺陷的复盘）；改逻辑先看被改文件头部那段。
- 用户可见文案一律 `l10n/Copy.ets`，页面里不硬编码中文。
- 日志走 `core/Log.ets`。
- 不加预留开关、不为不可能的分支写防御、不留未引用的参数。
- 依赖方向：`pages → ui → state → api → net → core`，`model/theme/l10n/media` 是被依赖的叶子。

改架构相关任何东西前读 [docs/05-architecture.md](docs/05-architecture.md)。

## 6. 验证设备的正确姿势

```bash
devecocli emulator fold <open|half-open|close> --target <名称>   # 折叠态实时换宽度桶
devecocli ui screenshot --device <序列号> --path ./shots/x.png
devecocli ui layout --device <序列号> --mode simplified
```

- 布局只按**窗口宽度桶**判断，永远不要按设备型号或 `deviceType` 判断（折叠屏恒报 `phone`）。
- 手机模拟器的 `emulator rotate` 是空操作；横屏要真机物理转。
- 模拟器连宿主机用 `10.0.2.2`，并且局域网扫描在模拟器上无效（扫的是 `10.0.2.x`）。
- 真机 `user` 版系统会裁 INFO 级日志，排查用 `--level W`。
- 锁屏会让启动失败（`Error Code:10106102`），包其实已装上；先唤醒解锁再判定成败。

## 7. 图标（分层素材）

- 真正打进包的是 **`AppScope/resources/base/media/foreground.png`**（曾靠解包验证过）；
  `entry` 下那份是配套，改就两份一起改，保持一致。
- 前景必须是**真 alpha 通道的透明 PNG**；素材自带假棋盘（把透明画成灰白格）会导致
  图标看起来没换。背景层必须不透明。
- 备份/中间产物放在 `resources` **之外**——hvigor 资源扫描器会把资源目录里的子目录当成
  非法路径，直接构建失败。
- 图标不得与知名商标造型相似；不使用桌面版 QwenPaw 的图标资产。

## 8. Windows 上的脚本

`.bat` 必须 CRLF + 纯 ASCII（LF 或含中文会让 cmd 解析炸掉，本机 ACP=936）；
`.ps1` 含中文要存成 UTF-8 with BOM。

## 9. 交付前

`devecocli check arkts` → `devecocli check lint` → `devecocli build` →
（动了网关）`selftest.py` → 至少一个设备形态的实测说明 → `CHANGELOG.md` 的
Unreleased 加一行。**别声称 UI 正确**：没在设备上看过的东西要说"未验证"。
