# 09 · 安装未签名的 BAR

> 前提：已经按 [04 · 注入 Root](04-root.md) 刷好 root 包，`./scripts/bbssh` 能登进去。
> 本文所有命令都在**真机**（Classic SQC100-3 / 10.3.3.3216）上验证过。

---

## 一、为什么 root 后就能装未签名应用

BB10 的安全模型是「所有应用必须由黑莓服务器签名」。2022 年签名服务器关停，
等于官方渠道彻底死掉 —— 这也是社区应用装不上的根本原因。

root 包在生成时改了 `/etc/system/config/sud.cfg`：

```text
[platform]
[installer]
module = unsigned
```

这一行让系统安装器**不再要求签名**。也就是说安装器本身还在，只是不查签名了。

> 注意：这不是「破解安装器」，而是把安全模块的判定改成 `unsigned`。
> 所以装进去的应用只要自己能被加载器跑起来，就能用。

---

## 二、先搞清楚：哪个 installer 才是真的

刷完 root 你会看到 `/var/rootdata/installer`，**它不是系统安装器**。

```bash
./scripts/bbssh "/var/rootdata/installer /var/rootdata/Term49.bar"
# Archive extracted successfully to: /var/tmp/extract_xxxx
# Initializing addon: /var/addons/unknown_package
# Installation completed successfully.        ← 骗你的，应用列表里啥也没有
```

它只是 AutoRoot 自带的一个解包器，把包摊到 `/var/addons/` 就算完事。
用它装 bar 会得到一个「看起来成功、实际没注册」的假象。

**真正的安装通道是 PPS job 文件**，也就是系统 `installer` 服务监听的那个目录：

```text
/pps/system/installer/upd/current/job.<任意名字>
```

往里写三行，系统就会去装：

```text
action::install
package_location::<bar 的绝对路径>
extras::
```

装完它会回写状态，看到 `progress::100` 就是成功；失败会写
`result::failure 500 <原因>`。

---

## 三、用脚本装（推荐）

仓库里带了一个封装好的 `scripts/bbinstall`，把它和 `bbssh` 放一起：

```bash
cp scripts/bbinstall scripts/bbssh bb10-root/
cd bb10-root
chmod +x bbinstall
```

### 安装

```bash
./bbinstall ~/Downloads/bPod.bar
```

输出长这样：

```text
→ 包名: com.example.bbtest
→ 包 ID: gYABgBBTESThv9R9Lxhnmfhpr9Hi
→ 签名: 无签名（靠 sud.cfg unsigned 放行）
→ 目标: /var/rootdata/bPod.bar
↑ 上传中 (2.9 MB) ...
✓ 上传完成
✓ 已提交安装任务

--- job 状态 ---
@job.bPod.bar
action::install
attempt::1
extras::
package_location::/var/rootdata/bPod.bar
progress::100
--- 安装目录 ---
/apps/com.example.bbtest.gYABgBBTESThv9R9Lxhnmfhpr9Hi

✓ 安装成功
```

### 列出已装的非系统应用

```bash
./bbinstall -l
```

### 卸载

```bash
./bbinstall -r com.example.bPod        # 给包名或包 ID 都行
./bbinstall -r ~/Downloads/bPod.bar    # 给 bar 文件也可以，会自动读 ID
```

---

## 四、不用脚本，手动装

只有三步，理解了就不怕翻车。

```bash
# 1. 把 bar 传上去（用 sftp / 或者手机 USB 大容量存储模式拷到 /var/rootdata）
#    这里假设已经在 /var/rootdata/bPod.bar

# 2. 写 job（注意 package_location 必须是绝对路径）
./scripts/bbssh "print 'action::install\npackage_location::/var/rootdata/bPod.bar\nextras::' > /pps/system/installer/upd/current/job.bPod.bar"

# 3. 等十几秒看结果
./scripts/bbssh "cat /pps/system/installer/upd/current/job.bPod.bar"
```

`progress::100` = 装好了；`result::failure 500 xxx` = 被拒，原因就在后面。

装完确认：

```bash
./scripts/bbssh "ls -d /apps/com.example.bPod.*"
```

> BB10 的应用目录命名是 `<Package-Name>.<Package-Id 里的 - 换成 .>`，
> 不是纯 Package-Id，所以别拿 ID 直接去 `ls /apps/<id>`，会找不到然后误判失败。

### 卸载（手动）

```text
action::uninstall
package_id::<包 ID>
extras::
```

同样写进 `job.<随便什么名字>`，等几秒 `ls` 确认目录没了。

---

## 五、bar 从哪来

BlackBerry World 已经关了，现在只有这几类来源：

| 来源 | 说明 |
|---|---|
| GitHub | 搜 `bb10 bar`、`blackberry 10 app`，社区作者会把 bar 挂在 Release 里 |
| archive.org | 有人整站备份过 BlackBerry World，注意包可能是 2013~2015 年的老版本 |
| bb10.root.sx | root 工具作者自己的页面，附了几个常用工具（Term49 等） |
| 自己打包 | Momentics / `blackberry-nativepackager` 能打，但要 2018 年的旧 SDK |

拿到手先确认它是不是 **BB10 的 bar**：

```bash
unzip -p xxx.bar META-INF/MANIFEST.MF | grep -E "Package-Name|Package-Architecture|Package-Type"
```

- `Package-Architecture: armle-v7` → BB10 用（BB10 是 ARMv7）
- `Package-Type: application` → 应用
- 如果架构是 `x86` 或包里带 `wrt/` 大量 JS，多半是 PlayBook 或纯 WebWorks 包，能装但不一定能跑

---

## 六、装上了但打不开？

按概率排：

| 现象 | 原因 |
|---|---|
| 应用列表里没图标 | 桌面没刷新。下拉通知栏再收起，或者重启手机 |
| 图标在，点了闪退 | 应用依赖 BBID / 黑莓服务（推送、地图、支付），服务端早就没了 |
| 点了没反应 | 架构不对（PlayBook 包），或者缺少它依赖的运行时 |
| 装的时候就 `result::failure` | 包 ID 冲突、版本号回退、包结构不合法 |

**判断依据**：只要 `/apps/<包名>.<包ID>` 目录在，文件齐全，就是装成功了 ——
打不开是应用自身依赖的问题，跟签名、跟 root 都没关系。

---

## 七、实测记录（2026-11-07）

在 Classic SQC100-3 / 10.3.3.3216 上验证了三条：

1. 剥掉 `META-INF/*.SF`、`*.EC` 的 Term49 包（完全无签名），用 PPS job 安装 →
   系统接受，因为版本号与已装版本相同，没有实际覆盖
2. 同一个包改包名 / 包 ID 后变成「全新应用」→ `progress::100`，
   `/apps/com.example.bbtest.<id>` 建好，桌面出现图标 → **未签名安装成立**
3. `action::uninstall` + `package_id::<id>` → 目录被删除，卸载成立

失败的写法也记一下，省得踩：

| 写法 | 结果 |
|---|---|
| `/var/rootdata/installer xxx.bar` | 假成功，解到 `/var/addons/`，不注册 |
| `action::remove` | `result::failure 500 unsupported action: remove` |
| job 文件不 `chmod 666` | 安装器能读，但删不掉自己的 job，残留垃圾文件 |

---

继续 → [06 · 排错手册](06-troubleshooting.md)
