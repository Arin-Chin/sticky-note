#!/usr/bin/env bash
# 构建 sticky note 的 .deb 安装包（基于本机已安装的「桌面便签」）
#
#   bash build-deb.sh [图标.svg]
#
# 产物: ./todo-list_1.1.0_arm64.deb
#
# 包名沿用原包 todo-list，版本号更高（1.1.0 > 0.2.3）=> 正常升级安装，不会留下两个图标：
#   sudo dpkg -i todo-list_1.1.0_arm64.deb
#
# 改动: 去掉打赏图标 / 标题栏多余文字 / 应用名改 sticky note / 换新图标
# 用户数据目录不变: ~/.config/todo-list
# 不联网、不重新编译，只读本机已安装的程序文件。

set -euo pipefail
cd "$(dirname "$0")"

ICON_SVG="${1:-/home/user/Downloads/sticky-note.svg}"
VERSION="1.1.0"
PKG="todo-list"
ARCH="$(dpkg --print-architecture)"
APP_NAME="sticky note"
OUT="$PWD/${PKG}_${VERSION}_${ARCH}.deb"
SIZES="16 24 32 48 64 96 128 256 512"

die() { echo "错误: $*" >&2; exit 1; }

[ -f "$ICON_SVG" ] || die "找不到图标文件: $ICON_SVG"
command -v dpkg-deb >/dev/null || die "缺少 dpkg-deb"
command -v rsvg-convert >/dev/null || die "缺少 rsvg-convert（apt install librsvg2-bin）"

# 定位原程序目录
APP_DIR="${SN_APP_DIR:-}"
if [ -z "$APP_DIR" ]; then
  exec_path="$(sed -n 's/^Exec="\?\([^" ]*todo-list\)"\?.*/\1/p' /usr/share/applications/todo-list.desktop 2>/dev/null | head -1 || true)"
  [ -n "$exec_path" ] && APP_DIR="$(dirname "$exec_path")"
fi
[ -n "$APP_DIR" ] || APP_DIR="/opt/桌面便签"
[ -x "$APP_DIR/todo-list" ] || die "找不到原程序: $APP_DIR/todo-list"

# 安装后的固定路径（与包内 chrome-sandbox / 自启动 / 启动项一致）
INSTALL_DIR="/opt/桌面便签"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
STAGE="$WORK/deb"

echo "[1/6] 生成补丁后的 app.asar"
bash install.sh build "$WORK/app.asar" >/dev/null
echo "      $(stat -c%s "$WORK/app.asar") 字节"

echo "[2/6] 从 SVG 渲染图标: $ICON_SVG"
mkdir -p "$WORK/icons"
for s in $SIZES; do
  rsvg-convert -w "$s" -h "$s" "$ICON_SVG" -o "$WORK/icons/$s.png"
done
rsvg-convert -w 512 -h 512 "$ICON_SVG" -o "$WORK/logo512.png"
rsvg-convert -w 32  -h 32  "$ICON_SVG" -o "$WORK/tray32.png"
echo "      $SIZES + 托盘 32px"

echo "[3/6] 替换 asar 内的托盘 / 窗口 / favicon 图标"
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

echo "[4/6] 拷贝程序目录到暂存区"
mkdir -p "$STAGE$INSTALL_DIR"
cp -a "$APP_DIR/." "$STAGE$INSTALL_DIR/"
cp -f "$WORK/app.asar" "$STAGE$INSTALL_DIR/resources/app.asar"
rm -f "$STAGE$INSTALL_DIR/resources/app.asar.orig"

echo "[5/6] 写入启动项 / 图标 / 控制信息"
DESK="$STAGE/usr/share/applications/todo-list.desktop"
mkdir -p "$(dirname "$DESK")"
cat > "$DESK" <<EOF
[Desktop Entry]
Name=$APP_NAME
Name[zh_CN]=$APP_NAME
Comment=简洁高效的本地便签
Exec="$INSTALL_DIR/todo-list" %U
Terminal=false
Type=Application
Icon=todo-list
StartupWMClass=$APP_NAME
Categories=Office;
Keywords=todo;note;memo;sticky;
EOF

for s in $SIZES; do
  d="$STAGE/usr/share/icons/hicolor/${s}x${s}/apps"
  mkdir -p "$d"
  cp -f "$WORK/icons/$s.png" "$d/todo-list.png"
done
mkdir -p "$STAGE/usr/share/icons/hicolor/scalable/apps"
cp -f "$ICON_SVG" "$STAGE/usr/share/icons/hicolor/scalable/apps/todo-list.svg"

mkdir -p "$STAGE/DEBIAN"
INSTALLED_SIZE="$(du -sk "$STAGE/opt" "$STAGE/usr" | awk '{s+=$1} END{print s}')"
cat > "$STAGE/DEBIAN/control" <<EOF
Package: $PKG
Version: $VERSION
Architecture: $ARCH
Maintainer: Arin-Chin <Arin-Chin@users.noreply.github.com>
Installed-Size: $INSTALLED_SIZE
Section: default
Priority: optional
Depends: libgtk-3-0, libnotify4, libnss3, libxss1, libxtst6, xdg-utils, libatspi2.0-0, libuuid1, libsecret-1-0, deepin-elf-verify (>= 1.1.10-1)
Description: $APP_NAME - 简洁高效的本地便签
EOF

cat > "$STAGE/DEBIAN/postinst" <<'EOF'
#!/bin/bash
ln -sf '/opt/桌面便签/todo-list' '/usr/bin/todo-list'
chmod 4755 '/opt/桌面便签/chrome-sandbox' || true
update-mime-database /usr/share/mime || true
update-desktop-database /usr/share/applications || true
gtk-update-icon-cache -q -t -f /usr/share/icons/hicolor || true
exit 0
EOF
cat > "$STAGE/DEBIAN/postrm" <<'EOF'
#!/bin/bash
if [ "$1" = "remove" ] || [ "$1" = "purge" ]; then
  rm -f '/usr/bin/todo-list'
  update-desktop-database /usr/share/applications || true
  gtk-update-icon-cache -q -t -f /usr/share/icons/hicolor || true
fi
exit 0
EOF
chmod 755 "$STAGE/DEBIAN/postinst" "$STAGE/DEBIAN/postrm"

( cd "$STAGE" && find . -type f ! -path './DEBIAN/*' -printf '%P\n' | LC_ALL=C sort | xargs -d '\n' md5sum > DEBIAN/md5sums )

echo "[6/6] 打包 .deb（xz -3，约 1-3 分钟）"
rm -f "$OUT"
dpkg-deb --root-owner-group -Zxz -z3 --build "$STAGE" "$OUT" >/dev/null

echo
echo "完成: $OUT"
echo "大小: $(du -h "$OUT" | cut -f1)"
echo "SHA256: $(sha256sum "$OUT" | cut -d' ' -f1)"
echo
echo "安装:   sudo dpkg -i \"$OUT\""
echo "还原:   sudo apt install --reinstall todo-list"
