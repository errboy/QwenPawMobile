# 贡献指南

小到改一个字也欢迎。开工前请先读 [SECURITY.md](SECURITY.md) —— 这个 App 操控的是
能在你桌面上执行命令的 agent，有些"顺手加个自动同意"的改动是不被接受的。

## 1. 环境

DevEco Studio 6.x + HarmonyOS SDK API 20。可选 `devecocli`（本文命令用它）。
**克隆下来不需要任何账号或证书就能构建**（详见 [docs/02](docs/02-build-and-sign.md)）。

本工程**没有第三方运行时依赖**，也不要引入：`oh_modules/`、`.hvigor/`、`**/build/`
全在 `.gitignore` 里。

## 2. 改之前先看的位置

| 你要做的事 | 权威文件 |
| --- | --- |
| 加/改端点 | `core/Wire.ets`（常量表）→ `api/` → `model/Dtos.ets` |
| 改布局宽度 | `core/Breakpoint.ets` + `theme/Theme.ets` 的 `AppMeasure` |
| 加文案 | `l10n/Copy.ets`（页面里不出现硬编码中文） |
| 改流式行为 | `stream/StreamReducer.ets` 头部注释（v1 的重复渲染就出在这） |
| 改状态传播 | `state/ChatStore.ets` 头部四条规则 |
| 连不上桌面端 | [docs/04](docs/04-desktop-cooperation.md)，九成是绑定地址问题 |

分层依赖方向只允许 [docs/05](docs/05-architecture.md) 里那条箭头链，不要反向 import。

## 3. 代码风格

从现有代码归纳，不一致的地方以邻近文件为准。

- ArkTS 严格模式：不用 `any` / `unknown`；对象字面量必须有声明过的形状。
- 常量用 `export class X { static readonly a: string = 'a'; }`，不用裸 `const` 大写堆。
- 缩进 2 空格、单引号、分号；行宽约 100。
- **注释写"为什么"，不写"是什么"**。文件头那段注释通常是某个具体缺陷的复盘，
  改动前先读它；推翻了它就改注释，别留过期说明（历史上真有过一条被实测推翻的
  widefold 注释）。
- 注释与标识符用英文；用户可见文本一律走 `Copy.ets`。
- 日志走 `core/Log.ets`，不用 `console.log`。注意 user 版系统会裁 INFO 级日志。
- 只为**当前**需求写代码：不加预留开关、不给不可能的分支加防御、
  不留"改天再清理"的死参数。删掉未引用的东西是正确做法。

## 4. 提交

Conventional Commits，scope 用 `mobile` / `tools` / `icon` / `docs` / `chore`：

```
feat(mobile): render markdown in assistant chat bubbles
fix(tools): make qp-gate actually start on a Chinese Windows console
```

正文说清动机与验证方式，尤其是**测的是真实桌面端还是桩**、在什么设备/形态上验的。
不确定的事别替仓库下结论。

只暂存你确实改过的路径（`git add <具体文件>`），不要用 `git add -A` 一把梭 ——
构建产物与本机文件很容易跟着进去。提交前跑一次：

```bash
git status --short
```

确认没有 `gate.json`、`external-signing-config.json`、`screenshots/`、
`local.properties`、`oh_modules/`、`entry/build/`。

## 5. PR 检查清单

- [ ] `devecocli check arkts --fix` 干净
- [ ] `devecocli check lint` 干净
- [ ] `devecocli build` 成功（无证书也应成功，产物 unsigned）
- [ ] 改了 `qp_gate.py` → `python tools/qp-gate/selftest.py` 全过
- [ ] `python tools/doc_line_check.py` 0 problems（它管三件事：文档里的代码行引用、markdown
      相对链接、`Copy.fill*` 的占位符数量。后两样 ArkTS 与 lint 都不报，只在屏幕上说谎）
- [ ] 影响 UI → 至少一个真机/模拟器形态的实测说明（截图不入库，写在描述里）
- [ ] 影响服务端交互 → 说明是否连真实端验过
- [ ] 涉及审批/鉴权/绑定地址 → 先开 issue 讨论，别直接提交
- [ ] `CHANGELOG.md` 的 Unreleased 加一行

大 PR 拆小；一个 PR 只做一件事。行为变更比代码变更更需要证据。

## 6. 沟通

先 issue 后 PR，尤其是：新能力、契约变更、任何触碰审批/鉴权的东西。
用 `.github/ISSUE_TEMPLATE` 里的模板，把设备型号、系统版本、断点桶、
是真实端还是桩都写上——这几项缺一个，问题基本无法复现。

## 7. 许可

提交即同意以 Apache License 2.0 授权你的贡献。不要提交你没有权利分发的素材
（图标、字体、截图里的第三方界面）。
