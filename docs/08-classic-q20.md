# 08 · Classic / Q20 实机刷机全记录

这一篇不是教程综述，是**一台真机从零刷到 root 的完整过程**，包括所有踩坑和现场结论。
型号 **BlackBerry Classic（Q20，`SQC100-3`）**，系统 `10.3.3.3216`，主机 macOS 26 / Apple Silicon。

> 结论先行：**最终成功了**，root 可用，SSH 可登录。
> 但路径和网上教程（以及 AutoRoot 官方文档）写的**不一样**，照着官方文档走会在第 3 步直接卡死。

---

## 为什么 Classic 用 Z30 的包

Classic（SQC100）、Z30（STA100）、Leap（STR100）三者平台和基带相同，黑莓当年只发了一份合并包：

```
Z30_10.3.03.3216_STA100-1-2-3-4-5-6.exe
```

文件名里没有 `SQC100`，但它**确实是 Classic 的官方包**。

⚠️ 反过来：Q10/Q5（`SQN100`）、Passport（`SQW100`）的包绝对不能用于 Classic。

---

## 实测环境

| 项 | 值 |
|---|---|
| 主机 | Mac Apple Silicon（arm64），macOS 26 |
| 工具 | bb10mt 0.6.0.0 beta4（macOS 原生二进制 + 自编译 libusb/lzo2） |
| 手机 | Classic SQC100-3，BootROM `9500270A`，OS 10.3.3.3216 |
| 磁盘峰值 | 下载 1.5 GB + 解压 2.8 GB + 构建 11 GB ≈ 16 GB |
| 全程耗时 | 约 2 小时（其中一半花在排查 loader 和签名包的问题上） |

---

## 第 0 步：备份（会清空数据）

刷 root 包会格式化 user 分区，**等于恢复出厂**：照片、短信、聊天记录、已装应用全没。

- 照片 / 文档：插 SD 卡拷走，或用 `设置 → 存储和访问` 挂到电脑
- 联系人：`联系人 → 设置 → 导出到 SIM / vCard`
- 别指望 BlackBerry Link，服务早停了

---

## 第 1 步：下固件

```bash
python3 scripts/mega-fetch.py \
  --url "https://mega.nz/file/tVgyjDYS#ojnru-l0Apt1289OrZ7zDkvvxzFtfCIkAU1dIybpHK0" \
  --out ./Z30_3216.7z
```

实测 16 分钟（香港节点 ~2 MB/s）。校验：

```bash
shasum -a 256 Z30_3216.7z
# bae7cd04b5376e82aa85edbf915996e06d90cea3f6747cd99207b5354a3d57f8
```

解压必须用真 7-Zip（这批包用了 BCJ2 过滤器，py7zr 会失败）：

```bash
./7zz x Z30_3216.7z     # → Z30_...exe，2.8 GB
```

---

## 第 2 步：生成 Root 包

```bash
cd bb10-root
./bb10mt batch -i autoloader/Z30_10.3.03.3216_STA100-1-2-3-4-5-6.exe -s patch.txt -o build
```

实测 **18 秒**。产物不只两个 exe，还有一批中间文件，**关键区别在这里**：

```
build/
├── ....0.signed      2.8 GB   ← 原始签名镜像（刷了 = 干净官方系统，无 root）
├── ....0.unsigned    2.8 GB   ← 打过 root 补丁的镜像 ★真正要刷的
├── ....1.signed       52 MB   ← radio
├── ...._os.exe       2.8 GB   ← 官方流程给 Windows 用的封装，bb10mt 刷不了
└── ...._radio.exe     61 MB
```

验证哪个是打了补丁的：

```bash
python3 - <<'PY'
import pathlib
for f in pathlib.Path("build").glob("*.signed"):
    d=f.read_bytes(); print(f.name, "use.root:", d.count(b"use.root"))
PY
# 0.signed → 0      ← 没补丁
# 0.unsigned → 2    ← 有补丁
```

