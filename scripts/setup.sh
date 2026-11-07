#!/usr/bin/env bash
#
# setup.sh — 在 macOS 上准备 BB10 刷机/Root 环境
#
# 干三件事：
#   1. 从 bb10.root.sx 下载 AutoRoot v4（bb10mt 工具 + 补丁数据）
#   2. 搞定 macOS 缺失的 libusb / liblzo2 动态库（优先 Homebrew，失败则源码编译）
#   3. 摆好目录结构，生成 bb10mt 启动器
#
# 用法：
#   ./scripts/setup.sh                # 直接跑
#   ./scripts/setup.sh --proxy URL    # 走代理下载
#   ./scripts/setup.sh --rebuild      # 强制重新编译依赖
#
set -euo pipefail

# ---------- 可调参数 ----------
AUTOROOT_URL="https://bb10.root.sx/blog/autoroot-v4/autoroot_v4.zip"
SSHKEY_URL="https://bb10.root.sx/downloads/id_rsa4x"
LIBUSB_VER="1.0.28"
LZO_VER="2.10"
LIBUSB_URL="https://github.com/libusb/libusb/releases/download/v${LIBUSB_VER}/libusb-${LIBUSB_VER}.tar.bz2"
LZO_URL="https://www.oberhumer.com/opensource/lzo/download/lzo-${LZO_VER}.tar.gz"

PROXY=""
FORCE_REBUILD=0

# ---------- 输出helper ----------
c_ok()   { printf '\033[32m✓\033[0m %s\n' "$*"; }
c_info() { printf '\033[36m→\033[0m %s\n' "$*"; }
c_warn() { printf '\033[33m!\033[0m %s\n' "$*"; }
c_err()  { printf '\033[31m✗\033[0m %s\n' "$*" >&2; }
die()    { c_err "$*"; exit 1; }

# ---------- 参数解析 ----------
while [ $# -gt 0 ]; do
  case "$1" in
    --proxy)   PROXY="${2:-}"; shift 2 ;;
    --rebuild) FORCE_REBUILD=1; shift ;;
    -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "未知参数：$1（用 --help 看用法）" ;;
  esac
done

# ---------- 路径 ----------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TARGET="$REPO_DIR/bb10-root"
CACHE="${BB10_CACHE:-$HOME/.cache/bb10-macos}"
BUILD="$CACHE/build"
TMP="$CACHE/tmp"

CURL_OPTS=(-fsSL --retry 3 --retry-delay 2)
[ -n "$PROXY" ] && CURL_OPTS+=(-x "$PROXY")

# 下载失败时自动换一种方式重试（有代理就去掉代理，没代理就试代理）
try_download() {
  local url="$1" out="$2"
  if curl "${CURL_OPTS[@]}" -o "$out" "$url"; then return 0; fi
  if [ -n "$PROXY" ]; then
    c_warn "走代理失败，改直连重试"
    if curl -fsSL --retry 3 --retry-delay 2 -o "$out" "$url"; then return 0; fi
  fi
  return 1
}

# ---------- 0. 基础检查 ----------
c_info "检查运行环境"

[ "$(uname -s)" = "Darwin" ] || die "这个脚本只支持 macOS"
command -v curl  >/dev/null || die "缺少 curl"
command -v unzip >/dev/null || die "缺少 unzip"
command -v xattr >/dev/null || true

ARCH="$(uname -m)"
case "$ARCH" in
  arm64) BIN_SUFFIX="aarch64_darwin" ;;
  x86_64) BIN_SUFFIX="x64_darwin" ;;
  *) die "不支持的架构：$ARCH" ;;
esac
c_ok "系统 $(sw_vers -productVersion) / $ARCH"

mkdir -p "$CACHE" "$BUILD" "$TMP" "$TARGET"/{bin,lib,autoloader,build}

# ---------- 1. 下载 AutoRoot v4 ----------
c_info "下载 AutoRoot v4（约 23 MB）"

ZIP="$CACHE/autoroot_v4.zip"
need_download=1
if [ -f "$ZIP" ] && [ "$(stat -f%z "$ZIP")" -gt 20000000 ]; then
  c_ok "已有缓存，跳过下载"
  need_download=0
fi

if [ "$need_download" -eq 1 ]; then
  try_download "$AUTOROOT_URL" "$ZIP" \
    || die "下载失败。网络问题可以试：./scripts/setup.sh --proxy http://127.0.0.1:7890"
  unzip -t "$ZIP" >/dev/null 2>&1 || { rm -f "$ZIP"; die "下载的压缩包损坏，已删除，请重跑"; }
  c_ok "下载完成（$(du -h "$ZIP" | cut -f1)）"
