#!/usr/bin/env bash
# 构建免安装 Windows 压缩包（复用同一份补丁后的 app.asar）
#
#   bash build-windows.sh            # 默认 x64
#   WIN_ARCH=arm64 bash build-windows.sh
#
# 产物: ./sticky-note-1.0.2-windows-<arch>.zip
# 依赖: curl, unzip, zip, rsvg-convert(若图标为 SVG)、本机原程序或 SN_APP_DIR

set -euo pipefail
cd "$(dirname "$0")"

VERSION="1.0.2"
APP_NAME="sticky note"
ELECTRON_VER="13.6.9"
WIN_ARCH="${WIN_ARCH:-x64}"
PKG_NAME="sticky-note-${VERSION}-windows-${WIN_ARCH}"
OUT="$PWD/$PKG_NAME.zip"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/sticky-note"
ELECTRON_ZIP="$CACHE/electron-v${ELECTRON_VER}-win32-${WIN_ARCH}.zip"
ELECTRON_URL="https://github.com/electron/electron/releases/download/v${ELECTRON_VER}/electron-v${ELECTRON_VER}-win32-${WIN_ARCH}.zip"

die() { echo "错误: $*" >&2; exit 1; }
command -v curl >/dev/null || die "缺少 curl"
command -v unzip >/dev/null || die "缺少 unzip"
command -v zip >/dev/null || die "缺少 zip"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "[1/4] 生成补丁后的 app.asar"
bash ./patch-asar.sh "$WORK/app.asar"

echo "[2/4] 准备 Windows Electron ${ELECTRON_VER} (${WIN_ARCH})"
mkdir -p "$CACHE"
if [ ! -s "$ELECTRON_ZIP" ]; then
  echo "      下载 $ELECTRON_URL"
  curl -fL --retry 3 -o "$ELECTRON_ZIP.part" "$ELECTRON_URL" || die "下载 Electron 失败"
  mv "$ELECTRON_ZIP.part" "$ELECTRON_ZIP"
else
  echo "      使用缓存: $ELECTRON_ZIP"
fi

echo "[3/4] 组装 Windows 免安装目录"
ROOT="$WORK/$PKG_NAME"
mkdir -p "$ROOT"
unzip -q "$ELECTRON_ZIP" -d "$ROOT"
[ -f "$ROOT/electron.exe" ] || die "Electron 压缩包结构异常"
cp -f "$WORK/app.asar" "$ROOT/resources/app.asar"
rm -f "$ROOT/resources/default_app.asar"
# 改名后任务管理器/托盘显示 sticky-note
mv -f "$ROOT/electron.exe" "$ROOT/sticky-note.exe"

# 固定使用仓库中的 sticky-note.svg 生成 exe 图标并写入 PE 资源
ICON_SVG="$PWD/sticky-note.svg"
[ -f "$ICON_SVG" ] || die "找不到图标文件: $ICON_SVG"
command -v rsvg-convert >/dev/null || die "需要 rsvg-convert 渲染图标"
python3 -c "import PIL" 2>/dev/null || die "需要 python3 Pillow 生成 ico"
mkdir -p "$WORK/ico"
rsvg-convert -w 256 -h 256 "$ICON_SVG" -o "$WORK/ico/icon256.png"
python3 - "$WORK/ico/icon256.png" "$WORK/icon.ico" <<'PYICO'
import sys
from PIL import Image
img = Image.open(sys.argv[1]).convert('RGBA')
img.save(sys.argv[2], format='ICO', sizes=[(16,16),(24,24),(32,32),(48,48),(64,64),(128,128),(256,256)])
PYICO
echo "      写入 Windows 可执行文件图标"
mkdir -p "$WORK/petools"
npm install --prefix "$WORK/petools" --silent resedit >/dev/null 2>&1 || die "npm 安装 resedit 失败"
cat > "$WORK/seticon.cjs" <<'JSICO'
const fs = require('fs');
const ResEdit = require('resedit');
const [exePath, icoPath] = process.argv.slice(2);
const exe = ResEdit.NtExecutable.from(fs.readFileSync(exePath));
const res = ResEdit.NtExecutableResource.from(exe);
const ico = ResEdit.Data.IconFile.from(fs.readFileSync(icoPath));
const icons = ico.icons.map((i) => i.data);
const groups = ResEdit.Resource.IconGroupEntry.fromEntries(res.entries);
if (groups.length) {
  for (const g of groups) {
    ResEdit.Resource.IconGroupEntry.replaceIconsForResource(res.entries, g.id, g.lang, icons);
  }
} else {
  ResEdit.Resource.IconGroupEntry.replaceIconsForResource(res.entries, 32512, 1033, icons);
}
res.outputResource(exe);
fs.writeFileSync(exePath, Buffer.from(exe.generate()));
JSICO
NODE_PATH="$WORK/petools/node_modules" node "$WORK/seticon.cjs" "$ROOT/sticky-note.exe" "$WORK/icon.ico" || die "写入 exe 图标失败"

cat > "$ROOT/使用说明.txt" <<'TXT'
sticky note 1.0.2（Windows 免安装版）

启动：双击 sticky-note.exe
数据：%APPDATA%\todo-list
无需安装，删除目录即可卸载。
TXT

echo "[4/4] 打包 zip"
rm -f "$OUT"
( cd "$WORK" && zip -qr "$OUT" "$PKG_NAME" )

echo
echo "完成: $OUT"
echo "大小: $(du -h "$OUT" | cut -f1)"
echo "SHA256: $(sha256sum "$OUT" | cut -d' ' -f1)"
