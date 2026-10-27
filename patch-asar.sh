#!/usr/bin/env bash
# 生成打过补丁的 app.asar（sticky note 的核心改造逻辑）
#
#   bash patch-asar.sh [输出.asar]      默认 ./app-patched.asar
#   SN_APP_DIR=/path/to/桌面便签 bash patch-asar.sh
#
# 改动:
#   - 删除打赏/捐赠功能（路由、窗口、支付接口、页面文件）
#   - 删除全部 sourcemap
#   - 清除作者与推广信息
#   - 应用名改 sticky note，版本号 1.0.3，隐藏标题栏多余文字
# 自检不通过会直接报错退出，不会写出半成品；替换逻辑幂等，可重复执行。

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
const removeFile = p => {
  const i = files.findIndex(f => f.path === p);
  if (i >= 0) { files.splice(i, 1); delete byPath[p]; console.log('  删除文件 ' + p); }
  else console.log('  文件不存在，跳过 ' + p);
};
const addFile = (p, data) => {
  const existing = byPath[p];
  if (existing) { existing.data = data; console.log('  更新文件 ' + p + ' (' + data.length + ' 字节)'); return; }
  const f = { path: p, data: data };
  files.push(f); byPath[p] = f;
  console.log('  新增文件 ' + p + ' (' + data.length + ' 字节)');
};

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
    // 删除类替换（to 为空）找不到即视为已完成，保证脚本幂等
    if (!to || s.indexOf(to) >= 0) { console.log('  ' + p + ' : 已处理，跳过'); return; }
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
// 版本号 V1.0.3
rep('/package.json',  '"version": "0.2.3"', '"version": "1.0.3"', 1);
rep(appJs,            '"version":"0.2.3"', '"version":"1.0.3"', 1);
rep('/background.js', '"version":"0.2.3"', '"version":"1.0.3"', 1);