fi

c_info "解压"
SRC="$TMP/autoroot_v4.$$"
mkdir -p "$SRC"
unzip -q -o "$ZIP" -d "$SRC" || die "解压失败，压缩包可能损坏，删掉 $ZIP 重试"

[ -f "$SRC/patch.txt" ] || die "压缩包结构异常：找不到 patch.txt"

# ---------- 2. 摆放工具文件 ----------
c_info "安装 bb10mt"

cp "$SRC/bb10mt_${BIN_SUFFIX}" "$TARGET/bin/bb10mt-$ARCH.tmp"
mv "$TARGET/bin/bb10mt-$ARCH.tmp" "$TARGET/bin/bb10mt-$ARCH"
chmod +x "$TARGET/bin/bb10mt-$ARCH"

# Intel 机器同时留一份 x64，方便跨平台拷贝
if [ "$ARCH" = "arm64" ] && [ -f "$SRC/bb10mt_x64_darwin" ]; then
  cp "$SRC/bb10mt_x64_darwin" "$TARGET/bin/bb10mt-x86_64"
  chmod +x "$TARGET/bin/bb10mt-x86_64"
fi

cp "$SRC/patch.txt"    "$TARGET/patch.txt"
cp -R "$SRC/patchdata" "$TARGET/"

# loaders / ini 必须和二进制同目录，否则 bb10mt 会报 not found
cp "$SRC/bb10mt.ini"  "$TARGET/bin/"
cp "$SRC/loaders.dat" "$TARGET/bin/" 2>/dev/null || true
cp "$SRC/loaders.ini" "$TARGET/bin/" 2>/dev/null || true

c_ok "工具文件就位"

# ---------- 3. 依赖动态库 ----------
c_info "准备 libusb / liblzo2"

have_libusb() { ls "$TARGET/lib"/libusb*.dylib >/dev/null 2>&1; }
have_lzo()    { ls "$TARGET/lib"/liblzo2*.dylib >/dev/null 2>&1; }

if [ "$FORCE_REBUILD" -eq 0 ] && have_libusb && have_lzo; then
  c_ok "动态库已存在，跳过"
else
  got_libusb=0
  got_lzo=0

  # --- 已经用 brew 装过就直接拿来用（不去联网装，避免卡住） ---
  if command -v brew >/dev/null 2>&1; then
    brew list --formula libusb >/dev/null 2>&1 && c_info "检测到 Homebrew 的 libusb"
    brew list --formula lzo    >/dev/null 2>&1 && c_info "检测到 Homebrew 的 lzo"
    for d in /opt/homebrew/lib /usr/local/lib; do
      [ -d "$d" ] || continue
      for f in "$d"/libusb-1.0.?.dylib; do
        [ -f "$f" ] && cp "$f" "$TARGET/lib/" && got_libusb=1
      done
      for f in "$d"/liblzo2.?.dylib; do
        [ -f "$f" ] && cp "$f" "$TARGET/lib/" && got_lzo=1
      done
    done
  fi

  # --- 源码编译 fallback ---
  build_dep() {
    # $1=名称 $2=源码目录 $3=压缩包路径 $4=下载 URL $5=安装前缀
    local name="$1" src="$2" tarball="$3" url="$4" prefix="$5"
    local log="$CACHE/${name}-build.log"

    if [ ! -f "$src/configure" ]; then
      [ -f "$tarball" ] || try_download "$url" "$tarball" || die "$name 源码下载失败"
      case "$tarball" in
        *.bz2) tar xjf "$tarball" -C "$BUILD" ;;
        *)     tar xzf "$tarball" -C "$BUILD" ;;
      esac
    fi

    c_info "编译 ${name}（约 30 秒）"
    (
      cd "$src" || exit 1
      ./configure --prefix="$prefix" --disable-static --enable-shared >"$log" 2>&1 || exit 1
      make -j"$(sysctl -n hw.ncpu 2>/dev/null || echo 4)" >>"$log" 2>&1 || exit 1
      make install >>"$log" 2>&1 || exit 1
    ) || {
      c_err "$name 编译失败，最后 15 行日志："
      tail -15 "$log" | sed 's/^/    /'
      die "完整日志：$log"
    }
  }

  if [ "$got_libusb" -eq 0 ]; then
    command -v clang >/dev/null || die "需要 Xcode Command Line Tools：xcode-select --install"
    command -v make  >/dev/null || die "缺少 make"
    build_dep libusb "$BUILD/libusb-$LIBUSB_VER" "$CACHE/libusb.tar.bz2" "$LIBUSB_URL" "$BUILD/libusb-inst"
    cp "$BUILD/libusb-inst/lib"/libusb-1.0.[0-9]*.dylib "$TARGET/lib/"
    got_libusb=1
    c_ok "libusb 就绪"
  fi

  if [ "$got_lzo" -eq 0 ]; then
    build_dep lzo "$BUILD/lzo-$LZO_VER" "$CACHE/lzo.tar.gz" "$LZO_URL" "$BUILD/lzo-inst"
    cp "$BUILD/lzo-inst/lib"/liblzo2.[0-9]*.dylib "$TARGET/lib/"
    got_lzo=1
    c_ok "lzo2 就绪"
  fi
