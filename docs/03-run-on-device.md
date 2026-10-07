# 03 · 装到设备上跑

## 1. 设备从哪来

```bash
devecocli device list            # 真机 + 正在跑的模拟器，含序列号
devecocli emulator list          # 只看模拟器实例（含未启动的）
devecocli emulator start "名称"  # 启动；名字带空格要引号
```

真机需要：开发者模式 + USB 调试（设置 → 关于本机 → 连点版本号 → 开发者选项），
插上后 `hdc` 能认到就算通了。**多台设备同时连着时，所有设备类命令都必须显式
`--device <name|序列号>`**，否则 CLI 直接报"多设备"错误——这是好事，别去猜它选了哪台。

## 2. 一次装好

```bash
devecocli run --device <序列号>                 # 构建 + 装机 + 启动 + 冒烟
devecocli run --device <序列号> --uninstall     # 换过签名证书、装不上时
```

冒烟结果只有三种：`Smoke: PASS`、`FAIL_CRASH`（附崩溃日志路径）、
`FAIL_BLANK`（附截图路径）。后两者会把产物路径直接打在输出里，先去看那个文件再来改代码。

**装机成功 ≠ 启动成功**。真机锁屏时启动会失败：

```
Error Code:10106102  device screen is locked
```

此时包已经装上了，只需解锁再拉起。解锁的脚本化做法（真机实测可用）：

```bash
hdc -t <序列号> shell power-shell wakeup
hdc -t <序列号> shell uitest uiInput swipe 300 1600 300 400 800   # 上滑过锁屏
hdc -t <序列号> shell uitest uiInput keyEvent Home
```

没有锁屏密码时上滑即过；有密码就得手点，脚本代劳不了。

## 3. 模拟器：注意网络口径

模拟器访问宿主机用保留地址 `10.0.2.2`，**不是** `127.0.0.1`，也不是宿主机的局域网 IP。
所以：

| 目标 | 登录页填 |
| --- | --- |
| 模拟器 → 宿主机上的 qp-gate | `http://10.0.2.2:61700` |
| 模拟器 → 宿主机上绑了 0.0.0.0 的桌面端 | `http://10.0.2.2:<端口>` |
| 真机 → 局域网任意机器 | `http://<该机器局域网 IP>:<端口>` |

局域网扫描在模拟器上扫的是 `10.0.2.x`，扫不到宿主机的真实服务，
所以**在模拟器上请手工填地址**，别把"扫描没结果"当成 bug。

## 4. 形态切换与 UI 检查

```bash
devecocli emulator fold <open|half-open|close> --target <名称或序列号>
devecocli emulator rotate left --target <名称>          # 手机模拟器上是空操作，已知
devecocli ui screenshot --device <序列号> --path ./shots/home.png
devecocli ui layout --device <序列号> --mode simplified  # 可点节点的无障碍树
devecocli ui click --device <序列号> --id <节点id>
devecocli ui dircfling up --device <序列号>              # 列表滚动
```

`ui layout` 只给**屏幕内**的节点，被滚出屏幕的元素不在树里；要验证底部按钮先滚到位。
`ui text` 会走焦点输入框，不指定坐标/`--id` 时打到当前焦点。

真机横屏不必用模拟器 rotate：把设备物理转 90°，或者
`hdc shell sensor` 之类的模拟手段都不可靠，直接拿
`devecocli ui screenshot` 核分桶即可（分桶规则见 [06](06-responsive-devices.md)）。

## 5. 看日志

```bash
devecocli log --device <序列号> --bundle-name <bundle> --tail 200
devecocli log --device <序列号> --crash
devecocli log --device <序列号> --level W --from 5m
```

`<bundle>` 是 `AppScope/app.json5` 里那个 `bundleName`。仓库自带的是 `com.liaocaosix.qwenpawmobile`，
而 [02](02-build-and-sign.md) 让你签名前先改成自己的应用标识 —— **改过之后，命令里写旧值一行日志都抓不到**，
把 `<bundle>` 换成你改成的那个值。后面几篇里的 `<bundle>` 同义。

**真机（user 版系统）会裁掉 INFO 级日志**，工程里的 `core/Log.ets` 因此把常规信息
发到更高等级；排查时先 `--level W`，别因为"一条 INFO 都没有"以为进程没起来。