// 2) 隐藏标题栏杂项文字（左上角应用名、右上角标语）
const cssOld = get(appCss);
if (cssOld.indexOf('.drag-nav b,.drag-nav i{display:none') < 0) {
  set(appCss, cssOld + '\n/* sticky-note patch */\n.drag-nav b,.drag-nav i{display:none!important}\n');
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
// 6) 彻底删除打赏 / 捐赠功能
// 6.1 渲染层：路由、入口方法、独立窗口判定（☕ 按钮已在第 3 步删除）
rep(appJs, '{path:"/donate",name:"Donate",component:()=>Promise.all([n.e("chunk-2862e3e5"),n.e("chunk-3d3df498")]).then(n.bind(null,"8125"))},', '', 1);
rep(appJs, 'showDonate(){s["ipcRenderer"].invoke("openDonateWindow")},', '', 1);
rep(appJs, '"/donate"===this.$route.path||', '', 1);
// 6.1b 移除 webpack 运行时的 chunk 映射（含预取表）
rep(appJs, '"chunk-3d3df498":"e3dd88ea",', '', 1);
rep(appJs, '"chunk-3d3df498":"01d2e32f",', '', 1);
rep(appJs, '"chunk-3d3df498":1,', '', 1);
// 6.2 asar 内不再需要打赏页面文件
removeFile('/js/chunk-3d3df498.e3dd88ea.js');
removeFile('/js/chunk-3d3df498.e3dd88ea.js.map');
removeFile('/css/chunk-3d3df498.01d2e32f.css');
// 6.3 index.html 预加载链接
rep('/index.html', '<link href="app://./css/chunk-3d3df498.01d2e32f.css" rel="prefetch">', '', 1);
rep('/index.html', '<link href="app://./js/chunk-3d3df498.e3dd88ea.js" rel="prefetch">', '', 1);
// 6.4 主进程：打赏窗口与支付接口
rep('/background.js', ',n.ipcMain.handle("openDonateWindow",async()=>{!X||X.isDestroyed()?await async function(){if(X&&!X.isDestroyed())return void X.focus();const e="linux"===process.platform,t=Z.opacity||1,r=t<1&&!te();X=new n.BrowserWindow({width:380,height:540,minWidth:340,minHeight:480,resizable:!0,minimizable:!1,maximizable:!1,frame:!1,transparent:r,hasShadow:!r,...e?{}:{type:"toolbar"},skipTaskbar:!0,title:"sticky note - 打赏",show:!1,backgroundColor:r?"#00000000":"#2d2d2d",webPreferences:{nodeIntegration:!0,contextIsolation:!1,webSecurity:!1}});try{X.setSkipTaskbar(!0)}catch(e){}try{t<1&&X.setOpacity(t)}catch(e){}process.env.WEBPACK_DEV_SERVER_URL?await X.loadURL(process.env.WEBPACK_DEV_SERVER_URL+"#/donate"):(g("app"),await X.loadURL("app://./index.html#/donate")),X.show(),X.focus(),X.on("closed",()=>{X=null})}():X.focus()}),', ',', 1);
rep('/background.js', ',X&&!X.isDestroyed()&&X.setOpacity(r)', '', 1);
rep('/background.js', 'n.ipcMain.handle("createPaymentOrder",async(e,t)=>{try{const{amount:e,subject:n,body:i,payment:s="wechat"}=t,o="TD"+Date.now()+Math.random().toString(36).substr(2,6).toUpperCase(),a={site_id:6,site_order_no:o,amount:e.toFixed(2),subject:n||`sticky note - ${e}元`,body:i||"sticky note",payment:s,return_url:"https://example.invalid/payment/success",notify_url:"https://example.invalid/payment/notify"},l=Object.keys(a).sort().reduce((e,t)=>(e[t]=a[t],e),{});let u="";for(const[e,t]of Object.entries(l))u+=`${e}=${t}&`;u+="key=6e006e14e6362adbff20e08c1fa7afc9",a.sign=r(26).createHash("md5").update(u).digest("hex").toUpperCase(),console.log("支付请求参数:",a),console.log("签名字符串:",u);const c=await new Promise((e,t)=>{const n=r(141),i=r(665).stringify(a),s={hostname:"pay.wap2app.com",port:443,path:"/payment/create",method:"POST",headers:{"Content-Type":"application/x-www-form-urlencoded","Content-Length":Buffer.byteLength(i)},timeout:3e4,rejectUnauthorized:!1},o=n.request(s,r=>{let n="";r.on("data",e=>{n+=e}),r.on("end",()=>{console.log("支付网关响应:",n);try{const t=JSON.parse(n);e(t)}catch(e){t(new Error("解析响应失败: "+e.message))}})});o.on("error",e=>{console.error("支付请求错误:",e),t(e)}),o.on("timeout",()=>{o.destroy(),t(new Error("请求超时"))}),o.write(i),o.end()});return 200===c.code?{success:!0,orderNo:o,payUrl:c.data?c.data.pay_url:null,qrCode:c.data?c.data.qr_code:null,msg:"支付订单创建成功"}:{success:!1,msg:c.msg||"创建支付订单失败"}}catch(e){return console.error("创建支付订单失败:",e),{success:!1,msg:e.message||"网络请求失败"}}}),', '', 1);
rep(appCss, '.nav .tools .tool-btn.coffee-btn{font-size:14px}.nav .tools .tool-btn.coffee-btn:hover{animation:coffeeShake .5s ease;background:hsla(0,0%,100%,.1)}@keyframes coffeeShake{0%,to{transform:rotate(0deg)}25%{transform:rotate(-15deg)}75%{transform:rotate(15deg)}}', '', 1);
// 6.6 删除全部 sourcemap（开发用，非运行时必需，且会漏出已删代码与原始源码）
Object.keys(byPath).filter(p => p.endsWith('.js.map')).forEach(removeFile);

// 6.7 注入界面扩展脚本：右上角置顶+齿轮菜单（便签纸/字体颜色 RGBA、导出、使用指南）
if (process.env.SN_EXTRA_JS) {
  const extra = fs.readFileSync(process.env.SN_EXTRA_JS);
  addFile('/js/notes-plus.js', extra);
  // 带内容摘要做 cache-bust，避免 app:// 磁盘缓存继续跑旧脚本
  const ver = require('crypto').createHash('md5').update(extra).digest('hex').slice(0, 8);
  rep('/index.html', '</body>',
      '<script src="app://./js/notes-plus.js?v=' + ver + '"></script></body>', 1);
} else {
  console.log('  未提供 SN_EXTRA_JS，跳过界面扩展');
}

// 6.8 托盘：右键仅保留「退出」；隐藏/显示改为双击托盘图标
rep('/background.js',
    'a=[{label:"显示/隐藏",click:()=>{t&&t()}}];"function"==typeof o&&o()&&a.push({label:"🔓 解锁窗口",click:()=>{s&&s()}}),a.push({type:"separator"},{label:"设置",click:()=>{r&&r(),e&&e()}},{label:"开机启动",type:"checkbox",checked:z(),click(){$(!z())}},{type:"separator"},{label:"使用指南",click:()=>{i&&i(),e&&e()}},{type:"separator"},{label:"退出",role:"quit"}),M.setContextMenu(n.Menu.buildFromTemplate(a))',
    'a=[{label:"显示/隐藏",click:()=>{se()}},{label:"退出",role:"quit"}];M.setContextMenu(n.Menu.buildFromTemplate(a))',
    null);
rep('/background.js',
    'M.on("click",()=>{t&&t()}),M.on("double-click",()=>{t&&t()}),M.on("right-click",()=>{M.popUpContextMenu()})',
    'M.on("click",()=>{re()}),M.on("right-click",()=>{M.popUpContextMenu()})',
    null);

// 6.8.2 开机自启状态读写 IPC（供设置齿轮菜单使用）
rep('/background.js',
    'n.ipcMain.handle("getAlwaysOnTop",()=>!!V&&V.isAlwaysOnTop()),',
    'n.ipcMain.handle("getAlwaysOnTop",()=>!!V&&V.isAlwaysOnTop()),n.ipcMain.handle("getAutoLaunch",()=>z()),n.ipcMain.handle("setAutoLaunch",(e,t)=>{$(!!t);return z()}),',
    null);


// 6.8.3 标题修改历史同时记录当时的笔记，供详情分两行展示
repAll('i.history.push({datetime:O(),oldContent:i.content,newContent:t,oldColor:i.color,newColor:r||i.color})',
    'i.history.push({datetime:O(),oldContent:i.content,newContent:t,oldColor:i.color,newColor:r||i.color,oldNote:i.note||"",newNote:i.note||""})',
    1);

// 6.9 启动时清一次 HTTP 磁盘缓存，避免 app:// 继续用旧的 index.html / notes-plus.js
rep('/background.js',
    'n.app.on("ready",async()=>{',
    'n.app.on("ready",async()=>{try{await n.session.defaultSession.clearCache()}catch(e){}',
    null);

// 6.10 随包附带 LXGW WenKai Regular 字体（不依赖系统安装）
if (process.env.SN_EXTRA_FONT) {
  addFile('/fonts/LXGWWenKai-Regular.ttf', fs.readFileSync(process.env.SN_EXTRA_FONT));
  if (process.env.SN_EXTRA_FONT_LICENSE) {
    addFile('/fonts/OFL.txt', fs.readFileSync(process.env.SN_EXTRA_FONT_LICENSE));
  }
} else {
  console.log('  未提供 SN_EXTRA_FONT，跳过字体注入');
}

// 6.11 替换托盘图标（Windows 任务栏通知区默认还是 Electron 原子图标）
if (process.env.SN_EXTRA_TRAY) {
  const trayPng = fs.readFileSync(process.env.SN_EXTRA_TRAY);
  if (byPath['/tray.png']) { byPath['/tray.png'].data = trayPng; console.log('  替换 /tray.png (' + trayPng.length + ' 字节)'); }
  else { addFile('/tray.png', trayPng); }
}

// 6.5 sourcemap / 残留字符串
repAll('donate', '');
repAll('Donate', '');
repAll('打赏', '');
repAll('payment', '');
repAll('coffee', '');
repAll('3d3df498', '');
}

