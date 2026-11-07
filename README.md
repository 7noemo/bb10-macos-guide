# 黑莓 BB10 · macOS 刷机与 Root 指南

> 在 Mac 上给黑莓 BB10 手机刷固件、注入 Root 的完整中文教程。
> **全程不需要 Windows，不需要虚拟机，不需要 CrossOver。**

---

## 为什么写这个

网上所有 BB10 教程都写着「autoloader 是 Windows only，Mac 用户去找台 Windows 电脑」。

这句话在 2014 年是对的 —— 因为 autoloader 本质上是一个 `.exe` 自解压程序，里面打包了黑莓的刷机引擎 `cap.exe`。

但 2026 年的情况变了：社区工具 `bb10mt` 已经提供了 **macOS 原生二进制**（Intel 和 Apple Silicon 都有），
它能直接跟设备的 bootrom 通信、把镜像写进去。也就是说 `cap.exe` 干的事，Mac 现在也能干。

唯一的坑是：官方压缩包里**没带** macOS 版的 `libusb` 和 `liblzo2` 动态库，
直接双击运行会报 `Couldn't load dynamic library libusb`。
本仓库的 `scripts/setup.sh` 会自动把这两个库编译好并配好环境。

---

## 五分钟快速开始

```bash
git clone https://github.com/7noemo/bb10-macos-guide.git
cd bb10-macos-guide

# 一键准备环境（下载工具 + 编译依赖，约 3 分钟）
./scripts/setup.sh

# 检查环境和设备
./bb10-root/bb10mt --version
./bb10-root/bb10mt info
```

然后按顺序读：

| 步骤 | 文档 | 你会得到 |
|---|---|---|
| 1 | [确认机型和版本](docs/01-check-device.md) | 知道自己该下哪个包 |
| 2 | [下载固件](docs/02-firmware.md) | 一个 2~3 GB 的 autoloader |
| 3 | [在 Mac 上刷机](docs/03-flash.md) | 手机回到官方 10.3.3.3216 |
| 4 | [注入 Root](docs/04-root.md) | 能装未签名 BAR 的 BB10 |
| 5 | [Root 之后玩什么](docs/05-post-root.md) | 终端、SSH、第三方应用 |
| 6 | [出问题了](docs/06-troubleshooting.md) | 对症下药 |
| 7 | [常见问题](docs/07-faq.md) | 你可能会问的 |
| 8 | [Classic / Q20 实机记录](docs/08-classic-q20.md) | **一台 SQC100-3 从零刷到 root 的完整实录**（含所有坑） |

### 已在真机验证

2026-11，BlackBerry Classic `SQC100-3`（OS 10.3.3.3216）在本仓库流程下成功 root：

```
QNX BLACKBERRY-6B84 8.0.0 MSM8960_V3.2.1.1_N_CLASSICVZW_Rev:12 armle
/var/rootdata: use.root  use.sshd  Term49.bar  installer
```

实测有三个官方文档没写的坑，都记在 [08 篇](docs/08-classic-q20.md) 里：

1. **loader 缺失**：`loaders.dat` 里没有 SQC100-3 的 loader，需要借 SQC100-2 的改名
2. **不能刷 `_os.exe`**：bb10mt 处理不了自建 exe，要刷拆分出来的 `0.unsigned`
3. **OS 和 radio 必须一条命令一起刷**，否则设备刷完不启动

另外 root 登录名是 **`root`** 不是 `devuser`，而 macOS 自带的 OpenSSH 10 已经
连不上 BB10 的 OpenSSH 6.2 了 —— 用仓库里的 `scripts/bbssh`。

---

## 这套东西能做什么、不能做什么

**能**

- 把任何版本的 BB10 刷回官方 10.3.3.3216
- 救回卡开机、卡初始化、无限重启的手机（硬件没坏的前提下）
- 获取 root，绕过 BAR 签名校验，安装 2022 年后社区新写的应用
- 开 SSH，把手机当一台 QNX 小机器用
- 移除预装的 Twitter / Facebook / LinkedIn / Amazon 等一堆死掉的服务

**不能**

- 不能装 Android 系统，不能升级 Android Runtime
- 不能解锁 bootloader（BB10 的 bootloader 至今没人破）
- 不能让 BBID、BlackBerry World、天气、BBM 这些官方服务复活
  （社区在重定向到自建服务器，但目前没有公开可用版本）

---

## 风险提示

刷机会**清空手机全部数据**，且存在**变砖**的可能。

BB10 没有公开的 EDL / 9008 救砖通道，刷错机型 = 基本只能换主板。
作者本人在开发 Root 方案的过程中就搞死过一台测试机（NVRAM 覆写）。

**建议只拿备用机折腾。** 主力机、有重要数据的机器，别碰。

---

## 环境要求

- macOS 12 以上（Intel / Apple Silicon 都行）
- Xcode Command Line Tools（`xcode-select --install`）
- 10 GB 以上空闲磁盘（生成 root 包时需要）
- 一根**能传数据**的 USB 线（很多劣质线只能充电，这是刷机失败第一大原因）

---

## 致谢

本仓库只是把别人的成果串起来，核心工作都不是我做的：

- **[bb10.root.sx](https://bb10.root.sx/)** — Oleksandr（bb10root）的 BB10 Root 研究，以及 `bb10mt` 工具。
  他的研究成果是整个 2026 年 BB10 社区能继续玩下去的唯一原因。有条件的话去 [Patreon](https://www.patreon.com/c/Oleksandr__) 支持一下。
- **thurask / CrackBerry** — [BlackBerry OS Archive](https://forums.crackberry.com/showthread.php?t=943672)，全机型官方固件存档。
- **[pb-appstore.netlify.app](https://pb-appstore.netlify.app/resources)** — 固件镜像与初始化跳过技巧。
- **[archive.org · BlackBerry 10 Autoloaders](https://archive.org/details/blackberry10-autoloaders)** — 56 GB 历史固件归档。

本仓库**不重新分发**任何第三方二进制，`setup.sh` 全部从上游官方地址下载。

---

## License

文档与脚本以 MIT 发布。第三方工具版权归各自作者，使用前请阅读其原始许可
（BB10 Root 项目明确声明：**仅供学习研究，未经授权禁止商用**）。
