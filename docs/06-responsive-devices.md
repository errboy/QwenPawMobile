# 06 · 多设备与折叠形态

## 1. 唯一原则：量窗口，不猜设备

折叠屏合上是 `sm`，展开是 `md`/`lg`，同一台机器会走过几个桶；而折叠屏的系统
deviceType 始终报 `phone`。所以布局键是**窗口宽度（vp）**，不是设备类型：

| 桶 | 窗口宽度 | 典型形态（实测，见下表） |
| --- | --- | --- |
| `xs` | < 320vp | 分屏/悬浮窗里被挤窄的手机窗口 |
| `sm` | 320–600vp | 手机竖屏、折叠屏外屏 |
| `md` | 600–840vp | 折叠屏内屏竖放、横屏手机 |
| `lg` | 840–1440vp | 折叠屏内屏、阔折叠内屏、平板竖屏、2in1 默认窗口 |
| `xl` | ≥ 1440vp | 平板横屏、2in1 最大化 |

阈值来自 `core/Breakpoint.ets:21` 与系统断点一致；取值逻辑在
`core/Breakpoint.ets:98-110`（先按窗口矩形算，UIContext 存在后再按系统能力复核）。
`xs` 保留为声明桶、不并进 `sm`（用户已定）：阈值就是系统断点（上一句），而全 app 没有只为
`xs` 写的分支——`AppMeasure.text`（`theme/Theme.ets:133`）与 `AppMeasure.panel`
（`theme/Theme.ets:141`）对 `xs`/`sm` 返回同一个值。
合并没有收益，只会破坏"桶 = 系统断点"这条。

## 2. 实测过的形态

`core/Breakpoint.ets:4-9` 的注释是权威记录，这里抄成表（模拟器 px/vp 1.9–3.1）：

| 设备 | 形态 | 宽度 | 桶 |
| --- | --- | --- | --- |
| Mate X | 内屏 / 外屏 | 711vp / 345vp | md / sm |
| Mate XT（三折） | 三档 | 1107 / 712 / 350vp | lg / md / sm |
| Pura X Max（阔叠） | 内屏 / 外屏 | 939vp / 459vp | lg / sm |
| MatePad | 竖屏 | 1137vp | lg |
| MatePad Pro 13 | 横屏 | 1440vp | xl |
| MateBook Pro（2in1 模拟器，1.9 px/vp） | 窗口化 / 最大化 | 1349vp / 1642vp | lg / xl |
| nova 14 Pro（真机，3.375 px/vp） | 横屏 | 822vp | md |
| Mate X20（模拟器，API 20） | 展开 / 合上 | 2224px / 1080px | md / sm |
| Mate XT20（模拟器，API 20） | 三档 3184 / 2048 / 1008px | 三档 | lg / md / sm |
| `xsprobe`（自建窄屏实例，720px @480dpi） | 竖屏 | 240vp | **xs** |

最后一行是**唯一能落进 `xs` 桶的形态**：现成的手机/折叠外屏最窄也只到 1008px（`sm` 下沿），
所以这一桶此前没有任何设备能验到。自建实例的做法记在 [08](08-testing.md) §6。

两个反直觉结论：
**阔叠的内屏不天然是窄的**（939vp 是 `lg`）；**`md` 也是手机态**（真机横屏 822vp，
离 `lg` 只差 18vp）。任何"按型号判断"的写法都会在这里翻车。
第三条是这一轮加上的：**同一台三折在三种握法下换三个桶**，日志逐条对得上
（`Window width bucket is sm` → `md` → `lg`，`core/Breakpoint.ets:84`），
所以"折叠态实时换分桶"不是推测。
第四条是 2in1 窗口这一轮补的：**PC 窗口不天然是 `xl`** —— 默认窗口 1349vp 落 `lg`，
离 `xl` 下沿还差 91vp；最大化到 1642vp 才进 `xl`，来回切都实时换桶（见 [08](08-testing.md) §6）。

## 3. 两类宽度上限

宽不等于好。正文行宽被封顶并居中，列表则放开：

| 用途 | 600–840vp | ≥840vp | 来源 |
| --- | --- | --- | --- |
| 聊天/登录/设置正文 `AppMeasure.text` | 600 | 680 | `theme/Theme.ets:131-137` |
| 会话列表/状态行 `AppMeasure.panel` | 680 | 880 | `theme/Theme.ets:139-145` |

`xs`/`sm` 两者都是 `100%`。