// 4) 自检：确认补丁生效、数量没被改坏
const all = files.map(f => f.data.toString('utf8')).join('\n');
for (const bad of ['"productName":"桌面便签"', 'title:"桌面便签', '"productName": "桌面便签"']) {
  if (all.indexOf(bad) >= 0) throw new Error('补丁未生效，仍存在: ' + bad);
}
for (const bad of ['xiaolin', '小林子', 'Powered by', '请作者喝咖啡']) {
  if (all.indexOf(bad) >= 0) throw new Error('作者信息未清除干净: ' + bad);
}
for (const bad of ['Donate', 'donate', '打赏', 'openDonateWindow', 'createPaymentOrder', 'wap2app', 'coffee', '3d3df498']) {
  if (all.indexOf(bad) >= 0) throw new Error('打赏功能未删干净: ' + bad);
}

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

# ---------------------------------------------------------------- 入口
OUT="${1:-app-patched.asar}"
# 界面扩展脚本（齿轮菜单 + 置顶按钮），默认取仓库里的 notes-plus.js
export SN_EXTRA_JS="${SN_EXTRA_JS:-$(cd "$(dirname "$0")" && pwd)/notes-plus.js}"
export SN_EXTRA_FONT="${SN_EXTRA_FONT:-$(cd "$(dirname "$0")" && pwd)/fonts/LXGWWenKai-Regular.ttf}"
export SN_EXTRA_FONT_LICENSE="${SN_EXTRA_FONT_LICENSE:-$(cd "$(dirname "$0")" && pwd)/fonts/OFL.txt}"

BIN="$APP_DIR/todo-list"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

printf '%s\n' "$PATCH_JS" > "$TMP/patch.js"
if [ -x "$BIN" ]; then
  ELECTRON_RUN_AS_NODE=1 ELECTRON_NO_ASAR=1 "$BIN" "$TMP/patch.js" "$ASAR" "$OUT"
elif command -v node >/dev/null 2>&1; then
  node "$TMP/patch.js" "$ASAR" "$OUT"
else
  die "找不到可用的 node 运行时（$BIN 与 node 都不可用）"
fi
