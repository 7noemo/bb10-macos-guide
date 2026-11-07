# 06 · 排错

按现象查。每条都给「怎么判断」和「怎么修」。

---

## 环境类

### `Couldn't load dynamic library libusb`

```
An unhandled exception occurred:
Exception: Couldn't load dynamic library libusb.
```

**原因**：`bb10mt` 依赖 `libusb`，官方包没带 macOS 版。

**修**：跑 `./scripts/setup.sh`。它会编译 libusb 和 lzo2 并配好 `DYLD_LIBRARY_PATH`。
手动确认：

```bash
./bb10mt --version        # 应该直接输出版本号，无任何警告
ls lib/                   # 应该有 libusb.dylib、liblzo2.dylib 等
```

### `Couldn't load dynamic library liblzo2`

同上，缺 lzo2。跑 `setup.sh`。

### `Warning: loaders.dat not found`

`loaders.dat` / `loaders.ini` 必须和**二进制放在同一目录**（`bin/`），不是当前工作目录。
`setup.sh` 会自动摆好。手动修：

```bash
cp loaders.dat loaders.ini bin/
```

### 「无法打开，因为无法验证开发者」

Gatekeeper 拦截。批量去掉隔离属性：

```bash
xattr -dr com.apple.quarantine bb10-root/
```

### `Killed: 9`

二进制架构不对（比如在 Intel Mac 上跑了 aarch64 版）。
用 `./bb10mt` 包装脚本，它会自动按 `uname -m` 选。

---

## 刷机类

### `flash` 一直等不到设备

终端停在 `Waiting for device` / `Connecting to bootrom` 不动。

按顺序排查：

1. **手机真的关机了吗** —— 长按电源键，看到关机动画，等屏幕全黑
2. **线能传数据吗** —— 换一根，最好是原装或明确标「数据线」的。这条原因占一半以上
3. **换 USB 口** —— 直插 Mac 机身，别用 hub、别用转接头
4. **手动开机** —— 插着线，按住电源键 3 秒开机
5. **拔插一次** —— 命令还挂着的时候拔掉线，等 2 秒再插
6. **换个 USB-C 口试试** —— MacBook 上不同口的供电/控制器不一样

还是不行，试试点完命令后立刻关机插线，抢在超时前。

### 红灯 / 绿灯是什么意思

| 状态 | 含义 | 该做什么 |
|---|---|---|
| **绿灯常亮** | 已进入 bootrom，正在接收数据 | 等 |
| **红灯常亮** | 正在写 flash | 等，**别拔线** |
| **红灯闪烁** | 写入中（部分型号） | 等 |
| **红灯快速闪 3 下停一下** | 错误码，按二进制读 | 见下 |
| **完全没灯** | 没识别到 / 没通电 | 检查线、口、电池 |

**错误码读法**：1 = 亮，0 = 灭。比如「亮-灭-亮」= `101` = 5。
对照社区的错误码表（搜 `BB10 error code blinking red`），常见的是 0010/0011，多半是固件不匹配。

### `Wrong device` / 刷到一半报机型不对

**你下错包了。** 或者拆包时混进了别的机型的文件。

回去对 [01 · 机型对应表](01-check-device.md#三型号--固件对应表)，重点检查：

- Z10 是不是 STL100-1（独一份）
- Passport 后缀对不对
- Z3 是不是拿了 Z30 的包

### 刷完无限重启 / 卡在黑莓 logo

多半是**只刷了一半**（radio 没刷，或者中途断了）。

修：完整重刷一遍，先 `.0.signed` 再 `.1.signed`，中间不要断电。

### 卡在 WiFi / BBID 初始化出不去

BB10 服务器已死，这是必然的。见 [03 · 刷机的第 4 步](03-flash.md#第-4-步跳过初始化这一步最容易卡)。

如果你刷的是 root 包，`patch.txt` 里已经有跳过初始化补丁，理论上不会卡。
还卡的话重刷一次，刷完等 3 分钟再操作。

### `batch` 报 `No space left on device`

生成 root 包要 **10 GB 以上**临时空间（解出 3 GB 的 ifs + 3 GB 的 rcfs + 重新打包）。

```bash
df -h /tmp          # 看剩余空间
export TMPDIR=~/bb10tmp && mkdir -p $TMPDIR   # 换到大盘
```

或者用 `-c` 压缩（更慢但省空间）。

---

## 设备识别类

### Mac 上看不到 169.254.0.1 那张网卡

1. `设置 → 存储和访问` → 确认「USB 大容量存储」是**关**的
2. 换线（又来了，真的是第一大原因）
3. 系统设置 → 网络 → 看有没有 `RIM` 或 `BlackBerry` 开头的接口
4. 拔插后等 10 秒，BB10 建链路比较慢

### `bb10mt info` 没反应

设备没连上，或者不在正确模式。
`info` 走的是 USB 网线（需要设备正常开机）；`flash` 走的是 bootrom（需要设备关机）。
两个模式不一样，别搞混。

---

## 判断是不是真砖了

**大概率能救**：

- 能进 bootrom（插线有灯反应）
- `flash` 能识别到设备
- 屏幕有反应（哪怕只是黑屏亮背光）

**基本没救**：

- 插线完全没反应，任何灯都不亮
- 充电没反应，电脑不认识这个 USB 设备
- 刷机中途 NVRAM 被改坏（`mod_nvram` 玩脱了）

BB10 **没有公开的 EDL / 9008 救砖通道**，也没有签名好的底层恢复包。
真砖了只能换主板，或者当零件机。

**所以：包别下错、线别用烂的、刷机时别拔线、`mod_nvram` 别乱动。**

---

## 还是不行？

去这些地方问，附上：机型、OS 版本、完整命令、完整报错、指示灯状态。

- [CrackBerry BB10 论坛](https://forums.crackberry.com/)
- bb10.root.sx 作者的 Discord（项目页有链接）
- XDA 的 BlackBerry 板块（活跃度低，但存档有价值）
