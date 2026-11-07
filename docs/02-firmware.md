# 02 · 下载固件

BB10 的官方更新服务器 2022 年 1 月 4 日就关了，`Sachesi` 的在线搜索、`BlackBerry Link` 的在线更新全部失效。
现在只能下**别人存档好的 autoloader**。

---

## 一、先搞清楚你要下的是什么

**autoloader** = 官方给维修点用的离线刷机包。

它长这样：

```
Passport_10.3.03.3216_SQW100-1-2-3-4.exe     ← 2~3 GB
```

这个 `.exe` 的本质是：**刷机引擎（cap.exe）+ 拼接在后面的固件镜像**。
在 Windows 上双击运行，它检测到设备就开始刷。

在 Mac 上我们不运行它，而是用 `bb10mt` 把里面的镜像**拆出来**再刷。
所以这个 `.exe` 你**不需要能执行**，只需要能读。

> 这正是很多人卡住的地方：他们以为 Mac 上没法用这个 exe，就放弃了。
> 其实它只是个容器，Mac 完全能读。

---

## 二、去哪里下

按可信度排序。**能选前两个就别用后两个。**

### ① CrackBerry · BlackBerry OS Archive（首选）

<https://forums.crackberry.com/showthread.php?t=943672>

thurask 维护的全机型存档，最新完整版就是 **10.3.3.3216**。
文件托管在 MEGA，帖子第一页有完整的「机型 → 文件名」对照表。

每个版本同时提供：

| 文件 | 要不要 |
|---|---|
| `.7z` / `.zip` | ✅ 要，这就是 autoloader（解压后是 exe） |
| `OSINFO.txt` | ✅ 要，里面有每个文件的 SHA 校验值 |
| `.asc` | ❌ 不用，PGP 签名文件，校验用的，普通人可以忽略 |

### 10.3.3.3216 已知的直链和哈希（实测可用）

社区里流传的链接都是同一批，下面这份是 2026-11 实测能下通的：

| 机型 | 文件名 | 大小 | SHA-256（.7z） |
|---|---|---|---|
| **Z30 / Classic(Q20) / Leap** | `Z30_10.3.03.3216_STA100-1-2-3-4-5-6.7z` | 1,592,660,159 | `bae7cd04b5376e82aa85edbf915996e06d90cea3f6747cd99207b5354a3d57f8` |
| Q10 / Q5 / P9983 | `Q10_10.3.03.3216_SQN100-1-2-3-4-5.7z` | 1,569,051,774 | 见 OSINFO.txt |
| Passport | `Passport_10.3.03.3216_SQW100-1-2-3-4.7z` | 1,572,841,956 | 见 OSINFO.txt |

Z30 那份的 MEGA 直链（**密钥是完整的 43 字符，抄漏一个就解出乱码**）：

```
https://mega.nz/file/tVgyjDYS#ojnru-l0Apt1289OrZ7zDkvvxzFtfCIkAU1dIybpHK0
```

> 论坛帖子里的链接常被截断成 `...ojnru-l0A...CIkAU1dIybpHK0` 这种形式，
> 照着抄一定失败。看到 `...` 就当没看见，去原帖复制完整地址。

### ② pb-appstore · BB10 Resources（国内访问最稳）

<https://pb-appstore.netlify.app/resources>

按机型分好类的直链，覆盖 Z10 / Z3 / Z30 / Q5 / Q10 / Passport / Classic。
页面下方还有「初始化卡住怎么跳过 BBID」的完整攻略（很关键，见 [03 · 刷机](03-flash.md) 最后一节）。

### ③ archive.org 归档

<https://archive.org/details/blackberry10-autoloaders>

56 GB 的历史固件合集，版本最全（从 10.0 到 10.3.3 都有）。
缺点是下载慢，且需要自己在目录里翻。适合找老版本降级。

### ④ 第三方聚合站

比如 `firmware4mobile.com` 之类。能用，但**别信他们的校验值**，下载后自己核对。

---

## 三、下载技巧

### 大文件用 curl 断点续传

浏览器下 3 GB 容易断，断了还不能续。用命令行：

