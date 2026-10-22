#!/usr/bin/env bash
# 构建免安装的 sticky note 压缩包
#
#   bash build.sh
#
# 产物: ./sticky-note-1.0.1-uos-arm64.tar.gz
# 解压即用，不依赖系统里是否装过原程序。
#
# 需要: rsvg-convert（仅当图标是 SVG 时，apt install librsvg2-bin）、本机已安装的原程序（或 SN_APP_DIR 指定）

set -euo pipefail
cd "$(dirname "$0")"

ICON_SVG="$PWD/sticky-note.svg"   # 固定图标，禁止通过参数更改
VERSION="1.0.1"
APP_NAME="sticky note"
SIZES="16 24 32 48 64 96 128 256 512"
ARCH="$(dpkg --print-architecture)"
PKG_NAME="sticky-note-${VERSION}-uos-${ARCH}"
OUT="$PWD/$PKG_NAME.tar.gz"

die() { echo "错误: $*" >&2; exit 1; }

[ -f "$ICON_SVG" ] || die "找不到图标文件: $ICON_SVG"
case "${ICON_SVG##*.}" in
  svg|SVG) command -v rsvg-convert >/dev/null || die "SVG 图标需要 rsvg-convert（apt install librsvg2-bin）" ;;
esac

APP_DIR="${SN_APP_DIR:-}"
if [ -z "$APP_DIR" ]; then
  exec_path="$(sed -n 's|^Exec="\?\([^" ]*todo-list\)"\?.*|\1|p' /usr/share/applications/todo-list.desktop 2>/dev/null | head -1)"
  [ -n "$exec_path" ] && APP_DIR="$(dirname "$exec_path")"
fi
APP_DIR="${APP_DIR:-/opt/桌面便签}"
[ -x "$APP_DIR/todo-list" ] || die "找不到原程序: $APP_DIR/todo-list（可用 SN_APP_DIR 指定）"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
ROOT="$WORK/$PKG_NAME"

echo "[1/4] 生成补丁后的 app.asar"
SN_APP_DIR="$APP_DIR" bash patch-asar.sh "$WORK/app.asar" >/dev/null
echo "      $(stat -c%s "$WORK/app.asar") 字节"

echo "[2/4] 准备图标: $ICON_SVG"
mkdir -p "$WORK/icons"
case "${ICON_SVG##*.}" in
  svg|SVG)
    for s in $SIZES; do
      rsvg-convert -w "$s" -h "$s" "$ICON_SVG" -o "$WORK/icons/$s.png"
    done
    rsvg-convert -w 512 -h 512 "$ICON_SVG" -o "$WORK/logo512.png"
    rsvg-convert -w 32 -h 32 "$ICON_SVG" -o "$WORK/tray32.png"
    echo "      由 SVG 渲染 $SIZES + 托盘 32px"
    ;;
  *)
    # 位图图标：原样使用，由桌面环境/Electron 自行缩放
    for s in $SIZES; do
      cp -f "$ICON_SVG" "$WORK/icons/$s.png"
    done
    cp -f "$ICON_SVG" "$WORK/logo512.png"
    cp -f "$ICON_SVG" "$WORK/tray32.png"
    echo "      使用位图 $SIZES + 托盘"
    ;;
esac

echo "[3/4] 替换 asar 内的托盘 / 窗口 / favicon 图标"
cat > "$WORK/icons.js" <<'JSEOF'
'use strict';
process.noAsar = true;
const fs = require('fs');
const asarPath = process.env.SN_ASAR;
const logo = fs.readFileSync(process.env.SN_LOGO);
const tray = fs.readFileSync(process.env.SN_TRAY);
const iconsDir = process.env.SN_ICONS;

const buf = fs.readFileSync(asarPath);
const u32 = n => { const b = Buffer.alloc(4); b.writeUInt32LE(n >>> 0, 0); return b; };
const align4 = n => (n + 3) & ~3;
const dataStart = 8 + buf.readUInt32LE(4);
const strSize = buf.readUInt32LE(8);
const rawHeader = buf.slice(16, 16 + strSize).toString('utf8');
const header = JSON.parse(rawHeader.slice(0, rawHeader.lastIndexOf('}') + 1));

