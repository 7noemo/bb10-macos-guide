# 05 · Root 之后玩什么

拿到 root 之后，BB10 从「一块砖」变回「一台能折腾的机器」。
但要有心理预期：**这不是 Android，生态不会因为 root 就复活。**

---

## 一、终于能装应用了

BB10 的应用格式是 `.bar`。官方签名服务器 2022 年关停后，所有未签名的 bar 都装不上。

Root 之后有两层解锁：

1. `patch.txt` 已经改了 `/etc/system/config/sud.cfg`，把 installer 切成 `unsigned`
2. 系统里跑着 `btool`，它带着 launcher 补丁，跳过了 BAR 校验

所以现在**随便装**。

### 装 bar 的工具

#### Sachesi（推荐，macOS 有构建）

- 项目：<https://github.com/xsacha/Sachesi>
- macOS 版下载：<https://mac.softpedia.com/get/Utilities/Sachesi.shtml>
- 自己编译（需要 Qt5）：

```bash
brew install qt@5 libusb
git clone https://github.com/xsacha/Sachesi.git
cd Sachesi && qmake && make -j8
```

用法：`Install` 标签页 → 拖入 `.bar` 文件 → 输入设备密码 → 走 USB 网线装进去。

> Sachesi 顺便还能**提取 autoloader 里的组件**、备份/恢复设备、清空设备。
> 是 BB10 上最万能的图形工具，值得常备。

#### DBBT（Darcy's BlackBerry Tools）

Java 写的，macOS 能跑，需要装 JDK 8：

```bash
brew install --cask temurin@8
java -jar DBBT.jar
```

比 Sachesi 更偏底层，能解析 `.nbak` 备份、直接操作文件系统。

#### 命令行（进阶）

BB10 NDK 里的 `blackberry-deploy` 可以脚本化安装：

```bash
blackberry-nativepackager -devMode -package app.bar bar-descriptor.xml
blackberry-deploy -installApp -device 169.254.0.1 -password 你的密码 app.bar
```

适合批量、自动化。SDK 已停止分发，得去 archive.org 找。

---

## 二、Term49：手机上的终端

root 包里自带 **Term49**，位置：

```
/accounts/1000/shared/misc/Term49.bar
```

装上去之后你就有：

- 一个真正的 QNX shell
- Python 3（可以 `pip install` 纯 Python 包）
- 能跑 `btool`、`mod_nvram` 这些自带工具

用 Term49 配合 `__root`，等于手里有了一台小 Linux（其实是 QNX）。

---

## 三、SSH

默认已开启（`patch.txt` 里 `use.sshd`）。

```bash
# 默认私钥在 bb10-root/ 目录下（setup.sh 会放好）
chmod 600 id_rsa4x
ssh -i id_rsa4x devuser@169.254.0.1
```

| 项 | 值 |
|---|---|
| 地址 | `169.254.0.1`（USB 网线模式）或手机 WiFi IP |
| 用户 | `devuser` |
| 端口 | 22 |
| 提权 | `__root <命令>` |

**建议改成自己的密钥**，默认私钥是公开的，等于谁都能登。

进阶：SSH 的 host key 每次刷机都会变，客户端会报指纹变化警告。想固定的话，
在 `patch.txt` 里把 `ssh_host_rsa_key` 的 push 行取消注释，把你的 host key 一起打进去。

---

## 四、干掉亚马逊那套东西

BB10 后期版本预装了 Amazon Appstore 和一堆 Amazon 组件，占地方还老想联网。

root 之后可以直接关掉「允许安装其他来源应用」的策略：

```bash
mkdir -p /var/pps/system/perimeter/settings/1000-personal
cat > /var/pps/system/perimeter/settings/1000-personal/policy <<'EOF'
@policy
policy_block_apps_install_other_sources::1
EOF
```

重启后 Amazon Appstore 就装不了东西了。

想彻底删组件，得改 os 分区 —— **做不到**（bootloader 校验）。只能靠 `patch.txt` 的 `removeapp` 在生成阶段删。

---

## 五、btool：v4 的全能小工具

v4 把 `btool` 整个用 C 重写了，稳定性比之前好很多。它集成了：

| 功能 | 用途 |
|---|---|
| `pathtrust` patcher | 往信任白名单里加程序 |
| `launcher` patcher | 关掉 BAR 签名校验 |
| NVRAM backup | 备份/恢复 NVRAM（**改之前一定先备份**） |
| `mod_nvram -u` | 运营商解锁 |
| `mod_nvram -d` | 降级 |

⚠️ **`mod_nvram` 是玩命工具。** 参数写错 = NVRAM 损坏 = 手机变砖且不可恢复（作者就这么搞死过一台）。
不确定就别碰。

---

## 六、社区应用现状

BB10 的原生开发生态基本停了，但还有零星项目：

| 项目 | 说明 |
|---|---|
| **BerryCore** | 社区维护的基础库和补丁集合，不 root 也能跑 |
| **Berry Browser** | 基于旧 WebKit 的浏览器，能勉强打开现代网页 |
| **K12KB** | 硬件键盘输入法，解决 Gboard 不收起的问题 |
| **Term49** | 终端 + Python，root 包里已带 |

想自己写原生应用：BB10 SDK 已经停止分发，得去 archive.org 找 Momentics，配合 root 后的未签名安装能力才能部署到自己机器上。

---

## 七、想回退？

**回退 = 重刷官方包。** 没有「卸载 root」这回事。

```bash
./bb10mt split -i autoloader/官方包.exe -o revert
./bb10mt flash -i revert/xxx.0.signed
./bb10mt flash -i revert/xxx.1.signed
```

刷完就是干净的官方系统，root 痕迹全无（因为整个 user 分区被覆盖了）。

继续 → [06 · 排错](06-troubleshooting.md)
