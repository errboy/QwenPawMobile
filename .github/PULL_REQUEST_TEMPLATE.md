<!--
标题用 Conventional Commits：feat(mobile): … / fix(tools): … / docs: … / refactor(icon): …
一个 PR 只做一件事。涉及审批、鉴权、绑定地址的改动请先开 issue 讨论。
-->

## 改了什么

- 

## 为什么

<!-- 动机，或者这个改动修掉的具体缺陷。若推翻了文件头注释里的旧说明，把注释一起改。 -->

## 验证

**测的是真实桌面端还是桩/mock？**（mock 通过不算联调通过）

- [ ] 真实 QwenPaw 桌面端
- [ ] 桩/mock
- [ ] 不涉及运行时

设备与形态：

| 设备 | 竖/横/折叠态 | 宽度桶 | 结果 |
| --- | --- | --- | --- |
|  |  |  |  |

日志/命令输出（删掉真实 IP 与会话内容）：

```

```

## 闸门

- [ ] `devecocli check arkts --fix` 干净
- [ ] `devecocli check lint` 干净
- [ ] `devecocli build` 成功（无证书也应成功）
- [ ] 改了 `qp_gate.py` → `python tools/qp-gate/selftest.py` 全过
- [ ] 改了文档或 `Copy.fill*` 占位符 → `python tools/doc_line_check.py` 0 problems
- [ ] 影响 UI → 至少一个真机 / 模拟器形态的实测说明（截图不入库，写在描述里）
- [ ] 涉及审批 / 鉴权 / 绑定地址 → 已先开 issue 讨论
- [ ] `CHANGELOG.md` 的 Unreleased 加了一行
- [ ] 没有提交 `gate.json` / `external-signing-config.json` / 截图 / 构建产物
- [ ] 带真实局域网 IP 或真实设备名的示例已泛化

## 影响面

<!-- 契约（core/Wire.ets）、状态规则（ChatStore 头部四条）、断点体系、图标素材管线 —— 命中哪个写哪个 -->

## 没做的 / 已知风险

<!-- 诚实写"未验证"比声称通过有用得多。 -->
