# 06 · 多设备与折叠形态

## 1. 唯一原则：量窗口，不猜设备

折叠屏合上是 `sm`、展开是 `md`/`lg`，同一台机器会走过几个桶；而折叠屏的系统
deviceType 始终报 `phone`。所以布局键是**窗口宽度（vp）**，不是设备类型：

| 桶 | 窗口宽度 | 典型形态 |
| --- | --- | --- |
| `xs` | < 320vp | 分屏/悬浮窗里被挤窄的手机窗口 |
| `sm` | 320–600vp | 手机竖屏、折叠屏外屏 |
| `md` | 600–840vp | 折叠屏内屏竖放、横屏手机 |
| `lg` | 840–1440vp | 折叠屏内屏、阔折叠内屏、平板竖屏、2in1 默认窗口 |
| `xl` | ≥ 1440vp | 平板横屏、2in1 最大化 |

阈值在 `core/Breakpoint.ets:21`，与系统断点一致；取值逻辑在 `core/Breakpoint.ets:98-110`
（先按窗口矩形算，UIContext 存在后再按系统能力复核）。`xs` 保留为声明桶、不并进 `sm`：
`AppMeasure.text`（`theme/Theme.ets:133`）与 `AppMeasure.panel`（`theme/Theme.ets:141`）对这两桶
返回同一个值，合并没有收益，只会破坏"桶 = 系统断点"这条。

## 2. 实测过的形态

| 设备 | 形态 | 宽度 → 桶 |
| --- | --- | --- |
| Mate X | 内屏 / 外屏 | 711vp → `md` / 345vp → `sm` |
| Mate XT（三折） | 三档 | 1107 / 712 / 350vp → `lg` / `md` / `sm` |
| Pura X Max（阔叠） | 内屏 / 外屏 | 939vp → `lg` / 459vp → `sm` |
| MatePad（平板） | 竖屏 | 1137vp → `lg` |
| MatePad Pro 13 | 横屏 | 1440vp → `xl` |
| MateBook Pro（2in1） | 窗口化 / 最大化 | 1349vp → `lg` / 1642vp → `xl` |
| nova 14 Pro（真机） | 横屏 | 822vp → `md` |
| 自建 720px @480dpi 实例 | 竖屏 | 240vp → **xs** |

读数抄自 `core/Breakpoint.ets:4-9` 的注释（模拟器 px/vp 1.9–3.1）。四条结论都是**按型号判断就会翻车**
的地方：阔叠的内屏不天然窄（939vp 是 `lg`）；`md` 也是手机态（真机横屏 822vp，离 `lg` 只差 18vp）；
同一台三折在三种握法下换三个桶；PC 窗口不天然是 `xl`（默认 1349vp 落 `lg`，最大化才进 `xl`）。
换桶都是实时的，不用重启。

## 3. 两类宽度上限

宽不等于好。正文行宽被封顶并居中，列表则放开：

| 用途 | 600–840vp | ≥840vp | 来源 |
| --- | --- | --- | --- |
| 聊天/登录/设置正文 `AppMeasure.text` | 600 | 680 | `theme/Theme.ets:131-137` |
| 会话列表/状态行 `AppMeasure.panel` | 680 | 880 | `theme/Theme.ets:139-145` |

`xs`/`sm` 两者都是 `100%`。

媒体气泡不吃这两档：它按气泡宽度的 82% 走，再各自封顶。图片用 `ImageFit.Contain`，本来就变形不了；
视频必须**显式**写 `Contain`，因为 `Video` 的默认填充是 `Cover`——它会裁掉装不下的部分。视频高度封在
220vp，所以它另有一个 391vp（= 220 × 16/9）的宽度上限（`theme/Theme.ets:123-125`），否则 4:3 的录像
放进宽桶那个 2.5:1 的框里只剩中间一条。

工具卡上那些「电脑端发来的文件」行（[05](05-architecture.md)）复用同一套上限，不新增宽度规则：
图走图片气泡、clip 走视频气泡、音频与文档各自一张卡。

## 4. 首帧不闪跳

