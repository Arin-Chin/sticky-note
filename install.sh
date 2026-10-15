#!/usr/bin/env bash
# sticky-note: 把已安装的「桌面便签」改造成无广告、无标题杂项的自用版
#
#   bash install.sh            # 安装（需要 sudo 密码）
#   bash install.sh uninstall  # 还原成原版
#   bash install.sh build out.asar   # 只生成打好补丁的 app.asar（免密码，便于检查）
#
# 改动内容：
#   - 隐藏工具栏 ☕（请作者喝咖啡）图标
#   - 隐藏左上角应用名、右上角“记清，办明，不遗漏”
#   - 应用名改为 sticky note（窗口标题 / 启动器 / 托盘提示）
#   - 数据目录 ~/.config/todo-list 不变，原有便签数据照常使用
#
# 原理：就地替换 /opt/桌面便签/resources/app.asar，原文件备份为 app.asar.orig。
# 不复制 130MB 的 Electron 运行时，不重编译，不联网。

set -euo pipefail

# 目标应用目录：优先环境变量 SN_APP_DIR，其次从系统启动项推断，最后回退到 UOS/Deepin 的默认位置
resolve_app_dir() {
  if [ -n "${SN_APP_DIR:-}" ] && [ -x "$SN_APP_DIR/todo-list" ]; then echo "$SN_APP_DIR"; return; fi
  local desktop exec_path
  for desktop in /usr/share/applications/todo-list.desktop "$HOME/.local/share/applications/todo-list.desktop"; do
    [ -f "$desktop" ] || continue
    exec_path="$(sed -n 's/^Exec=\"\?\([^\" ]*todo-list\)\"\?.*/\1/p' "$desktop" | head -1)"
    [ -n "$exec_path" ] && [ -x "$exec_path" ] && { echo "$(dirname "$exec_path")"; return; }
  done
  echo "/opt/桌面便签"
}

APP_DIR="$(resolve_app_dir)"
BIN="$APP_DIR/todo-list"
ASAR="$APP_DIR/resources/app.asar"
BAK="$APP_DIR/resources/app.asar.orig"
DESKTOP_ID="sticky-note"
APP_NAME="sticky note"

die() { echo "错误: $*" >&2; exit 1; }

# ---------------------------------------------------------------- patch.js
read -r -d '' PATCH_JS <<'PATCHEOF' || true
'use strict';
process.noAsar = true; // 关闭 Electron 的 asar 拦截，直接按普通文件读写
const fs = require('fs');
const src = process.argv[2], out = process.argv[3];
const verifyOnly = process.argv[4] === '--verify';
if (!src || !out) { console.error('用法: patch.js <源 app.asar> <输出 app.asar> [--verify]'); process.exit(1); }
if (!fs.existsSync(src) && !fs.existsSync(out)) {
  // 允许 uninstall 时源=目标
  console.error('找不到源文件: ' + src); process.exit(1);
}

const buf = fs.readFileSync(src);
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