const files = [];
(function walk(node, prefix) {
  for (const name of Object.keys(node.files)) {
    const e = node.files[name];
    const p = prefix + '/' + name;
    if (e.files) walk(e, p);
    else {
      const off = dataStart + Number(e.offset);
      files.push({ path: p, data: buf.slice(off, off + Number(e.size)) });
    }
  }
})(header, '');

const byPath = {};
for (const f of files) byPath[f.path] = f;

let n = 0;
for (const s of [16, 24, 32, 48, 64, 96, 128, 256, 512]) {
  const p = '/icons/' + s + 'x' + s + '.png';
  if (byPath[p]) { byPath[p].data = fs.readFileSync(iconsDir + '/' + s + '.png'); n++; }
}
for (const p of ['/logo.png', '/logo-512.png', '/favicon.png']) {
  if (byPath[p]) { byPath[p].data = logo; n++; }
}
if (byPath['/tray.png']) { byPath['/tray.png'].data = tray; n++; }

const root = { files: {} };
let offset = 0;
for (const f of files) {
  const parts = f.path.slice(1).split('/');
  let node = root;
  for (let i = 0; i < parts.length - 1; i++) {
    if (!node.files[parts[i]]) node.files[parts[i]] = { files: {} };
    node = node.files[parts[i]];
  }
  node.files[parts[parts.length - 1]] = { size: f.data.length, offset: String(offset) };
  offset += f.data.length;
}
const json = Buffer.from(JSON.stringify(root), 'utf8');
const jsonPadded = align4(json.length);
const headerBuf = Buffer.concat([u32(4 + jsonPadded), u32(json.length), json, Buffer.alloc(jsonPadded - json.length)]);
const prefix = Buffer.concat([u32(4), u32(headerBuf.length), headerBuf]);
fs.writeFileSync(asarPath, Buffer.concat([prefix].concat(files.map(f => f.data))));
console.log('      替换 ' + n + ' 个图标文件');
JSEOF
SN_ASAR="$WORK/app.asar" SN_LOGO="$WORK/logo512.png" SN_TRAY="$WORK/tray32.png" SN_ICONS="$WORK/icons" \
ELECTRON_NO_ASAR=1 ELECTRON_RUN_AS_NODE=1 "$APP_DIR/todo-list" "$WORK/icons.js"

echo "[4/4] 组装压缩包"
mkdir -p "$ROOT"
cp -a "$APP_DIR/." "$ROOT/"
cp -f "$WORK/app.asar" "$ROOT/resources/app.asar"
rm -f "$ROOT/resources/app.asar.orig"
# 应用菜单用的顶层图标（asar 内的 logo.png 只影响窗口/托盘）
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
# 图标会复制到 ~/.local/share/icons，与解压目录无关：
# 以后移动或删除解压出来的文件夹，菜单图标仍能正常显示。
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
APPS="$HOME/.local/share/applications"
ICONS="$HOME/.local/share/icons/hicolor/512x512/apps"
mkdir -p "$APPS" "$ICONS"
cp -f "$DIR/logo.png" "$ICONS/sticky-note.png"
cat > "$APPS/sticky-note.desktop" <<DESK
[Desktop Entry]
Type=Application
Name=sticky note
Comment=简洁高效的本地便签
Exec="$DIR/todo-list" %U
Terminal=false
Icon=sticky-note
StartupWMClass=sticky note
Categories=Office;
DESK
if command -v update-desktop-database >/dev/null 2>&1; then update-desktop-database "$APPS" || true; fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then gtk-update-icon-cache -q -t -f "$HOME/.local/share/icons/hicolor" || true; fi
echo "已加入应用菜单: sticky note（图标已装到 ~/.local/share/icons）"
EOF
chmod +x "$ROOT/install-desktop.sh"

cat > "$ROOT/README.txt" <<EOF
$APP_NAME $VERSION 免安装版
================================

运行:   ./sticky-note.sh           （或直接 ./todo-list）
菜单:   ./install-desktop.sh       （可选，写入 ~/.local/share/applications）

便签数据保存在 ~/.config/todo-list，与其他版本共用。
配置文件: ~/.config/todo-list/settings.json
EOF

tar -C "$WORK" -czf "$OUT" "$PKG_NAME"

echo
echo "完成: $OUT"
echo "大小: $(du -h "$OUT" | cut -f1)"
echo "SHA256: $(sha256sum "$OUT" | cut -d' ' -f1)"
echo
echo "使用: tar xzf $(basename "$OUT") && cd $PKG_NAME && ./sticky-note.sh"