分桶在**页面加载之前**就发布一次（读窗口矩形，`core/Breakpoint.ets:93`），UIContext 起来后再测一次。
默认值是 `sm`（`Bp.KEY = 'qpWidthBp'`，`core/Breakpoint.ets:34`）。改响应式时别去掉这一次预发布
——平板冷启动曾经先画一帧手机宽度再跳 `lg`。

## 5. 声明与旋转

`entry/src/main/module.json5`：

- `deviceTypes: ["phone", "tablet"]`（:7-10）。折叠屏报 `phone`，所以不需要单列。
- `orientation: "auto_rotation_restricted"`（:42）——**手机可以横过来用**，这是刻意开的，
  横屏时宽桶才可达，主页那一排宽卡片在竖屏放不下。但它**必须跟住系统的旋转锁定**：
  `auto_rotation`（枚举 0）照样跟随传感器却不受开关控制，`@ohos.window` 里
  `AUTO_ROTATION_RESTRICTED`（枚举 8）才明写"受控制中心旋转开关控制"。
  "开了旋转锁定 app 还在转"就是用了 0 号值。
- 权限只有 `INTERNET`、`GET_NETWORK_INFO`、`MICROPHONE`（:14-31）。

## 6. 字体大小跟随系统

字号 token（`app_font_*`）在 `resources/base/element/float.json` 里写成 `fp`，间距、边框、命中区
（`app_space_*`、`app_border_*`、`app_hit_target`）写 `vp` ——放大字号时只有文字变，骨架不变。

但**光有 `fp` 不够**：`AppScope/app.json5` 里没有 `configuration` 标签时，ArkUI 把整个应用的 `fp` 换算
钉在 1.0，系统【设置 › 显示和亮度 › 字体大小和界面缩放 › 字体大小】对本应用完全无效。要跟随就得有
`AppScope/resources/base/profile/configuration.json`（`fontSizeScale: "followSystem"`、
`fontSizeMaxScale: "3.2"`）并在 `app.json5` 用 `"configuration": "$profile:configuration"` 引它。

跟随之后窄窗口会顶不住，两条写法是硬要求：

- **标题行**：标题要 `layoutWeight(1)` + `maxLines(1)` + 省略号。`Text + Blank() + 两个按钮` 这种写法
  在字号变大后会把最后一颗按钮整只挤出屏幕，`ui layout` 里连节点都没有，退出/全选点不到。
  `xs`（240vp）连标题都放不下，主页头部在 `xs` 直接不渲染标题、只留两颗按钮贴右缘。
- **行尾是按钮 / chip 的行，一律不许用不换行的 `Row`**，**包括没有标题的行**。前一项拿满整行会把后面的
  控件推到窗口外，比省略号更糟。写法是 `Flex({ wrap: FlexWrap.Wrap })` 并给文本项
  `constraintSize({ maxWidth: '100%' })`：装不下就各自占一行，装得下仍是一行。

输入框那排三个选择器 chip 按原设计各自省略（见 `ui/chat/Composer.ets`）：字挤成"默认模…"但三颗都还在、
都还能点。

## 7. 主页紧凑开关

`home_compact`（`core/Prefs.ets:32`）：设备级，只影响主页是否只显示主窗口。
大屏默认放开多栏，窄窗口收成一列。

## 8. 怎么验一个形态

```bash
devecocli emulator list
devecocli emulator fold half-open --target <名称>      # 折叠态实时改变分桶
devecocli ui screenshot --device <序列号> --path ./shots/fold.png
devecocli ui layout --device <序列号> --depth 3
```

已知坑：

- 手机模拟器的 `emulator rotate` 是**空操作**，横屏要真机物理转或用大屏模拟器形态。
- 2in1 窗口化启动的 smoke **误报**（`Smoke: FAIL_CRASH` 而应用照常起来）见 [09](09-troubleshooting.md) §2。
- `ui layout` 只返回屏幕内节点，验证底部按钮先滚到位。
- 各形态还欠哪一步（含 `xs` 与深色 + 最大字号的组合）只记在 [08](08-testing.md) §6，不在这里重复。