const get = p => { if (!byPath[p]) throw new Error('asar 中缺少 ' + p); return byPath[p].data.toString('utf8'); };
const set = (p, s) => { byPath[p].data = Buffer.from(s, 'utf8'); };
// 按模式定位带 hash 的文件（js/app.<hash>.js、css/app.<hash>.css）
const match = re => {
  const hit = Object.keys(byPath).filter(p => re.test(p));
  if (hit.length !== 1) throw new Error('expected 1 file for ' + re + ', got ' + hit.length + ': ' + hit.join(','));
  return hit[0];
};
function rep(p, from, to, expect) {
  const s = get(p);
  const n = s.split(from).length - 1;
  if (n === 0) {
    if (to && s.indexOf(to) >= 0) { console.log('  ' + p + ' : 已处理，跳过'); return; }
    throw new Error(p + ' 中找不到 "' + from + '"（版本不匹配？）');
  }
  if (expect != null && n !== expect) throw new Error(p + ' 中 "' + from + '" 出现 ' + n + ' 次，预期 ' + expect + ' 次（版本不匹配？）');
  set(p, s.split(from).join(to));
  console.log('  ' + p + ' : ' + from + '  ->  ' + to + ' (' + n + ' 处)');
}
// 在所有文件中查找替换，只校验总数
function repAll(from, to, expect) {
  let total = 0;
  for (const f of files) {
    const s = f.data.toString('utf8');
    const n = s.split(from).length - 1;
    if (!n) continue;
    f.data = Buffer.from(s.split(from).join(to), 'utf8');
    total += n;
  }
  if (total === 0) {
    // 删除类替换（to 为空）无法用“目标已存在”判断，找不到即视为已完成
    if (to === '') { console.log('  [全部文件] 未找到或已处理，跳过: ' + from); return; }
    const all = files.map(f => f.data.toString('utf8')).join('\n');
    if (all.indexOf(to) >= 0) { console.log('  [全部文件] 已处理，跳过: ' + from); return; }
    throw new Error('asar 中找不到 "' + from + '"');
  }
  if (expect != null && total !== expect) throw new Error('"' + from + '" 共出现 ' + total + ' 次，预期 ' + expect + ' 次（版本不匹配？）');
  console.log('  [全部文件] ' + from + '  ->  ' + to + ' (' + total + ' 处)');
}

// 1) 应用名 / 标题
if (verifyOnly) console.log('  仅校验，不写入');
if (!verifyOnly) {
const appJs = match(/^\/js\/app\.[0-9a-f]+\.js$/);
const appCss = match(/^\/css\/app\.[0-9a-f]+\.css$/);
rep('/package.json',  '"productName": "桌面便签"', '"productName": "sticky note"', 1);
rep('/package.json',  '"description": "桌面便签 - ', '"description": "sticky note - ', 1);
rep('/index.html',    '<title>todo-list</title>', '<title>sticky note</title>', 1);
rep(appJs,            '"productName":"桌面便签"', '"productName":"sticky note"', 1);
rep(appJs,            '"description":"桌面便签 - ', '"description":"sticky note - ', 1);
rep('/background.js', '"productName":"桌面便签"', '"productName":"sticky note"', 1);
rep('/background.js', 'title:"桌面便签', 'title:"sticky note', null);
// 版本号 V1.1.0
rep('/package.json',  '"version": "0.2.3"', '"version": "1.1.0"', 1);
rep(appJs,            '"version":"0.2.3"', '"version":"1.1.0"', 1);
rep('/background.js', '"version":"0.2.3"', '"version":"1.1.0"', 1);

// 2) 隐藏 ☕ 图标与标题栏杂项文字（只加 CSS，不改 UI 逻辑）
const cssOld = get(appCss);
if (cssOld.indexOf('coffee-btn{display:none') < 0) {
  set(appCss, cssOld + '\n/* sticky-note patch */\n.drag-nav b,.drag-nav i,.tool-btn.coffee-btn{display:none!important}\n');
  console.log('  ' + appCss + ' : 附加隐藏规则');
}
// 3) 去除原程序作者 / 打赏 / 推广信息
const aboutJs = match(/^\/js\/chunk-ad7ee4c2\.[0-9a-f]+\.js$/);
rep('/package.json',   '  "author": "xiaolin",\n', '', 1);
rep('/package.json',   ',\n  "homepage": "https://github.com/xiaolin/todo-list"', '', 1);
rep(appJs,             '"author":"xiaolin"', '"author":""', 1);
rep('/background.js',  '"author":"xiaolin"', '"author":""', 1);
// 「使用指南」窗口底部: sticky note v0.2.3 / Powered by 万能小林子
rep(aboutJs, ',t("div",{staticClass:"version-info"},[t("p",[s._v(s._s(s.productName)+" v"+s._s(s.version))]),t("p",{staticClass:"author"},[s._v("Powered by 万能小林子")])])', '', 1);
// 工具栏 ☕ 按钮（含“请作者喝咖啡”提示与点击处理器）
rep(appJs, 't("span",{staticClass:"tool-btn coffee-btn",attrs:{title:"请作者喝咖啡"},on:{click:e.showDonate}},[e._v("☕")]),', '', 1);
// 首次运行的示例待办里的推广文案
rep('/background.js', '【重要】给项目点一个star ☕请作者喝咖啡', '欢迎使用 sticky note', 1);
// 打赏窗口文案与支付地址（入口已移除，这里清掉残留字符串）
repAll('☕ 请作者喝咖啡', '☕');
repAll('如果桌面便签帮到了你，可以请作者喝杯咖啡支持一下~', '');
repAll('必须支持！请作者喝咖啡~ ☕', '');
repAll('感谢投喂！这杯小咖啡让我精神一振~ ☕', '');
repAll('哇！中杯咖啡，双倍能量！谢谢你！☕☕', '');
repAll('太棒了！大杯咖啡，今天元气满满！☕☕☕', '');
repAll('感谢你的慷慨支持！动力满满！☕☕☕', '');
repAll('桌面便签打赏', 'sticky note');
repAll('桌面便签 - 请作者喝咖啡', 'sticky note');
repAll('请作者喝咖啡', '');
repAll('www.xiaolinwl.com/payment/success', 'example.invalid/payment/success');
repAll('www.xiaolinwl.com/payment/notify', 'example.invalid/payment/notify');
// sourcemap 里也残留作者信息，一并清掉
repAll('Powered by 万能小林子', '');
repAll('万能小林子', '');
repAll('"author":"xiaolin"', '"author":""');
}

