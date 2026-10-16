/*
 * sticky note 界面扩展（渲染层注入脚本，不改动编译后的 Vue 代码）
 *
 * 1. 右上角工具条：隐藏到托盘 → 锁定 → 置顶 → 设置（齿轮）
 * 2. 齿轮菜单：便签纸颜色(RGBA)、便签文字颜色(RGBA)、软件字体颜色(RGBA)，
 *    各 9 个预选色；导出到 Excel、使用指南移入菜单
 * 3. 图标统一为 Apple 风格极简线性 SVG（细描边、圆端头、单色 currentColor）
 *
 * 颜色存 localStorage（随 Electron userData 持久化），不动 settings.json。
 */
(function () {
  'use strict';

  var electron;
  try {
    electron = require('electron');
  } catch (e) {
    return;
  }
  var ipc = electron.ipcRenderer;
  if (!ipc) return;

  var KEY_PAPER = 'sn.paper';   // 便签纸底色
  var KEY_FONT = 'sn.font';     // 便签文字颜色
  var KEY_UI = 'sn.ui';         // 软件界面字体颜色

  var PAPER_PRESETS = [
    { name: '默认深灰', color: '#2d2d2d' },
    { name: '纯黑', color: '#1a1a1a' },
    { name: '纯白', color: '#ffffff' },
    { name: '米黄', color: '#fdf6e3' },
    { name: '鹅黄', color: '#fff9c4' },
    { name: '淡绿', color: '#c8e6c9' },
    { name: '淡蓝', color: '#bbdefb' },
    { name: '淡粉', color: '#f8bbd0' },
    { name: '淡紫', color: '#d1c4e9' }
  ];
  var FONT_PRESETS = [
    { name: '白色', color: '#ffffff' },
    { name: '黑色', color: '#1a1a1a' },
    { name: '红色', color: '#ff6b6b' },
    { name: '橙色', color: '#ff9f43' },
    { name: '黄色', color: '#feca57' },
    { name: '绿色', color: '#1dd1a1' },
    { name: '蓝色', color: '#54a0ff' },
    { name: '紫色', color: '#a29bfe' },
    { name: '品红', color: '#e056fd' }
  ];
  var UI_PRESETS = [
    { name: '默认白', color: '#ffffff' },
    { name: '浅灰', color: '#c8c8c8' },
    { name: '深灰', color: '#8a8a8a' },
    { name: '纯黑', color: '#1a1a1a' },
    { name: '蓝色', color: '#54a0ff' },
    { name: '绿色', color: '#1dd1a1' },
    { name: '橙黄', color: '#feca57' },
    { name: '红色', color: '#ff6b6b' },
    { name: '紫色', color: '#a29bfe' }
  ];

  // ------------------------------------------------------------ Apple 风线性图标
  // 24x24 viewBox，stroke 由 CSS 统一给（currentColor / 1.6 / round）
  var ICONS = {
    gear: '<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 1 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06A1.65 1.65 0 0 0 4.6 15a1.65 1.65 0 0 0-1.51-1H3a2 2 0 1 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06A1.65 1.65 0 0 0 9 4.6a1.65 1.65 0 0 0 1-1.51V3a2 2 0 1 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06A1.65 1.65 0 0 0 19.4 9v.09a1.65 1.65 0 0 0 1.51 1H21a2 2 0 1 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z"/>',
    pin: '<path d="M12 17v5"/><path d="M9 10.8V5.2a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1v5.6l1.9 2.4a1 1 0 0 1 .1 1.2 1 1 0 0 1-.9.6H7.9a1 1 0 0 1-.9-.6 1 1 0 0 1 .1-1.2z"/>',
    pinOff: '<path d="M12 17v5"/><path d="M9 10.8V5.2a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1v3"/><path d="M4 4l16 16"/>',
    eyeOff: '<path d="M17.94 17.94A10.07 10.07 0 0 1 12 20c-7 0-11-8-11-8a18.45 18.45 0 0 1 5.06-5.94M9.9 4.24A9.12 9.12 0 0 1 12 4c7 0 11 8 11 8a18.5 18.5 0 0 1-2.16 3.19m-6.72-1.07a3 3 0 1 1-4.24-4.24"/><path d="M1 1l22 22"/>',
    lock: '<rect x="4" y="11" width="16" height="10" rx="2"/><path d="M8 11V7a4 4 0 0 1 8 0v4"/>',
    unlock: '<rect x="4" y="11" width="16" height="10" rx="2"/><path d="M8 11V7a4 4 0 0 1 7.5-2"/>',
    x: '<path d="M18 6L6 18M6 6l12 12"/>',
    check: '<path d="M20 6L9 17l-5-5"/>',
    clock: '<circle cx="12" cy="12" r="9"/><path d="M12 7.5V12l3 2"/>',
    download: '<path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><path d="M7 10l5 5 5-5"/><path d="M12 15V3"/>',
    book: '<path d="M4 4.5A1.5 1.5 0 0 1 5.5 3H19v18H5.5A1.5 1.5 0 0 1 4 19.5z"/><path d="M4 17.5A1.5 1.5 0 0 1 5.5 16H19"/>',
    image: '<rect x="3" y="4" width="18" height="16" rx="2"/><circle cx="8.5" cy="9.5" r="1.5"/><path d="M21 16l-4.5-4.5L7 21"/>',
    plus: '<path d="M12 5v14M5 12h14"/>',
    minus: '<path d="M5 12h14"/>',
    arrowLeft: '<path d="M19 12H5M12 19l-7-7 7-7"/>',
    bulb: '<path d="M9 18h6"/><path d="M10 21h4"/><path d="M12 3a6 6 0 0 0-3.6 10.8A4 4 0 0 1 9 17h6a4 4 0 0 1 .6-3.2A6 6 0 0 0 12 3z"/>',
    target: '<circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="5"/><circle cx="12" cy="12" r="1.5"/>',
    star: '<path d="M12 3l2.8 5.7 6.2.9-4.5 4.4 1.1 6.2L12 17.3 6.4 20.2l1.1-6.2L3 9.6l6.2-.9z"/>',
    refresh: '<path d="M21 12a9 9 0 1 1-2.6-6.4"/><path d="M21 4v4h-4"/>',
    pencil: '<path d="M12 20h9"/><path d="M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4z"/>',
    trash: '<path d="M3 6h18"/><path d="M8 6V4h8v2"/><path d="M19 6l-1 14a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2L5 6"/>'
  };

  // 界面上残留的 emoji → 同风格线性图标（在渲染层直接换掉，不动编译产物）
  var EMOJI_ICONS = {
    '\u{1F4DD}': 'pencil',      // 📝 空状态
    '\u{1F5D1}': 'trash',       // 🗑 删除
    '\u{1F504}': 'refresh',     // 🔄 需要重启
    '\u2699': 'gear',           // ⚙ 设置标题
    '\u{1F4A1}': 'bulb',        // 💡 提示
    '\u{1F4D6}': 'book',        // 📖 使用指南
    '\u{1F3AF}': 'target',      // 🎯 基本功能
    '\u2728': 'star'            // ✨ 特色功能
  };

  function svg(name, size) {
    return '<svg viewBox="0 0 24 24" width="' + (size || 17) + '" height="' + (size || 17) +
      '" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" ' +
      'stroke-linejoin="round" aria-hidden="true">' + ICONS[name] + '</svg>';
  }

  // 把 data URI 用的 SVG 编码成 mask（alpha 决定形状）
  function maskUri(name) {
    var s = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" ' +
      'stroke="#000" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round">' +
      ICONS[name] + '</svg>';
    return 'url("data:image/svg+xml,' + encodeURIComponent(s).replace(/'/g, '%27') + '")';
  }

  // 原有 iconfont 图标 → Apple 风线性图标（保留元素本身，只换外观）
  var ICON_GLYPHS = {
    '.icon-lock': 'lock',
    '.icon-unlock': 'unlock',
    '.icon-eye-close': 'eyeOff',
    '.icon-export': 'download',
    '.icon-select': 'check',
    '.icon-close': 'x',
    '.icon-history': 'clock',
    '.icon-back': 'arrowLeft',
    '.icon-add': 'plus',
    '.icon-minus': 'minus',
    '.icon-browse': 'image'
  };

  var css = [
    // ---- 工具条按钮显隐（导出 / 指南移入齿轮菜单）
    '#app .nav .tools .help-btn,#app .nav .tools .icon-export{display:none!important}',

    // ---- iconfont 替换为线性 SVG（mask 用 currentColor，保留原 hover/状态色）
    '#app .iconfont{-webkit-text-fill-color:transparent}',
    '#app .iconfont::before{content:""!important;display:block;width:1em;height:1em;',
    'background-color:currentColor;-webkit-mask-repeat:no-repeat;mask-repeat:no-repeat;',
    '-webkit-mask-position:center;mask-position:center;-webkit-mask-size:contain;mask-size:contain}',
    '#app .nav .tools .iconfont::before{width:17px;height:17px}',
    '#app .nav .tools .lock-btn::before{width:18px;height:18px}',

    // ---- 便签纸颜色
    '#app{background-color:var(--sn-paper,#2d2d2d)}',
    'body.sn-paper-custom #app{background-color:var(--sn-paper)!important}',
    'body.sn-paper-custom .bg-color-layer{display:none!important}',

    // ---- 便签文字颜色（只作用于便签内容）
    'body.sn-font-custom #app .root .display p{color:var(--sn-font)!important}',

    // ---- 软件界面字体颜色（chrome 文字，不含便签内容）
    'body.sn-ui-custom #app{color:var(--sn-ui)!important}',
    'body.sn-ui-custom #app .drag-nav b,body.sn-ui-custom #app .drag-nav i,',
    'body.sn-ui-custom #app .nav,body.sn-ui-custom #app .nav .link a,',
    'body.sn-ui-custom #app .nav .link .divider,body.sn-ui-custom #app .nav .tools i,',
    'body.sn-ui-custom #app .nav .tools .tool-btn,body.sn-ui-custom #app .nav .tools .sn-btn,',
    'body.sn-ui-custom #app .empty-state,body.sn-ui-custom #app .empty-state p,',
    'body.sn-ui-custom #app .display .index,body.sn-ui-custom #app .display .history-icon,',
    'body.sn-ui-custom #app .list .group,body.sn-ui-custom #app .edit-textarea,',
    'body.sn-ui-custom #app .edit-shortcuts span,body.sn-ui-custom #app .switch-label,',
    'body.sn-ui-custom #app .modal h3,body.sn-ui-custom #app .modal-body>p,',
    'body.sn-ui-custom #app .modal-body label,body.sn-ui-custom #app .modal-body small,',
    'body.sn-ui-custom #app .detail-item:not(.current) p,body.sn-ui-custom #app .detail-item small,',
    'body.sn-ui-custom #app .history-item .history-time,body.sn-ui-custom #app .change .old,',
    'body.sn-ui-custom #app .change .new,body.sn-ui-custom #app .change .icon-arrow-right,',
    'body.sn-ui-custom #app .delete-confirm-body p,body.sn-ui-custom #app .delete-confirm-item,',
    'body.sn-ui-custom #app .setting-section label,body.sn-ui-custom #app .setting-section .setting-hint,',
    'body.sn-ui-custom #app .upload-area span,body.sn-ui-custom #app .upload-area small,',
    'body.sn-ui-custom #app .upload-area i,body.sn-ui-custom #app .btn-export,',
    'body.sn-ui-custom #app .about-body,body.sn-ui-custom #app .about-body *',
    '{color:var(--sn-ui)!important}',

    // ---- 新增按钮
    '#app .nav .tools .sn-btn{width:20px;height:20px;cursor:pointer;border-radius:5px;',
    'display:flex;align-items:center;justify-content:center;transition:background .18s,color .18s,transform .18s;',
    '-webkit-app-region:no-drag}',
    '#app .nav .tools .sn-btn:hover{background:rgba(150,150,150,.22)}',
    '#app .nav .tools .sn-btn:active{transform:scale(.92)}',
    '#app .nav .tools .sn-btn.sn-active{color:#feca57}',
    // 图钉启用后斜过来（钉住了）
    '#app .nav .tools .sn-pin svg{transition:transform .2s ease}',
    '#app .nav .tools .sn-pin.sn-active svg{transform:rotate(45deg)}',
    '#app .nav .tools .sn-gear.sn-open{background:rgba(150,150,150,.22)}',

    // ---- 齿轮面板（小窗口可滚动，不被裁掉）
    '.sn-panel{position:fixed;top:52px;right:10px;z-index:1002;',
    'width:min(240px,calc(100vw - 20px));box-sizing:border-box;padding:12px;',
    'max-height:calc(100vh - 62px);overflow-y:auto;overflow-x:hidden;overscroll-behavior:contain;',
    'background:var(--sn-surface,#2b2b2b);border:1px solid rgba(150,150,150,.22);border-radius:10px;',
    'box-shadow:0 10px 30px rgba(0,0,0,.45);color:var(--sn-surface-fg,#eaeaea);font-size:12px;',
    'user-select:none;-webkit-app-region:no-drag}',
    '.sn-panel::-webkit-scrollbar{width:5px}',
    '.sn-panel::-webkit-scrollbar-track{background:transparent}',
    '.sn-panel::-webkit-scrollbar-thumb{background:rgba(150,150,150,.35);border-radius:3px}',
    '.sn-panel::-webkit-scrollbar-thumb:hover{background:rgba(150,150,150,.55)}',
    '.sn-panel.sn-hidden{display:none}',
    '.sn-sec{margin-bottom:12px}',
    '.sn-sec:last-child{margin-bottom:0}',
    '.sn-sec>label{display:block;color:var(--sn-surface-dim,rgba(255,255,255,.55));font-size:11px;margin-bottom:6px}',
    '.sn-swatches{display:flex;flex-wrap:wrap;gap:6px;margin-bottom:8px}',
    '.sn-sw{width:22px;height:22px;border-radius:50%;cursor:pointer;border:2px solid transparent;box-sizing:border-box;',
    'transition:transform .15s,border-color .15s}',
    '.sn-sw:hover{transform:scale(1.12)}',
    '.sn-sw.sn-on{border-color:var(--sn-surface-fg,#fff);box-shadow:0 0 6px rgba(150,150,150,.4)}',
    '.sn-row{display:flex;align-items:center;gap:6px;margin-bottom:8px}',
    '.sn-row input[type=color]{width:34px;height:22px;padding:0;border:1px solid rgba(150,150,150,.35);',
    'background:transparent;border-radius:5px;cursor:pointer}',
    '.sn-row input[type=range]{flex:1;min-width:0;-webkit-appearance:none;height:4px;border-radius:2px;',
    'background:rgba(150,150,150,.3);outline:none}',
    '.sn-row input[type=range]::-webkit-slider-thumb{-webkit-appearance:none;width:13px;height:13px;',
    'border-radius:50%;background:#54a0ff;cursor:pointer;border:1px solid #fff}',
    '.sn-alpha{width:34px;text-align:right;color:var(--sn-surface-dim,rgba(255,255,255,.6));',
    'font-variant-numeric:tabular-nums}',
    '.sn-val{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:11px;',
    'color:var(--sn-surface-dim,rgba(255,255,255,.5));margin:-2px 0 8px;letter-spacing:.2px}',
    '.sn-apply{width:100%;padding:6px;border:1px solid rgba(150,150,150,.3);border-radius:6px;',
    'background:rgba(150,150,150,.12);color:var(--sn-surface-fg,#eaeaea);cursor:pointer;font-size:12px;',
    'transition:background .18s}',
    '.sn-apply:hover{background:rgba(150,150,150,.22)}',
    '.sn-reset{background:none;border:none;color:var(--sn-surface-dim,rgba(255,255,255,.45));cursor:pointer;',
    'font-size:11px;padding:0}',
    '.sn-reset:hover{color:var(--sn-surface-fg,rgba(255,255,255,.85))}',
    '.sn-hint{color:var(--sn-surface-dim,rgba(255,255,255,.35));font-size:11px;margin-top:4px}',
    '.sn-split{height:1px;background:rgba(150,150,150,.22);margin:10px 0}',
    '.sn-menu{display:flex;flex-direction:column;gap:2px}',
    '.sn-menu button{display:flex;align-items:center;gap:8px;width:100%;padding:7px 8px;border:none;',
    'border-radius:6px;background:none;color:var(--sn-surface-fg,#eaeaea);cursor:pointer;font-size:12px;',
    'text-align:left;transition:background .18s}',
    '.sn-menu button:hover{background:rgba(150,150,150,.18)}',
    '.sn-menu button svg{flex-shrink:0}',

    // ---- emoji 替换成线性图标后的容器
    '.sn-emoji{display:inline-flex;align-items:center;justify-content:center;vertical-align:-.15em}',
    '.sn-emoji svg{width:1em;height:1em}'
  ].join('');

  // ---------------------------------------------------------------- 颜色工具
  function parseHex(hex) {
    var h = String(hex || '').replace('#', '');
    if (h.length === 3) h = h[0] + h[0] + h[1] + h[1] + h[2] + h[2];
    var n = parseInt(h, 16);
    if (isNaN(n)) return { r: 45, g: 45, b: 45 };
    return { r: (n >> 16) & 255, g: (n >> 8) & 255, b: n & 255 };
  }

  function hexToRgba(hex, alpha) {
    var c = parseHex(hex);
    return 'rgba(' + c.r + ',' + c.g + ',' + c.b + ',' + alpha + ')';
  }

  // ponytail: 以默认深色底 (#2d2d2d) 估算对比度，足够决定面板用深字还是浅字
  function isLightOnDark(hex, alpha) {
    var c = parseHex(hex);
    var bg = { r: 45, g: 45, b: 45 };
    var r = c.r * alpha + bg.r * (1 - alpha);
    var g = c.g * alpha + bg.g * (1 - alpha);
    var b = c.b * alpha + bg.b * (1 - alpha);
    return (0.299 * r + 0.587 * g + 0.114 * b) > 150;
  }

  function loadColor(key, fallbackHex) {
    try {
      var raw = localStorage.getItem(key);
      if (!raw) return { hex: fallbackHex, alpha: 1 };
      var v = JSON.parse(raw);
      return { hex: v.hex || fallbackHex, alpha: typeof v.alpha === 'number' ? v.alpha : 1 };
    } catch (e) {
      return { hex: fallbackHex, alpha: 1 };
    }
  }

  function saveColor(key, hex, alpha) {
    try { localStorage.setItem(key, JSON.stringify({ hex: hex, alpha: alpha })); } catch (e) { /* 忽略 */ }
  }

  var panelRefs = null;

  // 界面字体颜色变化时同步面板自身：底色与文字保持高对比，编辑取色时也看得清
  function syncPanelContrast(c) {
    if (!panelRefs) return;
    var root = document.documentElement;
    if (isLightOnDark(c.hex, c.alpha)) {
      root.style.setProperty('--sn-surface', '#2b2b2b');
      root.style.setProperty('--sn-surface-fg', '#f2f2f2');
      root.style.setProperty('--sn-surface-dim', 'rgba(242,242,242,.6)');
    } else {
      root.style.setProperty('--sn-surface', '#f7f7f7');
      root.style.setProperty('--sn-surface-fg', '#1c1c1c');
      root.style.setProperty('--sn-surface-dim', 'rgba(28,28,28,.55)');
    }
  }

  function applyPaper(c) {
    document.documentElement.style.setProperty('--sn-paper', hexToRgba(c.hex, c.alpha));
    document.body.classList.add('sn-paper-custom');
  }
  function applyFont(c) {
    document.documentElement.style.setProperty('--sn-font', hexToRgba(c.hex, c.alpha));
    document.body.classList.add('sn-font-custom');
  }
  function applyUi(c) {
    document.documentElement.style.setProperty('--sn-ui', hexToRgba(c.hex, c.alpha));
    document.body.classList.add('sn-ui-custom');
    syncPanelContrast(c);
  }
  function resetPaper() {
    document.documentElement.style.removeProperty('--sn-paper');
    document.body.classList.remove('sn-paper-custom');
    try { localStorage.removeItem(KEY_PAPER); } catch (e) { /* 忽略 */ }
  }
  function resetFont() {
    document.documentElement.style.removeProperty('--sn-font');
    document.body.classList.remove('sn-font-custom');
    try { localStorage.removeItem(KEY_FONT); } catch (e) { /* 忽略 */ }
  }
  function resetUi() {
    document.documentElement.style.removeProperty('--sn-ui');
    document.body.classList.remove('sn-ui-custom');
    document.documentElement.style.removeProperty('--sn-surface');
    document.documentElement.style.removeProperty('--sn-surface-fg');
    document.documentElement.style.removeProperty('--sn-surface-dim');
    try { localStorage.removeItem(KEY_UI); } catch (e) { /* 忽略 */ }
  }

  // ---------------------------------------------------------------- 齿轮面板
  var panel = null;

  function buildSection(title, presets, state, onApply, onReset, defaultHex) {
    var wrap = document.createElement('div');
    wrap.className = 'sn-sec';

    var label = document.createElement('label');
    label.textContent = title;
    wrap.appendChild(label);

    var swatches = document.createElement('div');
    swatches.className = 'sn-swatches';
    var swNodes = [];
    presets.forEach(function (p) {
      var dot = document.createElement('span');
      dot.className = 'sn-sw';
      dot.style.background = p.color;
      dot.title = p.name + ' ' + p.color;
      dot.onclick = function () {
        state.hex = p.color;
        colorInput.value = p.color;
        onApply();
        sync();
      };
      swNodes.push({ node: dot, color: p.color });
      swatches.appendChild(dot);
    });
    wrap.appendChild(swatches);

    var row = document.createElement('div');
    row.className = 'sn-row';
    var colorInput = document.createElement('input');
    colorInput.type = 'color';
    colorInput.value = state.hex;
    var alphaInput = document.createElement('input');
    alphaInput.type = 'range';
    alphaInput.min = '0';
    alphaInput.max = '100';
    alphaInput.value = String(Math.round(state.alpha * 100));
    var alphaText = document.createElement('span');
    alphaText.className = 'sn-alpha';
    alphaText.textContent = alphaInput.value + '%';
    row.appendChild(colorInput);
    row.appendChild(alphaInput);
    row.appendChild(alphaText);
    wrap.appendChild(row);

    // 当前 RGBA 值实时回显，避免只看到 HEX 以为没透明度
    var valText = document.createElement('div');
    valText.className = 'sn-val';
    wrap.appendChild(valText);

    colorInput.oninput = function () { state.hex = colorInput.value; onApply(); sync(); };
    alphaInput.oninput = function () {
      state.alpha = Number(alphaInput.value) / 100;
      alphaText.textContent = alphaInput.value + '%';
      onApply();
      updateVal();
    };

    function rgbaText() {
      var c = parseHex(state.hex);
      return 'rgba(' + c.r + ', ' + c.g + ', ' + c.b + ', ' + state.alpha.toFixed(2).replace(/\.?0+$/, '') + ')';
    }
    function updateVal() { valText.textContent = rgbaText(); }

    function sync() {
      swNodes.forEach(function (s) {
        s.node.className = 'sn-sw' + (s.color.toLowerCase() === String(state.hex).toLowerCase() ? ' sn-on' : '');
      });
      updateVal();
    }
    sync();

    var apply = document.createElement('button');
    apply.className = 'sn-apply';
    apply.textContent = '应用' + title;
    apply.onclick = onApply;
    wrap.appendChild(apply);

    var foot = document.createElement('div');
    foot.className = 'sn-hint';
    var reset = document.createElement('button');
    reset.className = 'sn-reset';
    reset.textContent = '恢复默认';
    reset.onclick = function () {
      onReset();
      state.hex = defaultHex;
      state.alpha = 1;
      colorInput.value = defaultHex;
      alphaInput.value = '100';
      alphaText.textContent = '100%';
      sync();
    };
    foot.appendChild(reset);
    wrap.appendChild(foot);

    return { node: wrap };
  }

  function buildPanel() {
    panel = document.createElement('div');
    panel.className = 'sn-panel sn-hidden';

    var paperState = loadColor(KEY_PAPER, '#2d2d2d');
    var fontState = loadColor(KEY_FONT, '#ffffff');
    var uiState = loadColor(KEY_UI, '#ffffff');

    var paperSec = buildSection('便签纸颜色', PAPER_PRESETS, paperState, function () {
      saveColor(KEY_PAPER, paperState.hex, paperState.alpha);
      applyPaper(paperState);
    }, resetPaper, '#2d2d2d');
    panel.appendChild(paperSec.node);

    var fontSec = buildSection('便签文字颜色', FONT_PRESETS, fontState, function () {
      saveColor(KEY_FONT, fontState.hex, fontState.alpha);
      applyFont(fontState);
    }, resetFont, '#ffffff');
    panel.appendChild(fontSec.node);

    var uiSec = buildSection('软件字体颜色', UI_PRESETS, uiState, function () {
      saveColor(KEY_UI, uiState.hex, uiState.alpha);
      applyUi(uiState);
    }, resetUi, '#ffffff');
    panel.appendChild(uiSec.node);

    var split = document.createElement('div');
    split.className = 'sn-split';
    panel.appendChild(split);

    var menu = document.createElement('div');
    menu.className = 'sn-menu';
    var exportBtn = document.createElement('button');
    exportBtn.innerHTML = svg('download', 16) + '<span>导出到 Excel</span>';
    exportBtn.onclick = function () { hidePanel(); ipc.invoke('exportData'); };
    var guideBtn = document.createElement('button');
    guideBtn.innerHTML = svg('book', 16) + '<span>使用指南</span>';
    guideBtn.onclick = function () { hidePanel(); ipc.invoke('openAboutWindow'); };
    menu.appendChild(exportBtn);
    menu.appendChild(guideBtn);
    panel.appendChild(menu);

    document.body.appendChild(panel);
    panelRefs = { paper: paperSec, font: fontSec, ui: uiSec };
    syncPanelContrast(uiState);
  }

  function panelOpen() { return panel && !panel.classList.contains('sn-hidden'); }
  function showPanel() { if (panel) panel.classList.remove('sn-hidden'); }
  function hidePanel() { if (panel) panel.classList.add('sn-hidden'); }
  function togglePanel() { if (panelOpen()) hidePanel(); else showPanel(); }

  // ---------------------------------------------------------------- 工具条
  var gearBtn = null;

  function setIcon(el, name, size) {
    el.innerHTML = svg(name, size);
  }

  function inject() {
    var tools = document.querySelector('#app .nav .tools');
    if (!tools || tools.querySelector('.sn-gear')) return;

    var pin = document.createElement('span');
    pin.className = 'sn-btn sn-pin';
    pin.title = '置顶（始终在最前）';
    setIcon(pin, 'pin');
    pin.onclick = function () {
      ipc.invoke('toggleAlwaysOnTop').then(function (on) {
        pin.classList.toggle('sn-active', !!on);
        pin.title = on ? '取消置顶' : '置顶（始终在最前）';
      });
    };
    ipc.invoke('getAlwaysOnTop').then(function (on) {
      pin.classList.toggle('sn-active', !!on);
      if (on) pin.title = '取消置顶';
    });

    var gear = document.createElement('span');
    gear.className = 'sn-btn sn-gear';
    gear.title = '设置';
    setIcon(gear, 'gear');
    gear.onclick = function (e) {
      e.stopPropagation();
      togglePanel();
      gear.classList.toggle('sn-open', panelOpen());
    };

    tools.appendChild(pin);   // 隐藏到托盘 → 锁定 → 置顶 → 设置
    tools.appendChild(gear);
    gearBtn = gear;

    if (!panel) buildPanel();
    hidePanel();

    if (localStorage.getItem(KEY_PAPER)) applyPaper(loadColor(KEY_PAPER, '#2d2d2d'));
    if (localStorage.getItem(KEY_FONT)) applyFont(loadColor(KEY_FONT, '#ffffff'));
  }

  // 启动时套用已保存的界面字体颜色
  function restoreUi() {
    if (localStorage.getItem(KEY_UI)) applyUi(loadColor(KEY_UI, '#ffffff'));
  }

  var style = document.createElement('style');
  style.textContent = css;
  var glyphCss = Object.keys(ICON_GLYPHS).map(function (sel) {
    return '#app ' + sel + '::before{-webkit-mask-image:' + maskUri(ICON_GLYPHS[sel]) +
      ';mask-image:' + maskUri(ICON_GLYPHS[sel]) + '}';
  }).join('');
  style.textContent += glyphCss;

  document.addEventListener('click', function (e) {
    if (!panelOpen()) return;
    if (panel.contains(e.target)) return;
    if (gearBtn && gearBtn.contains(e.target)) return;
    hidePanel();
    if (gearBtn) gearBtn.classList.remove('sn-open');
  });
  document.addEventListener('keydown', function (e) {
    if (e.key === 'Escape' && panelOpen()) {
      hidePanel();
      if (gearBtn) gearBtn.classList.remove('sn-open');
    }
  });

  // 把界面里残留的 emoji 换成线性 SVG（幂等：替换后是元素，不会重复处理）
  var EMOJI_SRC = '[\\u{1F300}-\\u{1FAFF}\\u2600-\\u27BF\\u2B00-\\u2BFF]\\uFE0F?';
  var EMOJI_RE = new RegExp(EMOJI_SRC, 'gu');
  var EMOJI_TEST = new RegExp(EMOJI_SRC, 'u');
  function deEmoji(root) {
    if (!root || typeof document.createTreeWalker !== 'function') return;
    var walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, null, false);
    var nodes = [];
    var n;
    while ((n = walker.nextNode())) {
      if (n.parentNode && n.parentNode.classList && n.parentNode.classList.contains('sn-emoji')) continue;
      if (EMOJI_TEST.test(n.nodeValue)) nodes.push(n);
    }
    nodes.forEach(function (node) {
      var parts = node.nodeValue.split(EMOJI_RE);
      var found = node.nodeValue.match(EMOJI_RE) || [];
      if (!found.length) return;
      var frag = document.createDocumentFragment();
      parts.forEach(function (txt, i) {
        if (txt) frag.appendChild(document.createTextNode(txt));
        if (i < found.length) {
          var key = found[i].replace(/\uFE0F/g, '');
          if (!EMOJI_ICONS[key]) { frag.appendChild(document.createTextNode(found[i])); return; }
          var span = document.createElement('span');
          span.className = 'sn-emoji';
          span.innerHTML = svg(EMOJI_ICONS[key], 16);
          frag.appendChild(span);
        }
      });
      node.parentNode.replaceChild(frag, node);
    });
  }

  function boot() {
    document.head.appendChild(style);
    restoreUi();
    inject();
    deEmoji(document.getElementById('app'));
    var app = document.getElementById('app');
    if (app && typeof MutationObserver !== 'undefined') {
      new MutationObserver(function () {
        inject();
        deEmoji(app);
      }).observe(app, { childList: true, subtree: true });
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', boot);
  } else if (document.body) {
    boot();
  } else {
    document.addEventListener('DOMContentLoaded', boot);
  }
})();
