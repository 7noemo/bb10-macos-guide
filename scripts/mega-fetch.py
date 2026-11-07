#!/usr/bin/env python3
"""备用下载器：走本机代理从 MEGA 拉固件，自动换节点续传。

为什么需要它：
  MEGA 的下载直链是 **IP 绑定** 的，换出口 IP 立刻 403，同一 IP 下满额度就 509。
  浏览器/普通 curl 下 1.5 GB 基本必挂。这个脚本把「切节点 → 取直链 → 下载」
  绑在一起，出错就换下一个节点，靠 Range 续传。

用法：
  python3 scripts/mega-fetch.py \
      --url "https://mega.nz/file/tVgyjDYS#ojnru-l0Apt1289OrZ7zDkvvxzFtfCIkAU1dIybpHK0" \
      --out ./Z30_3216.7z \
      --proxy http://127.0.0.1:7890 \
      --controller http://127.0.0.1:9000 \
      --node "中国香港-HK-1-流量倍率:0.7"

说明：
  --controller 是 Clash/mihomo 的外部控制接口（config.yaml 里 external-controller）。
  不传 --node 就用当前节点，遇到 403/509 会自动在 proxy-groups 里轮换。
  只依赖 Python 标准库 + openssl。
"""
import argparse
import base64
import json
import os
import re
import subprocess
import sys
import time
import urllib.request


def parse_link(link):
    """从 mega 链接里取出 handle 和 key。"""
    m = re.search(r"mega\.nz/(?:file|folder)/([A-Za-z0-9_-]+)#([A-Za-z0-9_-]+)", link)
    if not m:
        m = re.search(r"mega\.nz/#[!F]!([A-Za-z0-9_-]+)!([A-Za-z0-9_-]+)", link)
    if not m:
        sys.exit("无法解析链接，请确认是 https://mega.nz/file/<handle>#<key> 形式")
    return m.group(1), m.group(2)


class MEGA:
    def __init__(self, proxy):
        self.opener = urllib.request.build_opener(
            urllib.request.ProxyHandler({"http": proxy, "https": proxy} if proxy else {})
        )

    def api(self, payload, handle):
        req = urllib.request.Request(
            "https://g.api.mega.co.nz/cs?id=%d&n=%s" % (int(time.time()), handle),
            data=json.dumps(payload).encode(),
            headers={"Content-Type": "application/json"},
        )
        r = json.loads(self.opener.open(req, timeout=60).read())
        if isinstance(r, list) and r and isinstance(r[0], dict):
            return r[0]
        raise RuntimeError("MEGA API 返回异常: %r" % (r,))

    def open(self, url, pos):
        req = urllib.request.Request(url, headers={"Range": "bytes=%d-" % pos})
        return self.opener.open(req, timeout=120)


def set_node(controller, node):
    if not controller or not node:
        return
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    req = urllib.request.Request(
        controller.rstrip("/") + "/proxies/Proxy",
        data=json.dumps({"name": node}).encode(),
        headers={"Content-Type": "application/json"},
        method="PUT",
    )
    try:
        opener.open(req, timeout=10).read()
    except Exception as e:
        print("  ! 切换节点失败（忽略）: %s" % e)


def nodes_of(controller):
    if not controller:
        return []
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    try:
        d = json.loads(opener.open(controller.rstrip("/") + "/proxies/Proxy", timeout=10).read())
        return [n for n in d.get("all", []) if n not in ("Proxy", "Auto", "DIRECT", "REJECT")]
    except Exception:
        return []


def decrypt_file(src, dst, key_b64):
    """MEGA 的数据密钥是 key[0:16] XOR key[16:32]，IV = key[16:24] + 8 字节 0。"""
    key = base64.urlsafe_b64decode(key_b64 + "=" * ((4 - len(key_b64) % 4) % 4))
    if len(key) != 32:
        sys.exit("密钥长度不对（应为 32 字节）")
    aes = bytes(a ^ b for a, b in zip(key[:16], key[16:32]))
    iv = key[16:24] + b"\0" * 8
    subprocess.run(
        ["openssl", "enc", "-d", "-aes-128-ctr", "-K", aes.hex(), "-iv", iv.hex(),
         "-in", src, "-out", dst],
        check=True,
    )


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", required=True, help="mega 文件链接（含 #key）")
    ap.add_argument("--out", required=True, help="输出文件名（解密后）")
    ap.add_argument("--proxy", default="http://127.0.0.1:7890")
    ap.add_argument("--controller", default="http://127.0.0.1:9000",
                    help="Clash/mihomo 控制接口，用于自动换节点")
    ap.add_argument("--node", default="", help="指定节点名，不填则自动轮换")
    ap.add_argument("--keep-encrypted", action="store_true")
    a = ap.parse_args()

    handle, key = parse_link(a.url)
    tmp = a.out + ".enc"
    mega = MEGA(a.proxy)

    pool = [a.node] if a.node else nodes_of(a.controller)
    if not pool:
        pool = [""]

    pos = os.path.getsize(tmp) if os.path.exists(tmp) else 0
    i = 0
    fails = 0
    total = None
    print("handle=%s 已下载=%d 字节" % (handle, pos))

    while total is None or pos < total:
        node = pool[i % len(pool)]
        set_node(a.controller, node)
        time.sleep(1)
        try:
            info = mega.api([{"a": "g", "g": 1, "ssl": 1, "p": handle}], handle)
            total = info["s"]
            resp = mega.open(info["g"], pos)
            with open(tmp, "ab") as f:
                mark = pos
                last = time.time()
                while True:
                    buf = resp.read(1 << 20)
                    if not buf:
                        break
                    f.write(buf)
                    pos += len(buf)
                    if time.time() - last > 10:
                        sp = (pos - mark) / (time.time() - last) / 1024
                        print("  %.1f%%  %.2f/%.2f GB  %.0f KB/s  [%s]"
                              % (pos * 100.0 / total, pos / 1e9, total / 1e9, sp, node), flush=True)
                        mark, last = pos, time.time()
            if pos < total:
                raise RuntimeError("连接提前结束")
        except Exception as e:
            msg = str(e)
            print("  节点 %s 失败: %s" % (node, msg), flush=True)
            if any(k in msg for k in ("403", "509", "401")):
                i += 1
                fails = 0
            else:
                fails += 1
                if fails >= 3:
                    i += 1
                    fails = 0
                time.sleep(2)
            if i > len(pool) * 4:
                sys.exit("所有节点都失败，稍后再试（MEGA 免费额度按 IP 计算，等 6 小时或换网络）")

    print("下载完成: %s (%d 字节)" % (tmp, pos), flush=True)
    decrypt_file(tmp, a.out, key)
    if not a.keep_encrypted:
        os.remove(tmp)
    print("已解密: %s (%d 字节)" % (a.out, os.path.getsize(a.out)))


if __name__ == "__main__":
    main()
