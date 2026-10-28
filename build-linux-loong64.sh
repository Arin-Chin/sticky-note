#!/usr/bin/env bash
# 构建 LoongArch64（银河麒麟/loongarch64）免安装压缩包
#
#   bash build-linux-loong64.sh
#
# 产物: ./sticky-note-<version>-linux-loong64.tar.gz
# 运行时来源: Loongnix Electron v13.6.9（与应用的 Electron 版本一致）
# 需要: rsvg-convert、node、curl、unzip、本机原程序或 SN_APP_DIR

set -euo pipefail
cd "$(dirname "$0")"

VERSION="$(tr -d '[:space:]' < "$PWD/VERSION")"
APP_NAME="sticky note"
ARCH="loong64"
PKG_NAME="sticky-note-${VERSION}-linux-${ARCH}"
OUT="$PWD/$PKG_NAME.tar.gz"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/sticky-note"
ELECTRON_VER="13.6.9"
ELECTRON_ZIP="$CACHE/electron-v${ELECTRON_VER}-linux-loong64.zip"
ELECTRON_URL="https://ftp.loongnix.cn/electron/LoongArch/v${ELECTRON_VER}/electron-v${ELECTRON_VER}-linux-loong64.zip"
ELECTRON_SHA256="c402063d2838a65a09b1d74a9b76a440d767104b27d396ca702e9fb1dc02e482"
SIZES="16 24 32 48 64 96 128 256 512"

die() { echo "错误: $*" >&2; exit 1; }
[ -n "$VERSION" ] || die "VERSION 文件为空或不存在"
command -v curl >/dev/null || die "缺少 curl"
command -v unzip >/dev/null || die "缺少 unzip"
command -v node >/dev/null || die "缺少 node"
command -v rsvg-convert >/dev/null || die "需要 rsvg-convert 渲染图标"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
ROOT="$WORK/$PKG_NAME"

echo "[1/4] 生成补丁后的 app.asar"
SN_VERSION="$VERSION" SN_APP_DIR="${SN_APP_DIR:-}" bash ./patch-asar.sh "$WORK/app.asar" >/dev/null
echo "      $(stat -c%s "$WORK/app.asar") 字节"

echo "[2/4] 渲染图标"
mkdir -p "$WORK/icons"
for s in $SIZES; do
  rsvg-convert -w "$s" -h "$s" "$PWD/sticky-note.svg" -o "$WORK/icons/$s.png"
done
rsvg-convert -w 512 -h 512 "$PWD/sticky-note.svg" -o "$WORK/logo512.png"
rsvg-convert -w 32 -h 32 "$PWD/sticky-note.svg" -o "$WORK/tray32.png"

echo "[3/4] 准备 LoongArch64 Electron ${ELECTRON_VER}"
mkdir -p "$CACHE"
if [ ! -s "$ELECTRON_ZIP" ]; then
  echo "      下载 $ELECTRON_URL"
  curl -fL --retry 3 -o "$ELECTRON_ZIP.part" "$ELECTRON_URL" || die "下载 Electron 失败"
  mv "$ELECTRON_ZIP.part" "$ELECTRON_ZIP"
fi
echo "$ELECTRON_SHA256  $ELECTRON_ZIP" | sha256sum -c - >/dev/null || die "Electron 校验失败"

mkdir -p "$ROOT"
unzip -q "$ELECTRON_ZIP" -d "$ROOT"
[ -x "$ROOT/electron" ] || die "Electron 压缩包结构异常"
cp -f "$WORK/app.asar" "$ROOT/resources/app.asar"
rm -f "$ROOT/resources/default_app.asar"

SN_ASAR="$ROOT/resources/app.asar" SN_LOGO="$WORK/logo512.png" \
SN_TRAY="$WORK/tray32.png" SN_ICONS="$WORK/icons" node "$PWD/tools/inject-icons.js"
mv -f "$ROOT/electron" "$ROOT/todo-list"

echo "[4/4] 组装压缩包"
find "$ROOT/locales" -maxdepth 1 -type f ! -name 'en-US.pak' -delete
cp -f "$WORK/logo512.png" "$ROOT/logo.png"

cat > "$ROOT/sticky-note.sh" <<'EOF'
#!/bin/bash
# 启动脚本：在解压目录就地运行
cd "$(dirname "$0")"
exec ./todo-list "$@"
EOF
chmod +x "$ROOT/sticky-note.sh"

cat > "$ROOT/install-desktop.sh" <<'EOF'
#!/bin/bash
# 可选：把 sticky note 加入应用菜单（不需要 root）
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
APPS="$HOME/.local/share/applications"
ICON="$HOME/.local/share/icons/sticky-note.png"
mkdir -p "$APPS" "$HOME/.local/share/icons"
cp -f "$DIR/logo.png" "$ICON"
# 用绝对路径，避免 UKUI/麒麟菜单找不到主题图标名
cat > "$APPS/sticky-note.desktop" <<DESK
[Desktop Entry]
Type=Application
Name=sticky note
Comment=简洁高效的本地便签
Exec="$DIR/todo-list" %U
Terminal=false
Icon=$ICON
StartupWMClass=sticky note
Categories=Office;
DESK
if command -v update-desktop-database >/dev/null 2>&1; then update-desktop-database "$APPS" || true; fi
echo "已加入应用菜单: sticky note（图标: $ICON）"
echo "若菜单未刷新，请注销后重新登录。"
EOF
chmod +x "$ROOT/install-desktop.sh"

{
  echo "LXGW WenKai — SIL Open Font License 1.1"
  echo
  cat "$PWD/fonts/OFL.txt"
} > "$ROOT/LICENSES.txt"

cat > "$ROOT/README.txt" <<EOF
$APP_NAME $VERSION Linux LoongArch64 免安装版

运行:   ./sticky-note.sh
菜单:   ./install-desktop.sh（可选）
数据:   ~/.config/todo-list

运行时为 Loongnix Electron v${ELECTRON_VER}（loongarch64）。
如提示 SUID sandbox 权限错误，可执行：
  sudo chown root:root chrome-sandbox && sudo chmod 4755 chrome-sandbox
EOF

tar -C "$WORK" -czf "$OUT" "$PKG_NAME"
echo
echo "完成: $OUT"
echo "大小: $(du -h "$OUT" | cut -f1)"
echo "SHA256: $(sha256sum "$OUT" | cut -d' ' -f1)"