```bash
curl -L -C - -o Passport_10.3.03.3216_SQW100-1-2-3-4.exe "下载链接"
```

- `-C -` 断点续传，中断了再执行同一条命令就接着下
- `-L` 跟随重定向（MEGA / 网盘都需要）
- 没进度条想看得清楚可以加 `--progress-bar`

### 有代理就挂上

```bash
curl -L -C - --proxy http://127.0.0.1:7890 -o xxx.exe "链接"
```

MEGA 在国内直连基本废，走代理能快十倍。

### ⚠️ MEGA 的两个坑（下载 1.5 GB 必踩）

1. **直链是 IP 绑定的**。换节点 = 403，代理自动换 IP 也会 403。
   所以「先取链接、再切节点下载」一定失败，必须**同一个 IP 上取链接并下载完**。
2. **同一 IP 有免费额度**。下到一半报 `509 Bandwidth Limit Exceeded`，
   说明这个出口的额度用完了，换节点 + 用 Range 续传就行（MEGA 用 AES-CTR，密文和明文等长，任意字节都能独立续传）。

手动处理很痛苦，仓库里带了个脚本：

```bash
python3 scripts/mega-fetch.py \
  --url "https://mega.nz/file/tVgyjDYS#ojnru-l0Apt1289OrZ7zDkvvxzFtfCIkAU1dIybpHK0" \
  --out ./Z30_3216.7z
```

它会自动切节点、自动续传、下完自动解密（MEGA 的 key 前 16 字节还要和后 16 字节异或才是真正的 AES 密钥，这点和大部分教程写的不一样）。

实测：香港节点 2 MB/s，1.48 GB 用了 16 分钟，中途被换了 3 次节点。

### 7z 压缩包解压

⚠️ 这批 autoloader 的 7z 用了 **BCJ2 过滤器**，`py7zr`、macOS 自带 Archive Utility、部分老版本 7z 都解不了，会报 `UnsupportedCompressionMethod`。

```bash
# 官方 7-Zip 命令行版，arm64 原生
curl -L -o 7z.tar.xz https://www.7-zip.org/a/7z2301-mac.tar.xz
tar xf 7z.tar.xz
./7zz x Z30_10.3.03.3216_STA100-1-2-3-4-5-6.7z
```

Homebrew 能用的机器直接 `brew install sevenzip` 也行，图形界面用 [Keka](https://www.keka.io/) 也可以。

---

## 四、校验（强烈建议做）

第三方站点挂马、下错机型、下载损坏，三种情况都真实存在。花 30 秒校验一下：

### 方法 1：对 OSINFO.txt

下到的 `OSINFO.txt` 里长这样：

```
Passport_10.3.03.3216_SQW100-1-2-3-4.exe
SHA256: 3f8a...（一长串）
```

在 Mac 上：

```bash
shasum -a 256 Passport_10.3.03.3216_SQW100-1-2-3-4.exe
```

两个值一致才往下走。

### 方法 2：看大小

| 现象 | 判断 |
|---|---|
| 文件 < 1 GB | ⚠️ 不对，完整包至少 1.5 GB，大概率是假的或者只有一部分 |
| 双击没反应 / 提示要密码 | ⚠️ 可疑，正版 autoloader 不需要密码 |
| 文件名里没有你的型号编号 | ⚠️ 下错了 |

### 方法 3：看文件头（最硬核，也最准）

```bash
file Passport_10.3.03.3216_SQW100-1-2-3-4.exe
```

正常输出应该是 `PE32 executable (GUI) Intel 80386` 之类。
如果显示 `Zip archive` 或 `HTML document`，那就是下错了（很多网盘错误页会存成 .exe）。

---

## 五、放到哪

```bash
# 假设你已经 clone 了本仓库
cp ~/Downloads/Passport_10.3.03.3216_SQW100-1-2-3-4.exe bb10-macos-guide/bb10-root/autoloader/
```

目录里只放**一个**文件，避免后面命令写错路径。

---

继续 → [03 · 在 Mac 上刷机](03-flash.md)