媒体气泡不吃这两档：它按气泡宽度的 82% 走，再各自封顶。图片用
`ImageFit.Contain`，本来就变形不了；视频必须**显式**写 `Contain`，因为
`Video` 的默认填充是 `Cover`——它会裁掉装不下的部分。宽屏桶里 82% 能到
557vp 而高度封在 220vp，那是 2.5:1 的框，4:3 的录像放进去只剩中间一条，
所以视频另有一个 391vp（= 220 × 16/9）的宽度上限（`theme/Theme.ets:123-125`）。

工具卡上那些「电脑端发来的文件」行（[05](05-architecture.md)「电脑端「发文件」住在
工具卡的 output 里」）复用同一套上限，不新增宽度规则：图走图片气泡、clip 走视频气泡、
音频与文档各自一张卡。这一轮只在 `sm`（Pura 90 Pro）逐行看过；`lg`/`xl` 是**未验证** ——
阔叠模拟器这次起不来（`emulator list` 报 running、`hdc list targets` 里没有它），
带文件的卡不进组那一条例外在宽桶只按代码推理过，没有截图。

## 4. 首帧不闪跳

分桶在**页面加载之前**就发布一次（读窗口矩形，`core/Breakpoint.ets:93`），
UIContext 起来后再测一次。原因是平板冷启动曾经先画一帧手机宽度再跳 `lg`。
默认值是 `sm`（`Bp.KEY = 'qpWidthBp'`，`core/Breakpoint.ets:34`）——
那是响应式之前所有页面本来的样子，窗口一直没上报也还能用。

## 5. 声明与旋转

`entry/src/main/module.json5`：

- `deviceTypes: ["phone", "tablet"]`（:7-10）。折叠屏报 `phone`，所以不需要单列；
  2in1（PC）模拟器照装不误（模拟器侧如此，见 [08](08-testing.md) §6）。
- `orientation: "auto_rotation_restricted"`（:42）——**手机可以横过来用**，这是刻意开的，
  横屏时宽桶才可达，主页那一排宽卡片在竖屏放不下。但**必须跟住系统的旋转锁定**：
  `auto_rotation`（枚举 0）照样跟随传感器却不受开关控制，`@ohos.window` 里
  `AUTO_ROTATION_RESTRICTED`（枚举 8）才明写"受控制中心旋转开关控制"。
  真机上"开了旋转锁定 app 还在转"就是用了 0 号值。
- 权限只有 `INTERNET`、`GET_NETWORK_INFO`、`MICROPHONE`（:14-31）。

## 6. 字体大小跟随系统

全部字号 token 在 `resources/base/element/float.json` 里写成 `fp`（`app_font_*`），间距、
边框、命中区写 `vp`（`app_space_*`、`app_border_*`、`app_hit_target`）——所以放大字号时只有
文字变，骨架不变。

但**光有 `fp` 不够**：`AppScope/app.json5` 里没有 `configuration` 标签时，ArkUI 把整个应用的
`fp` 换算钉在 1.0，系统【设置 › 显示和亮度 › 字体大小和界面缩放 › 字体大小】对本应用完全无效。
实测对照（同一台 MatePad Pro 13 模拟器，标准 ↔ 超大）：系统设置自己的行高 136px → 208px，
本应用标题 428px → 428px，冷启动重启进程也一样。修法是加
`AppScope/resources/base/profile/configuration.json`（`fontSizeScale: "followSystem"`，
`fontSizeMaxScale: "3.2"`）并在 `app.json5` 用 `"configuration": "$profile:configuration"` 引它。
生效后同一台设备标题 363px → 619px。

跟随之后窄窗口会顶不住，两处标题已改成可收缩：主页头部（`pages/HomePage.ets` 的
`header()`）与清理页头部（`pages/CleanupPage.ets`）原来是 `Text + Blank() + 两个按钮`，
字号一大最后一个按钮整只被挤出屏幕——`ui layout` 里根本没有这个节点，退出/全选点不到。
两处都改成标题 `layoutWeight(1)` + `maxLines(1)` + 省略号，按钮保住位置，聊天页头部
早就是这个写法（主页头部之后又按本节末那段改了 `xs` 分支，其余桶仍是这个写法）。输入框那排
选择器 chip 仍按原设计各自省略（见 `ui/chat/Composer.ets`
里"三个 chip 共用一行"那条注释）：字全部挤成"默认模…"但三个都还在、都还能点。