> 🔴 **这是整篇文章最重要的一条**：`.signed` 是原始签名镜像，`.unsigned` 才是补丁版。
> 刷错了会得到一台"全新的官方系统"，root 一点影子都没有。

---

## 第 3 步：处理 loader 缺失（Classic 特有坑）

第一次刷会失败：

```
BlackBerry Classic SQC100-3 (9500270A)
No valid loader found for 9500270A
```

原因：`bb10mt` 自带的 `loaders.dat` 里 **213 个 loader，Classic 只有 `9400270A`（SQC100-2）**，
没有 SQC100-3 的。跑 `./bb10mt loader` 逐个探测，82 个全部拒绝。

**解决办法：借同平台 loader。** Classic 各 SKU 是同一套硬件（都是 MSM8960 + `270A` 平台），
只有第一位（94/95/96/97/9c）区分销售型号：

```bash
# 1. 从官方 cap.exe 里抽出所有 loader
./bb10mt autoloader loaders -i cap.exe -o caploaders

# 2. 把 SQC100-2 的 loader 复制成 SQC100-3 的名字
mkdir -p myloaders
cp caploaders/cap/loader_9400270A-00.bin myloaders/loader_9500270A-00.bin

# 3. 刷机时用 -r 指定这个目录
./bb10mt flash -r myloaders -i ...
```

结果：设备**接受**了这个 loader，正常切到 Mode(2)、读出闪存分区表。
实测可行，同类推法也能救 SQC100-1/4/5、Z30 STA100-5 这些缺失型号。

---

## 第 4 步：刷入（顺序和官方文档不同）

### ❌ 官方文档的写法（在 macOS 上行不通）

```bash
./bb10mt flash -i build/...._os.exe
# → Making QCFM stream → Flash error（0% 即失败）
```

`bb10mt` 处理不了自己 batch 出来的 exe，这条路直接堵死。

### ✅ 实际可用的写法

**OS 和 radio 必须放在一条命令里、一次刷完：**

```bash
./bb10mt flash -r myloaders \
  -i "build/....0.unsigned,build/....1.signed"
```

为什么必须一起：只刷 `0.unsigned` 时，设备**刷完不启动**，卡在 BootROM 黑屏。
两个一起刷，设备才正常起来。这是实测出来的，官方文档没写。

准备：电量 50%+、能传数据的线、直插 Mac、拔 SIM 和 SD 卡。

命令跑起来后：**手机关机 → 插线**，工具自己接上。

日志正常长这样：

```
loader: myloaders/loader_9500270A-00.bin
Sending loader to device...   [100%]
Running loader...
Flashing 2 files...
Flashing: ....0.unsigned      [100%] Send signature / Done
Flashing: ....1.signed        [100%] Send signature / Done
Rebooting phone...
Error executing command: Init: LIBUSB_ERROR_OTHER   ← 这是断开 USB 的正常报错
```

最后那行 `LIBUSB_ERROR_OTHER` **不是失败**，是设备重启导致 USB 断开，可以忽略。

---

## 第 5 步：跳过开机向导

刷完会进初始化向导（user 分区被格式化了，这是正常的）。

**BBID 登录页永远过不去**——BlackBerry 服务器 2022 年就关了。跳过方法：

1. WiFi 页面随便连一个网络
2. 走到「连接移动网络」页，**快速连按三次电源键**启动屏幕阅读器（可能要等十几秒才出声）
3. 两指双击屏幕激活阅读器
4. 点 **Skip** 跳过移动网络
5. 下一页 WiFi 页面等着，听到 BBID 提示时，**在标题正下方两指双击**
6. 弹出「是否跳过 BBID」→ **Skip**
7. 软件更新 → 忽略 → 完成

这步可能要重复两三遍，正常。

---

## 第 6 步：验证 root

刷对包之后，root 是**自动生效**的，不需要点任何东西：

- 通知栏会弹出 `root v4` 提示
- 桌面出现 **Term49**
- 设备的 USB 网卡 IP 会被脚本主动设成 **`169.254.0.1`**

