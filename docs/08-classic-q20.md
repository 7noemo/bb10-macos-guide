# 08 · Classic / Q20 实操记录

这一篇是**实机走一遍的完整记录**，不是泛泛而谈。
型号：BlackBerry Classic（开发代号 **Q20**，型号编号 `SQC100-x`），系统 OS `10.3.3.3216`。

> 如果你的机器不是 Classic，看 [01 · 查机型](01-check-device.md) 找到对应文件，流程完全一样。

---

## 为什么 Classic 刷 Z30 的包

Classic（SQC100）、Z30（STA100）、Leap（STR100）三者**硬件平台和基带相同**，
黑莓当年只发了一份合并包：

```
Z30_10.3.03.3216_STA100-1-2-3-4-5-6.exe
```

文件名里虽然没有 `SQC100`，但它**确实是 Classic 的官方包**。
CrackBerry 的机型对照表、官方 OSINFO 都是这么写的，不用怀疑。

⚠️ 反过来说：**Q10/Q5 的包绝对不能用**（`SQN100`），Passport 的也不能用（`SQW100`）。

---

## 本次实测的环境

| 项 | 值 |
|---|---|
| Mac | Apple Silicon（arm64），macOS 26 |
| 工具 | bb10mt 0.6.0.0 beta4（macOS 原生 + 自编译 libusb/lzo2） |
| 手机 | Classic，OS 10.3.3.3216（已经是目标版本，**不需要先刷官方包**） |
| 磁盘占用 | 下载 1.5 GB + 解压 2.8 GB + 构建 11 GB，峰值约 **16 GB** |

---

## 第 0 步：备份

刷 root 包会写 user 分区，**等于恢复出厂**：照片、短信、聊天记录、装过的应用全没。

- 照片 / 文档：插 SD 卡拷走，或者用 `设置 → 存储和访问` 挂到电脑上拷
- 联系人：`联系人 → 设置 → 导出到 SIM 卡 / vCard`
- 其他：BB10 的备份服务已经死了，`BlackBerry Link` 也不认新系统，别指望

---

## 第 1 步：下固件

```bash
python3 scripts/mega-fetch.py \
  --url "https://mega.nz/file/tVgyjDYS#ojnru-l0Apt1289OrZ7zDkvvxzFtfCIkAU1dIybpHK0" \
  --out ./Z30_3216.7z
```

实测 16 分钟（香港节点 ~2 MB/s，中途被换过 3 次节点）。

校验：

```bash
shasum -a 256 Z30_3216.7z
# bae7cd04b5376e82aa85edbf915996e06d90cea3f6747cd99207b5354a3d57f8
```

解压（一定要用真 7-Zip，BCJ2 过滤器）：

```bash
./7zz x Z30_3216.7z
# 得到 Z30_10.3.03.3216_STA100-1-2-3-4-5-6.exe，2.8 GB
```

---

## 第 2 步：生成 Root 包

```bash
cd bb10-root
./bb10mt batch \
  -i autoloader/Z30_10.3.03.3216_STA100-1-2-3-4-5-6.exe \
  -s patch.txt \
  -o build
```

实测耗时 **18 秒**（M 系列 + NVMe，纯 IO 活）。

成功的话 `build/` 里会出现两个星级文件：

```
build/
├── Z30_10.3.03.3216_STA100-1-2-3-4-5-6_os.exe      2.8 GB   ★ 先刷
├── Z30_10.3.03.3216_STA100-1-2-3-4-5-6_radio.exe    61 MB   ★ 后刷
└── 一堆 .ifs/.rcfs/.ufs/.signed 中间文件，可以删
```

日志里应该能看到这些关键行：

```
[INFO] Successfully touched file "/var/rootdata/use.root"
[INFO] Successfully touched file "/var/rootdata/use.sshd"
[INFO] Removed "com.rim.bb.app.facebook...." from "/apps"
Packing files into OS autoloader...
Packing files into Radio autoloader...
```

`use.root` 没出现 = root 没打开；`use.sshd` 没出现 = SSH 没开。
两个都在，才说明补丁真的写进去了。

---

## 第 3 步：刷入

准备：电量 50%+、**能传数据**的线、直插 Mac、拔掉 SIM 和 SD 卡、
`设置 → 存储和访问` 里关掉「USB 大容量存储」。

```bash
./bb10mt flash -i build/Z30_10.3.03.3216_STA100-1-2-3-4-5-6_os.exe
```

终端会停在等设备。这时候：**手机关机 → 插线**。
（30 秒没反应就按住电源键开机，保持插线。）

刷完 `_os.exe` 时屏幕可能是黑的、或者闪红灯，**这是正常的**，别拔线也别重刷。
接着立刻刷 radio：

```bash
./bb10mt flash -i build/Z30_10.3.03.3216_STA100-1-2-3-4-5-6_radio.exe
```

两个都刷完，手机自动重启，直接进系统（初始化向导已经被 `patch.txt` 里的 `tutorials_*_done` 跳过了）。

---

## 第 4 步：确认 root 成功

1. 开机 1~2 分钟后，通知栏会弹 root 成功提示
2. 桌面上会出现 **Term49**
3. SSH 验证：

```bash
ssh -i id_rsa4x devuser@169.254.0.1
# 密码留空，用密钥登录
```

进去之后：

```
$ id
uid=1000(devuser) gid=1000 ...
$ __root id
uid=0(root) gid=0 ...
```

`__root id` 输出 `uid=0` 就是拿到了。

---

## 出问题怎么办

| 现象 | 原因 | 处理 |
|---|---|---|
| `flash` 一直等设备 | 手机在正常系统里，没进 bootrom | 关机再插线，或按住电源键开机保持插线 |
| 刷完 `_os.exe` 报错 | 官方文档明确说**正常**，会提示一个 error | 忽略，接着刷 `_radio.exe` |
| 开机后没有 root 提示 | 用错包 / patch.txt 没生效 | 看 batch 日志有没有 `use.root` 那行，重跑 batch |
| 开机卡在 BB10 logo 转圈 | user 分区和系统版本不匹配 | 重新下 3216 的包重做，别混版本 |
| 红灯长闪不停 | 刷机中断或线有问题 | 用**官方原包**重刷一遍（官方包就是最好的救砖工具） |

官方原包重刷：

```bash
./bb10mt flash -i autoloader/Z30_10.3.03.3216_STA100-1-2-3-4-5-6.exe
```

---

继续 → [05 · Root 之后玩什么](05-post-root.md)