比省略号更糟的一类长这样：整颗控件**被推到窗口外**，`ui layout` 里连节点都没有 —— 省略号至少
还留着一个能点的残骸。撞到过两处，都是 `Row` 不换行、前一项拿满整行导致的：会话页后台会话条的
第二颗 chip 只剩 24px（`ChatPage.ets`），主页智能体那一行的「🔒 N 项待审批」整颗不见 ——
而那是主页通向待审批的唯一入口（`HomePage.ets`）。两处都改成会换行的
`Flex({ wrap: FlexWrap.Wrap })` 并给文本项 `constraintSize({ maxWidth: '100%' })`：
装不下就各自占一行，装得下仍是一行（nova 标准字号上"⏳ 1 个会话进行中"照旧贴内容右缘）。
复现要靠**又长又像真的**名字 —— 桩有 `--long-names`，跑法与 bounds 见
[08](08-testing.md) §6。同类写法再出现时的判据：行尾是按钮/chip 的行，一律不许用不换行的 `Row`
——**包括没有标题的行**（`xs` 头部第二次就撞在这：标题已让位，两颗按钮自己超宽）。

跟随系统之后在 `xs`（240vp）上，主页头部原本是"标题只剩一个 Q"：标题被挤到 39px，
同行的「主题 · 跟随系统」374px（480dpi，3px/vp）。用户拍板 **`xs` 下不渲染标题**；另一候选
"主题收成图标"未采纳——`AppButton` 没有图标位，为一个桶改共享组件不划算。实现收在
`pages/HomePage.ets` 的 `header()`：`xs` 分支只渲染两颗按钮、`justifyContent: FlexAlign.End`
贴右缘；其余桶照旧 `Text + layoutWeight(1)`。xsprobe 实测（标准字号）：标题节点消失，
「主题 · 跟随系统」[111,165,485,297]、「退出」[509,165,672,297]，与改动前逐像素一致。

同一台上把字号拉到**特大**（240vp 下这条路这次走通了：设置页先滚动再点，
见 [08](08-testing.md) §6 末）又撞出第二处，比标题更重：标题让位后，两颗**全标签**按钮自己
也会超宽——「主题 · 跟随系统」507px、「退出」自然宽 200px，加上 24px 行内间距共 731px，
内容宽只有 624px，「退出」右缘顶到 720px 窗口边缘被切掉一截。这是上一段判据没覆盖到的残角：
那行已经没有标题了。修法：`xs` 分支的行改成会换行的
`Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.End })`，两个方向的行间距用
`LengthMetrics.resource(...)` 给 token 值（全仓首次用 `LengthMetrics`）；非 `xs` 仍是 `Row`，
逐像素未动。特大下实测：「主题」[165,165,672,297] 一行、「退出」[472,321,672,453] 第二行
（间距 24px = 8vp），都在窗内；标准字号仍是一行贴右缘（bounds 同上）。

> 后注（2026-10-06 深夜）：主题按钮文案其后收短为 `主题 ▾`（[08](08-testing.md) §6 末）。
> 同一台复量：标准字号 [296,165,485,297] / [509,165,672,297]，**特大**字号
> [209,165,448,297] / [472,165,672,297] —— 两档都回到**一行**；换行 `Flex` 保留，
> 这次没被触发，判据照旧。

## 7. 主页紧凑开关

`home_compact`（`core/Prefs.ets:32`）：设备级，只影响主页是否只显示主窗口。
大屏默认放开多列，窄窗口收成一列。

## 8. 怎么验一个形态

```bash
devecocli emulator list
devecocli emulator fold half-open --target <名称>      # 折叠态实时改变分桶
devecocli ui screenshot --device <序列号> --path ./shots/fold.png
devecocli ui layout --device <序列号> --depth 3
```

已知坑：

- 手机模拟器的 `emulator rotate` 是**空操作**，横屏要真机物理转或用大屏模拟器形态。
- 2in1 窗口化启动时 `devecocli run` 的 smoke 会**误报** `Smoke: FAIL_CRASH`：`pidof` 里进程还在、
  `devecocli log --crash` 无记录就没事（见 [08](08-testing.md) §6）。
- 深色 + 系统最大字号在 `sm`/`lg`/`xl` 三桶都回归过了（§6）；`xs` 有自建实例（§2）但只跑过
  浅色（标准 + 特大两档），**深色 + 最大字号没组合过**；真机分屏下的 `xs` 也没有。
- `ui layout` 只返回屏幕内节点，验证底部按钮先滚到位。