> 💡 判断 root 有没有生效的一个土办法：看 Mac 上那张 USB 网卡的 IP。
> 如果 Mac 拿到的是 `169.254.0.2`，说明设备的 root 脚本跑了（它把自己设成 .1）；
> 如果 Mac 拿到的是随机 `169.254.x.y`，说明脚本没跑，root 没生效。

### SSH 登录：账号是 root，不是 devuser

`patchdata/var/etc/ssh/sshd_config` 里写的是：

```
AllowUsers=root
PermitRootLogin=yes
AuthorizedKeysFile=/etc/ssh/authorized_keys2
PasswordAuthentication=no
```

所以：

```bash
ssh -i id_rsa4x root@169.254.0.1     # ✅
ssh -i id_rsa4x devuser@169.254.0.1  # ❌ Authentication failed
```

### ⚠️ macOS 自带 ssh 连不上（重要）

设备上的 sshd 是 **OpenSSH 6.2（2013 年 QNX 版）**，只认 `ssh-rsa`（SHA-1）签名。
而 macOS 现在的 OpenSSH 10 **已彻底移除该算法**，直连必然失败：

```
Unable to negotiate ... no matching host key type found. Their offer: ssh-rsa
# 加了 -o HostKeyAlgorithms=+ssh-rsa 会变成：
Connection closed by 169.254.0.1 port 22
```

**解决办法**：用支持 `ssh-rsa` 的 paramiko 3.x，并用系统自带的 `nc` 做本地中转
（macOS 的"本地网络"权限会拦截 Python 直连 169.254.x.x，`nc` 不受影响）。

仓库里已经封装成一条命令：

```bash
./scripts/bbssh "id; ls /var/rootdata"
./scripts/bbssh                     # 交互 shell
```

实测输出：

```
Term49.bar  backup  install.sh  installer  term49.installed  use.root  use.sshd
QNX BLACKBERRY-6B84 8.0.0 2018/02/21 MSM8960_V3.2.1.1_N_CLASSICVZW_Rev:12 armle
```

看到 `use.root` / `use.sshd` 两个文件 + `QNX ... CLASSICVZW` 内核串，就是确认到位了。

---

## 完整命令清单（复制即用）

```bash
cd bb10-root

# 1. 借 loader
./bb10mt autoloader loaders -i cap.exe -o caploaders
mkdir -p myloaders
cp caploaders/cap/loader_9400270A-00.bin myloaders/loader_9500270A-00.bin

# 2. 一次性刷 OS + radio
./bb10mt flash -r myloaders -i "build/....0.unsigned,build/....1.signed"

# 3. 手机关机 → 插线，等它跑完

# 4. 跳过开机向导，进桌面

# 5. 连 root
./bbssh "id"
```

---

## 踩坑总表

| 现象 | 真正原因 | 处理 |
|---|---|---|
| `No valid loader found for 9500270A` | loaders.dat 没有 SQC100-3 的 loader | 借 `9400270A` 的 loader 改名 |
| `Failed to connect after maximum attempts` | 连续探测把 BootROM 会话耗尽了 | 拔线 → 长按电源 10 秒 → 重插 |
| 刷 `_os.exe` 报 `Flash error`（0%） | bb10mt 处理不了自建的 exe | 改刷 `.0.unsigned` + `.1.signed` |
| 只刷 `.0.unsigned` 后不开机 | OS 和 radio 必须成套刷 | 两个文件写在同一条 `-i` 里，逗号分隔 |
| 刷完是全新系统、没 root | 刷成了 `.signed`（原始签名镜像） | 改刷 `.0.unsigned` |
| SSH 端口拒绝 | sshd 没起来 = root 没生效 | 检查是否刷了对的镜像 |
| `no matching host key type` | OpenSSH 10 不支持 ssh-rsa | 用 `scripts/bbssh` |
| `Authentication failed` | 用 devuser 登录 | 改成 `root` |

---

继续 → [05 · Root 之后玩什么](05-post-root.md)
