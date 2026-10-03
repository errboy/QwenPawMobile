# 06 · 多设备与折叠形态

## 1. 唯一原则：量窗口，不猜设备

折叠屏合上是 `sm`，展开是 `md`/`lg`，同一台机器会走过几个桶；而折叠屏的系统
deviceType 始终报 `phone`。所以布局键是**窗口宽度（vp）**，不是设备类型：

| 桶 | 窗口宽度 | 典型形态（实测，见下表） |
| --- | --- | --- |
| `xs` | < 320vp | 分屏/悬浮窗里被挤窄的手机窗口 |
| `sm` | 320–600vp | 手机竖屏、折叠屏外屏 |
| `md` | 600–840vp | 折叠屏内屏竖放、横屏手机 |
| `lg` | 840–1440vp | 折叠屏内屏、阔折叠内屏、平板竖屏 |
| `xl` | ≥ 1440vp | 平板横屏 |

阈值来自 `core/Breakpoint.ets:21` 与系统断点一致；取值逻辑在
`core/Breakpoint.ets:98-110`（先按窗口矩形算，UIContext 存在后再按系统能力复核）。

## 2. 实测过的形态

`core/Breakpoint.ets:4-9` 的注释是权威记录，这里抄成表（模拟器 px/vp 2.0–2.75）：

| 设备 | 形态 | 宽度 | 桶 |
| --- | --- | --- | --- |
| Mate X | 内屏 / 外屏 | 711vp / 345vp | md / sm |
| Mate XT（三折） | 三档 | 1107 / 712 / 350vp | lg / md / sm |
| Pura X Max（阔叠） | 内屏 / 外屏 | 939vp / 459vp | lg / sm |
| MatePad | 竖屏 | 1137vp | lg |
| MatePad Pro 13 | 横屏 | 1440vp | xl |
| nova 14 Pro（真机，3.375 px/vp） | 横屏 | 822vp | md |

两个反直觉结论：
**阔叠的内屏不天然是窄的**（939vp 是 `lg`）；**`md` 也是手机态**（真机横屏 822vp，
离 `lg` 只差 18vp）。任何"按型号判断"的写法都会在这里翻车。

## 3. 两类宽度上限

宽不等于好。正文行宽被封顶并居中，列表则放开：

| 用途 | 600–840vp | ≥840vp | 来源 |
| --- | --- | --- | --- |
| 聊天/登录/设置正文 `AppMeasure.text` | 600 | 680 | `theme/Theme.ets:141-146` |
| 会话列表/状态行 `AppMeasure.panel` | 680 | 880 | `theme/Theme.ets:149-154` |

`xs`/`sm` 两者都是 `100%`。

## 4. 首帧不闪跳

分桶在**页面加载之前**就发布一次（读窗口矩形，`core/Breakpoint.ets:93`），
UIContext 起来后再测一次。原因是平板冷启动曾经先画一帧手机宽度再跳 `lg`。
默认值是 `sm`（`Bp.KEY = 'qpWidthBp'`，`core/Breakpoint.ets:34`）——
那是响应式之前所有页面本来的样子，窗口一直没上报也还能用。

## 5. 声明与旋转

`entry/src/main/module.json5`：

- `deviceTypes: ["phone", "tablet"]`（:7-10）。折叠屏报 `phone`，所以不需要单列。
- `orientation: "auto_rotation"`（:42）——**手机可以横过来用**，这是刻意开的，
  横屏时宽桶才可达，主页那一排宽卡片在竖屏放不下。
- 权限只有 `INTERNET`、`GET_NETWORK_INFO`、`MICROPHONE`（:14-31）。

## 6. 主页紧凑开关

`home_compact`（`core/Prefs.ets:32`）：设备级，只影响主页是否只显示主窗口。
大屏默认放开多列，窄窗口收成一列。

## 7. 怎么验一个形态

```bash
devecocli emulator list
devecocli emulator fold half-open --target <名称>      # 折叠态实时改变分桶
devecocli ui screenshot --device <序列号> --path ./shots/fold.png
devecocli ui layout --device <序列号> --depth 3
```

已知坑：

- 手机模拟器的 `emulator rotate` 是**空操作**，横屏要真机物理转或用大屏模拟器形态。
- 深色 + 大字号 + 分屏三件事在 `lg`/`xl` 桶上还没做完整回归（见 [../CHANGELOG.md](../CHANGELOG.md) 的"尚未验证"）。
- `ui layout` 只返回屏幕内节点，验证底部按钮先滚到位。
