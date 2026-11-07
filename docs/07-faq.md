# 07 · 常见问题

---

**Q：Mac 真的能刷吗？网上都说必须要 Windows。**

能。这个说法在 2015 年成立，因为 autoloader 是个 Windows 的 `.exe` 自解压程序。
但 2026 年的 `bb10mt` 有 macOS 原生二进制，能直接跟 bootrom 通信，
做的事和 Windows 上的 `cap.exe` 完全一样。本仓库就是干这个的。

---

**Q：我的机器是 Intel Mac，能行吗？**

能。包里带 `bb10mt_x64_darwin`，`./bb10mt` 会自动按 `uname -m` 选对应版本。

---

**Q：刷完还能用 BBID 吗？还能收到推送吗？**

不能。BBID、BlackBerry World、BBM、天气、邮件推送，2022 年 1 月 4 日全部关停。

刷机后你的 BB10 是：一台能打电话、发短信、拍照、听歌、装本地应用的**功能机**。
邮件可以手动配 IMAP/Exchange，网页勉强能用（浏览器内核太老，很多站点打不开）。

**心态要摆正：这不是「恢复智能机体验」，这是「让老设备重新能用」。**

---

**Q：root 之后能装 Android 应用吗？**

能跑一部分。BB10 内置了 Android Runtime（10.3 是 Android 4.3 级别的 ART），
可以装 `.apk`，但要求 API 级别低、不依赖 Google 服务、不强依赖硬件特性。

root 本身**不会**提升兼容性，也不会升级 Runtime 版本。网上说的「root 后能跑 Android」是夸大的。

---

**Q：能让它跑新的 Android 系统吗？**

不能。BB10 的 bootloader 到今天都没被破解，os 分区有签名校验，改不了。

能跑 mainline Linux 的是 **BlackBerry KEY2**（安卓机，靠 CVE-2021-1931 解锁），
和 BB10 完全是两码事，别搞混。

---

**Q：值不值得折腾？**

看你要什么。

- 想救活一台抽屉里的 Passport/Classic，当备用机打电话打字 → **值得**，刷机 20 分钟的事
- 想拿它当主力机 → **不值得**，2026 年了，别为难自己
- 想研究 QNX / 嵌入式安全 → **非常值得**，BB10 是个绝佳样本

---

**Q：为什么 root 了还是删不掉预装的 Facebook/Twitter？**

因为它们在 **os 分区**（只读 + 签名校验），不是 user 分区。

唯一办法是在**生成 root 包时**用 `patch.txt` 的 `removeapp` 删掉，然后重刷。
事后想删只能重刷。

---

**Q：系统里找不到 AppWorld / 黑莓世界，有影响吗？**

分两层看：

- **当商店用**：没影响。2022 年 1 月 4 日就停服了，图标点开也是白屏或者报网络错误。
- **当 root 跳板用**：有影响，**这个应用绝对不能删**。

v4 的动态库劫持是这样的：把 `libslog2.so.1` 塞进
`/apps/sys.appworld.<hash>/native/lib/`，只有当 **AppWorld 进程启动**时，
这个库才会被加载，加载时才执行「拉起 sshd、放开 root 权限」那段代码。

所以「图标看不见」和「应用不存在」是两件事 —— 图标没了无所谓，
`/apps/sys.appworld.*` 这个目录必须留着。

自查一下：

```bash
./scripts/bbssh "ls /apps/sys.appworld*/native/lib/"
# 正常应该有 libslog2.so.1
```

**重启后 SSH 连不上**（AppWorld 没自启时会出现）：
在手机上手动打开一次 BlackBerry World，哪怕它报网络错误、白屏，
触发链跑完 sshd 就起来了，再连就行。

真删了/刷坏了：把工具自带的 `patchdata/appworld.bar` 推回设备重装，
或者重新生成 root 包重刷一遍。

---

**Q：刷机会掉运营商锁吗？**

不会。SIM 锁在 NVRAM 里，和系统无关。

root 之后可以用 `mod_nvram -u` 解锁，但**这是玩命操作** ——
参数错了 NVRAM 就废了，手机变砖且不可恢复。作者本人都搞死过一台。

---

**Q：我能刷其他机型的固件吗？**

**绝对不能。** 尤其这三个：

- Z10 **STL100-1**（TI OMAP 芯片）≠ 其他 Z10（高通）
- **Z3** 独一份
- **Passport** 独一份

刷错 = 开机都开不了 = 基本报废。

---

**Q：刷坏了怎么办？**

只要还能进 bootrom，重刷官方包就行 —— **官方包本身就是最好的救砖工具**。

真砖（完全没反应）就只能换主板。所以刷之前一定确认包没下错。

---

**Q：`setup.sh` 为什么要编译 libusb？不能用 brew 装吗？**

能用 brew 装的话最省事：

```bash
brew install libusb lzo
```

但有两个问题：

1. Homebrew 的 `libusb` 装出来叫 `libusb-1.0.0.dylib`，而 `bb10mt` 找的是 `libusb.dylib`，得手动建软链
2. 某些环境（比如 CI、受限沙箱）里 Homebrew 跑不起来，只能源码编译

`setup.sh` 优先用 brew，装不了就自动 fallback 到源码编译。

---

**Q：我要备份吗？怎么备份？**

**要，而且刷机前必须做。**

BB10 官方的 `BlackBerry Link` 已经废了，实际可行的：

| 数据 | 方法 |
|---|---|
| 照片 / 视频 / 文档 | 拷到 SD 卡或电脑（USB 大容量存储模式） |
| 联系人 | 设置里导出 vCard，或者同步到 Google |
| 短信 | 基本没救，除非之前用 DBBT 备份过 |
| 应用数据 | root 后可以 `tar` 打包 `/accounts/1000/`，但恢复很麻烦 |

---

**Q：这项目还在更新吗？**

bb10.root.sx 的作者 2026 年 3 月说过「因为缺乏反馈暂停公开更新」，但 10 月又发了 v4。
目前是间歇性活跃。

想支持的话：Patreon 或者直接给他发反馈 —— 他是真的靠反馈才继续做的。

---

**Q：文档有错怎么办？**

提 Issue 或 PR。刷机流程里的坑非常多，欢迎补充你踩过的。