// 4) 自检：确认补丁生效、数量没被改坏
const all = files.map(f => f.data.toString('utf8')).join('\n');
for (const bad of ['"productName":"桌面便签"', 'title:"桌面便签', '"productName": "桌面便签"']) {
  if (all.indexOf(bad) >= 0) throw new Error('补丁未生效，仍存在: ' + bad);
}
for (const bad of ['xiaolin', '小林子', 'Powered by', '请作者喝咖啡']) {
  if (all.indexOf(bad) >= 0) throw new Error('作者信息未清除干净: ' + bad);
}
if (all.indexOf('coffee-btn{display:none') < 0) throw new Error('CSS 隐藏规则未写入');

if (verifyOnly) { console.log('  校验通过'); process.exit(0); }

// 5) 重新打包 asar（与原格式一致：pickle 头 + 顺序数据）
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
fs.writeFileSync(out, Buffer.concat([prefix].concat(files.map(f => f.data))));
console.log('  打包完成: ' + out + ' (' + fs.statSync(out).size + ' 字节, ' + files.length + ' 个文件)');
PATCHEOF

# ---------------------------------------------------------------- 工具函数
run_patch() { # run_patch <源> <输出>
  local tmp; tmp="$(mktemp -d)"
  printf '%s\n' "$PATCH_JS" > "$tmp/patch.js"
  if [ -x "$BIN" ]; then
    ELECTRON_RUN_AS_NODE=1 ELECTRON_NO_ASAR=1 "$BIN" "$tmp/patch.js" "$1" "$2"
  elif command -v node >/dev/null 2>&1; then
    node "$tmp/patch.js" "$1" "$2"
  else
    rm -rf "$tmp"; die "找不到可用的 node 运行时（$BIN 与 node 都不可用）"
  fi
  rm -rf "$tmp"
}

verify_asar() { # verify_asar <file>：重新解包抽查
  local tmp; tmp="$(mktemp -d)"
  printf '%s\n' "$PATCH_JS" > "$tmp/patch.js"
  local out="$tmp/check.asar"
  ELECTRON_RUN_AS_NODE=1 ELECTRON_NO_ASAR=1 "$BIN" "$tmp/patch.js" "$1" "$out" --verify >/dev/null 2>&1 || { rm -rf "$tmp"; die "校验失败：app.asar 已损坏或补丁未生效"; }
  rm -rf "$tmp"
  echo "  校验通过"
}

target_user() { echo "${SUDO_USER:-${USER:-$(id -un 1000)}}"; }
target_home() { getent passwd "$(target_user)" | cut -d: -f6; }

