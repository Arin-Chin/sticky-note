#!/usr/bin/env bash
# 构建免安装 Windows 压缩包（复用同一份补丁后的 app.asar）
#
#   bash build-windows.sh            # 默认 x64
#   WIN_ARCH=arm64 bash build-windows.sh
#
# 产物: ./sticky-note-1.0.1-windows-<arch>.zip
# 依赖: curl, unzip, zip, rsvg-convert(若图标为 SVG)、本机原程序或 SN_APP_DIR

set -euo pipefail
cd "$(dirname "$0")"

VERSION="1.0.1"
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

# 附带图标源，方便自行替换重新构建
cp -f "$PWD/sticky-note.svg" "$ROOT/sticky-note.svg" 2>/dev/null || true

cat > "$ROOT/使用说明.txt" <<'TXT'
sticky note 1.0.1（Windows 免安装版）
=====================================

启动：双击 sticky-note.exe

说明：
- 无需安装，解压到任意目录即可使用；删除目录即可卸载。
- 数据保存在 %APPDATA%\todo-list（data.json / settings.json）。
- 托盘：单击图标显示窗口；右键菜单可显示/隐藏或退出。
- 设置齿轮：开机自启、导出 Excel、使用指南、便签纸/文字/界面配色。
- 字体霞鹜文楷已随包附带，无需在系统安装。

如 Windows SmartScreen 提示未知发布者，属于未签名自编译程序的正常提示，
选择“更多信息 → 仍要运行”即可。
TXT

echo "[4/4] 打包 zip"
rm -f "$OUT"
( cd "$WORK" && zip -qr "$OUT" "$PKG_NAME" )

echo
echo "完成: $OUT"
echo "大小: $(du -h "$OUT" | cut -f1)"
echo "SHA256: $(sha256sum "$OUT" | cut -d' ' -f1)"
