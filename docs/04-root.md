# 04 · 注入 Root（AutoRoot v4）

BB10 一直没有公开的 root 方案，直到 2026 年 [bb10.root.sx](https://bb10.root.sx/) 的作者 Oleksandr 把链条打通。
当前版本是 **AutoRoot v4**（2026-10-22）。

本仓库的 `setup.sh` 已经把工具下好了，这一节只讲怎么用。

---

## 一、为什么 BB10 能 Root（简述）

不感兴趣可以跳过，但知道原理有助于排错。

BB10 的安全模型里，**所有应用必须由黑莓服务器签名**才能安装。
2022 年签名服务器关停后，等于任何人都装不了新应用 —— 包括你自己写的。

Oleksandr 找到的突破口有几层：

1. **`install_apk` 命令不校验签名**
   系统安装器在处理 `install_apk` 类型的请求时，直接跳过了 `bar.checksigs()` 校验。
   而且 `Package-Id` 以 `andrB` 开头的包也会跳过校验。

2. **`sud.cfg` 可以被改**
   `/etc/system/config/sud.cfg` 里把 installer 模块改成 `unsigned`，整个签名校验就关了。

3. **pathtrust 白名单里混进了 Android 子系统的文件**
   系统只允许 pathtrust 里的程序以 root 运行，但黑莓自己把 Android 子系统的脚本加进去了。
   通过**符号链接替换**，可以让一个普通脚本以 root 身份执行。

4. **动态库劫持（v4 新增）**
   v4 改用 `LD_LIBRARY_PATH` 劫持已签名应用的加载路径，实现了**重启后依然保持 root**。

**能改的只有 user 分区**，os 和 radio 分区由 bootloader 校验，改不了。
所以这不是 bootloader 解锁，也不能装别的系统 —— 它只是「在现有系统上拿到 root」。

---

## 二、前提条件

| 条件 | 要求 |
|---|---|
| OS 版本 | **必须是 10.3.3.3216** |
| 磁盘空间 | 生成过程需要 **10 GB 以上** |
| 手机状态 | 已刷好官方 3216，能正常开机 |

版本不对？回去看 [03 · 刷机](03-flash.md)，先刷到 3216 再说。

> 官方原话：*AutoRoot v3/v4 主要在 10.3.3.3216 上验证。低于 10.2.1 可能完全不工作，其他版本不保证。*

---

## 三、生成 Root 包

```bash
cd bb10-root

./bb10mt batch \
  -i autoloader/Passport_10.3.03.3216_SQW100-1-2-3-4.exe \
  -s patch.txt \
  -o build
```

参数说明：

| 参数 | 含义 |
|---|---|
| `-i` | 官方 autoloader，必须是**和你手机版本一致**的 3216 包 |
| `-s` | 补丁脚本，就是 `patch.txt` |
| `-o` | 输出目录 |
| `-c` | 可选，压缩镜像，能显著减小体积（但刷得更慢） |

过程大概 5~15 分钟，中途会解出 3 GB 的 `.ifs` 和 `.rcfs` 再重新打包，**别中断**。

### 产物

```
build/
├── Passport_...._os.exe      ← 打好补丁的系统镜像 ★
├── Passport_...._radio.exe   ← radio 包 ★
└── （一堆中间文件，可以删）
```

只留这两个星标的，其他都可以删掉腾空间。

---

## 四、刷入

顺序**不能变**：先 `_os.exe`，再 `_radio.exe`。

```bash
# 1. 刷系统
./bb10mt flash -i build/Passport_...._os.exe

# 2. 刷 radio
./bb10mt flash -i build/Passport_...._radio.exe
```

操作手法和 [03 · 刷机](03-flash.md#第-2-步让手机进-bootrom) 完全一样：
命令挂起等设备 → 手机关机 → 插线 → 开机。

> `_os.exe` 刷完会闪红灯或者直接黑屏，这是**正常的** —— 因为 radio 还没刷。
> 别以为失败了去重刷，直接接着刷 `_radio.exe`。

> 如果 `flash` 报不认识 `.exe` 格式：
> ```bash
> ./bb10mt split -i build/xxx_os.exe -o build/os-split
> ./bb10mt flash -i build/os-split/xxx.0.signed
> ```

---

## 五、验证 Root

刷完重启，走完初始化（root 包已经内置了跳过初始化的补丁），等 1~2 分钟。

**成功标志：通知栏弹出 root 成功提示。**

再验证一下：

```bash
# 注意：sshd_config 里是 AllowUsers=root，登录名就是 root，不是 devuser
# macOS 自带 ssh 太新（OpenSSH 10 已移除 ssh-rsa），用仓库里的封装脚本
./scripts/bbssh "id; ls /var/rootdata"
```

`__root` 和 `u_root` 这两个 helper 就是提权入口，已经自动加进 pathtrust 了。root 登录后直接就是 uid=0。

---

## 六、patch.txt 配置

`patch.txt` 决定了 root 包里塞什么、删什么、开什么。改完重跑 `batch` 即可，不用重刷官方包。

### 默认配置

```text
# 开启基础 root helper（__root / u_root）
touch /var/rootdata/use.root

# 开机自动以 root 启动 SSH
touch /var/rootdata/use.sshd

# BerryCore 应用以 root 运行（默认关闭）
#touch /var/rootdata/use.berrycore
```

### 常用改法

**关掉 SSH**（不想留后门，更安全）：

```diff
-touch /var/rootdata/use.sshd
+#touch /var/rootdata/use.sshd
```

**换自己的 SSH 公钥**：

把公钥放进 `patchdata/var/etc/ssh/authorized_keys2`，然后取消这几行的注释：

```sh
push "patchdata/var/etc/ssh/authorized_keys2" "/var/etc/ssh/authorized_keys2"
chmod 644 "/var/etc/ssh/authorized_keys2"
chown 0:0 "/var/etc/ssh/authorized_keys2"
```

**少删点预装应用**：

默认会删掉这些：

```text
removeapp com.twitter com.evernote com.linkedin com.tcs.maps com.rim.bb.app.facebook ...
removeapp sys.retaildemo sys.socialconnect.* sys.cfs.box sys.cfs.dropbox sys.uri.youtube
```

反正服务器都死了，留着也打不开，一般没必要改。

### ⚠️ 两个致命禁忌

1. **绝对不要**把 `sys.appworld` 加进 `removeapp`
   v4 的提权链是靠 AppWorld 这个应用做跳板的，删了 root 直接失效。

2. **不要**改 `push "patchdata/apps" "/apps"` 这类基础行
   除非你很清楚自己在干什么。

---

## 七、升级已有 Root（不重刷）

如果你已经在跑 v2/v3，作者给贡献者提供了免刷升级脚本 `v2tov4.sh` / `v3tov4.sh`。
普通用户拿不到，得去 Patreon 支持一下或者直接重刷。

---

继续 → [05 · Root 之后玩什么](05-post-root.md)