write_desktop_entry() {
  local home; home="$(target_home)"
  local dir="$home/.local/share/applications"
  local user; user="$(target_user)"
  install -d -o "$user" -g "$user" "$dir"
  cat > "$dir/$DESKTOP_ID.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=$APP_NAME
Comment=简洁高效的待办事项管理工具
Exec="$BIN" %U
Terminal=false
Icon=todo-list
StartupWMClass=$APP_NAME
Categories=Office;
Keywords=todo;note;memo;sticky;
EOF
  chown "$user:$user" "$dir/$DESKTOP_ID.desktop"
  # 隐藏系统里原来的「桌面便签」启动项，避免出现两个图标
  cat > "$dir/todo-list.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=桌面便签
Hidden=true
EOF
  chown "$user:$user" "$dir/todo-list.desktop"
  command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$dir" >/dev/null 2>&1 || true
}

restart_app() {
  local user; user="$(target_user)"
  local pid envs=""
  pid="$(pgrep -f "^$BIN$" | head -1 || true)"
  if [ -n "$pid" ] && [ -r "/proc/$pid/environ" ]; then
    local v val
    for v in DISPLAY XAUTHORITY DBUS_SESSION_BUS_ADDRESS XDG_RUNTIME_DIR; do
      val="$(tr '\0' '\n' < "/proc/$pid/environ" | sed -n "s/^$v=//p" | head -1)"
      [ -n "$val" ] && envs="$envs $v=$val"
    done
  fi
  [ -n "$envs" ] || envs=" DISPLAY=:0 XAUTHORITY=$(target_home)/.Xauthority"
  pkill -f "^$BIN$" 2>/dev/null || true
  sleep 1
  # shellcheck disable=SC2086
  setsid runuser -u "$user" -- env $envs "$BIN" >/dev/null 2>&1 < /dev/null &
  sleep 2
  pgrep -f "^$BIN$" >/dev/null && echo "  应用已重新启动" || echo "  提示：请手动点击 sticky note 图标启动"
}

# 应用启动时会重写 ~/.config/autostart/todo-list.desktop，若里面的路径失效（例如指向临时目录）则修正
fix_autostart() {
  local home entry
  home="$(target_home)"
  entry="$home/.config/autostart/todo-list.desktop"
  [ -f "$entry" ] || return 0
  if ! grep -qF "Exec=$BIN" "$entry"; then
    sed -i "s|^Exec=.*|Exec=$BIN|" "$entry"
    chown "$(target_user):$(target_user)" "$entry"
    echo "  已修正开机自启路径: $entry"
  fi
}

# ---------------------------------------------------------------- 主流程
CMD="${1:-install}"

case "$CMD" in
  build)
    OUT="${2:-/tmp/sticky-note-app.asar}"
    [ -f "$ASAR" ] || die "找不到 $ASAR"
    echo "生成补丁包（不修改系统）："
    run_patch "$ASAR" "$OUT"
    ;;

  install)
    [ "$(id -u)" -eq 0 ] || exec sudo -E bash "$0" "$@"
    [ -f "$ASAR" ] || die "找不到 $ASAR，确认「桌面便签」已安装"
    [ -e "$BAK" ] || { cp -a "$ASAR" "$BAK"; echo "已备份原版 -> $BAK"; }
    echo "应用补丁："
    run_patch "$BAK" "$ASAR"
    verify_asar "$ASAR"
    write_desktop_entry
    echo "启动器已更新为 $APP_NAME"
    fix_autostart
    restart_app
    echo "完成。卸载还原：bash $0 uninstall"
    ;;

  uninstall)
    [ "$(id -u)" -eq 0 ] || exec sudo -E bash "$0" "$@"
    [ -e "$BAK" ] || die "没有备份文件 $BAK，无法还原"
    cp -a "$BAK" "$ASAR"
    local_home="$(target_home)"
    rm -f "$local_home/.local/share/applications/$DESKTOP_ID.desktop" \
          "$local_home/.local/share/applications/todo-list.desktop"
    command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$local_home/.local/share/applications" >/dev/null 2>&1 || true
    fix_autostart
    echo "已还原原版「桌面便签」"
    restart_app
    ;;

  *)
    die "未知命令: $CMD（可用: install / uninstall / build）"
    ;;
esac