fi

# --- 补齐 dlopen 需要的文件名别名 ---
cd "$TARGET/lib"
# 只挑真实文件，避免把上一次建的软链当成源文件（会导致自引用死循环）
LIBUSB_REAL="$(find . -maxdepth 1 -type f -name 'libusb-1.0.*.dylib' ! -name 'libusb-1.0.dylib' | head -1 | sed 's|^\./||')"
LZO_REAL="$(find . -maxdepth 1 -type f -name 'liblzo2.*.dylib' ! -name 'liblzo2.dylib' | head -1 | sed 's|^\./||')"
[ -n "$LIBUSB_REAL" ] || die "找不到 libusb 动态库"
[ -n "$LZO_REAL" ]    || die "找不到 liblzo2 动态库"

# bb10mt 用的是 dlopen("libusb") 这种裸名，必须建这些别名
ln -sf "$LIBUSB_REAL" libusb.dylib
ln -sf "$LIBUSB_REAL" libusb-1.0.dylib
ln -sf "$LZO_REAL"    liblzo2.dylib
cd - >/dev/null

c_ok "动态库就位：$(ls "$TARGET/lib" | tr '\n' ' ')"

# ---------- 4. 生成启动器 ----------
c_info "生成 bb10mt 启动器"

cat > "$TARGET/bb10mt" <<'WRAPPER'
#!/bin/bash
# bb10mt 启动器 —— 自动处理架构选择和动态库路径
set -e
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export DYLD_LIBRARY_PATH="$ROOT/lib${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}"

case "$(uname -m)" in
  arm64)  BIN="$ROOT/bin/bb10mt-arm64" ;;
  x86_64) BIN="$ROOT/bin/bb10mt-x86_64" ;;
  *)      echo "不支持的架构：$(uname -m)" >&2; exit 1 ;;
esac
[ -x "$BIN" ] || { echo "找不到 $BIN，请重新跑 setup.sh" >&2; exit 1; }

xattr -d com.apple.quarantine "$BIN" 2>/dev/null || true
exec "$BIN" "$@"
WRAPPER
chmod +x "$TARGET/bb10mt"

# ---------- 5. SSH 私钥（可选） ----------
if [ ! -f "$TARGET/id_rsa4x" ]; then
  if try_download "$SSHKEY_URL" "$TARGET/id_rsa4x" 2>/dev/null; then
    chmod 600 "$TARGET/id_rsa4x"
    c_ok "SSH 私钥已下载（id_rsa4x）"
  else
    c_warn "SSH 私钥下载失败，不影响刷机和 Root，需要时手动下 $SSHKEY_URL"
  fi
fi

# ---------- 6. 自检 ----------
c_info "自检"

cd "$TARGET"
VER="$(./bb10mt --version 2>&1 | grep -i 'multitool' | head -1 || true)"
if [ -n "$VER" ]; then
  c_ok "$VER"
else
  c_warn "bb10mt 启动失败，手动排查："
  ./bb10mt --version 2>&1 | head -5 | sed 's/^/    /'
  exit 1
fi

echo
c_ok "环境准备完成"
cat <<EOF

  工具目录：$TARGET
  下一步：
    1. 把固件放进  $TARGET/autoloader/
    2. 看文档      docs/02-firmware.md（下载固件）
                   docs/03-flash.md（刷机）
                   docs/04-root.md（Root）

  常用命令：
    cd $TARGET
    ./bb10mt --version
    ./bb10mt info
    ./bb10mt split -i autoloader/xxx.exe -o split
    ./bb10mt flash -i split/xxx.0.signed

EOF
