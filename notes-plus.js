/*
 * sticky note 界面扩展（渲染层注入脚本，不改动编译后的 Vue 代码）
 *
 * 1. 右上角工具条改为：隐藏到托盘 → 锁定 → 置顶 → 设置（齿轮）
 * 2. 齿轮菜单：便签纸颜色(RGBA)、字体颜色(RGBA)，各 9 个预选色；
 *    导出到 Excel、使用指南移入菜单
 *
 * 颜色存在 localStorage（随 Electron userData 持久化），不动 settings.json。
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

  var KEY_PAPER = 'sn.paper';
  var KEY_FONT = 'sn.font';

  // 便签纸 9 预选色 / 字体 9 预选色（含默认值）
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

  var style = document.createElement('style');
  style.textContent = [
    // 隐藏原有的「使用指南 / 导出」按钮（功能已移入齿轮菜单）
    '.nav .tools .help-btn,.nav .tools .icon-export{display:none!important}',
    // 便签纸颜色 / 字体颜色
    '#app{background-color:var(--sn-paper,#2d2d2d)}',
    'body.sn-paper-custom #app{background-color:var(--sn-paper)!important}',
    'body.sn-paper-custom .bg-color-layer{display:none!important}',
    'body.sn-font-custom .root .display p{color:var(--sn-font)!important}',
    // 新增按钮
    '.nav .tools .sn-btn{width:20px;height:20px;line-height:20px;text-align:center;cursor:pointer;',
    'border-radius:4px;font-size:13px;color:rgba(255,255,255,.6);display:flex;align-items:center;',
    'justify-content:center;transition:all .2s;-webkit-app-region:no-drag}',
    '.nav .tools .sn-btn:hover{color:rgba(255,255,255,.9);background:rgba(255,255,255,.1);transform:scale(1.1)}',
    '.nav .tools .sn-btn.sn-active{color:#feca57}',
    // 齿轮面板
    '.sn-panel{position:fixed;top:56px;right:10px;z-index:1002;width:236px;padding:12px;box-sizing:border-box;',
    'background:#2b2b2b;border:1px solid rgba(255,255,255,.12);border-radius:8px;',
    'box-shadow:0 8px 28px rgba(0,0,0,.5);color:#eaeaea;font-size:12px;user-select:none;-webkit-app-region:no-drag}',
    '.sn-panel.sn-hidden{display:none}',
    '.sn-sec{margin-bottom:12px}',
    '.sn-sec:last-child{margin-bottom:0}',
    '.sn-sec>label{display:block;color:rgba(255,255,255,.55);font-size:11px;margin-bottom:6px}',
    '.sn-swatches{display:flex;flex-wrap:wrap;gap:6px;margin-bottom:8px}',
    '.sn-sw{width:22px;height:22px;border-radius:50%;cursor:pointer;border:2px solid transparent;box-sizing:border-box}',
    '.sn-sw:hover{transform:scale(1.12)}',
    '.sn-sw.sn-on{border-color:#fff;box-shadow:0 0 6px rgba(255,255,255,.35)}',
    '.sn-row{display:flex;align-items:center;gap:6px;margin-bottom:8px}',
    '.sn-row input[type=color]{width:34px;height:22px;padding:0;border:1px solid rgba(255,255,255,.2);',
    'background:transparent;border-radius:4px;cursor:pointer}',
    '.sn-row input[type=range]{flex:1;min-width:0;-webkit-appearance:none;height:4px;border-radius:2px;',
    'background:rgba(255,255,255,.2);outline:none}',
    '.sn-row input[type=range]::-webkit-slider-thumb{-webkit-appearance:none;width:12px;height:12px;',
    'border-radius:50%;background:#54a0ff;cursor:pointer;border:1px solid #fff}',
    '.sn-alpha{width:34px;text-align:right;color:rgba(255,255,255,.6);font-variant-numeric:tabular-nums}',
    '.sn-apply{width:100%;padding:6px;border:1px solid rgba(255,255,255,.2);border-radius:5px;',
    'background:rgba(255,255,255,.06);color:#eaeaea;cursor:pointer;font-size:12px}',
    '.sn-apply:hover{background:rgba(255,255,255,.13)}',
    '.sn-reset{background:none;border:none;color:rgba(255,255,255,.45);cursor:pointer;font-size:11px;padding:0}',
    '.sn-reset:hover{color:rgba(255,255,255,.8)}',
    '.sn-hint{color:rgba(255,255,255,.35);font-size:11px;margin-top:4px}',
    '.sn-split{height:1px;background:rgba(255,255,255,.1);margin:10px 0}',
    '.sn-menu{display:flex;flex-direction:column;gap:2px}',
    '.sn-menu button{display:flex;align-items:center;gap:8px;width:100%;padding:7px 8px;border:none;',
    'border-radius:5px;background:none;color:#eaeaea;cursor:pointer;font-size:12px;text-align:left}',
    '.sn-menu button:hover{background:rgba(255,255,255,.1)}'
  ].join('');

  function hexToRgba(hex, alpha) {
    var h = String(hex || '').replace('#', '');
    if (h.length === 3) h = h[0] + h[0] + h[1] + h[1] + h[2] + h[2];
    var n = parseInt(h, 16);
    if (isNaN(n)) return 'rgba(45,45,45,' + alpha + ')';
    return 'rgba(' + ((n >> 16) & 255) + ',' + ((n >> 8) & 255) + ',' + (n & 255) + ',' + alpha + ')';
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
    try {
      localStorage.setItem(key, JSON.stringify({ hex: hex, alpha: alpha }));
    } catch (e) { /* 忽略 */ }
  }

  function applyPaper(c) {
    var css = hexToRgba(c.hex, c.alpha);
    document.documentElement.style.setProperty('--sn-paper', css);
    document.body.classList.add('sn-paper-custom');
  }

  function applyFont(c) {
    var css = hexToRgba(c.hex, c.alpha);
    document.documentElement.style.setProperty('--sn-font', css);
    document.body.classList.add('sn-font-custom');
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

  // ---------------------------------------------------------------- 齿轮面板
  var panel = null;

  function buildSection(title, presets, state, onApply, onReset) {
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
        syncSwatches();
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

    colorInput.oninput = function () { state.hex = colorInput.value; onApply(); syncSwatches(); };
    alphaInput.oninput = function () {
      state.alpha = Number(alphaInput.value) / 100;
      alphaText.textContent = alphaInput.value + '%';
      onApply();
    };

    function syncSwatches() {
      swNodes.forEach(function (s) {
        s.node.className = 'sn-sw' + (s.color.toLowerCase() === String(state.hex).toLowerCase() ? ' sn-on' : '');
      });
    }
    syncSwatches();

    var apply = document.createElement('button');
    apply.className = 'sn-apply';
    apply.textContent = '应用 ' + title;
    apply.onclick = onApply;
    wrap.appendChild(apply);

    var foot = document.createElement('div');
    foot.className = 'sn-hint';
    var reset = document.createElement('button');
    reset.className = 'sn-reset';
    reset.textContent = '恢复默认';
    reset.onclick = function () {
      onReset();
      alphaInput.value = '100';
      alphaText.textContent = '100%';
    };
    foot.appendChild(reset);
    wrap.appendChild(foot);

    return { node: wrap, colorInput: colorInput, alphaInput: alphaInput, alphaText: alphaText, sync: syncSwatches };
  }

  function buildPanel() {
    panel = document.createElement('div');
    panel.className = 'sn-panel sn-hidden';

    var paperState = loadColor(KEY_PAPER, '#2d2d2d');
    var fontState = loadColor(KEY_FONT, '#ffffff');

    var paper = buildSection('便签纸颜色', PAPER_PRESETS, paperState, function () {
      saveColor(KEY_PAPER, paperState.hex, paperState.alpha);
      applyPaper(paperState);
    }, resetPaper);
    panel.appendChild(paper.node);

    var font = buildSection('字体颜色', FONT_PRESETS, fontState, function () {
      saveColor(KEY_FONT, fontState.hex, fontState.alpha);
      applyFont(fontState);
    }, resetFont);
    panel.appendChild(font.node);

    var split = document.createElement('div');
    split.className = 'sn-split';
    panel.appendChild(split);

    var menu = document.createElement('div');
    menu.className = 'sn-menu';
    var exportBtn = document.createElement('button');
    exportBtn.textContent = '📤  导出到 Excel';
    exportBtn.onclick = function () { hidePanel(); ipc.invoke('exportData'); };
    var guideBtn = document.createElement('button');
    guideBtn.textContent = '💡  使用指南';
    guideBtn.onclick = function () { hidePanel(); ipc.invoke('openAboutWindow'); };
    menu.appendChild(exportBtn);
    menu.appendChild(guideBtn);
    panel.appendChild(menu);

    document.body.appendChild(panel);
    return { paper: paper, font: font };
  }

  function showPanel() {
    if (panel) panel.classList.remove('sn-hidden');
  }
  function hidePanel() {
    if (panel) panel.classList.add('sn-hidden');
  }
  function togglePanel() {
    if (!panel) return;
    if (panel.classList.contains('sn-hidden')) showPanel(); else hidePanel();
  }

  // ---------------------------------------------------------------- 工具条
  var gearBtn = null;

  function makeButton(text, title) {
    var b = document.createElement('span');
    b.className = 'sn-btn';
    b.textContent = text;
    b.title = title;
    return b;
  }

  function inject() {
    var tools = document.querySelector('#app .nav .tools');
    if (!tools || tools.querySelector('.sn-gear')) return;

    var pin = makeButton('📌', '置顶（始终在最前）');
    pin.className += ' sn-pin';
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

    var gear = makeButton('⚙', '设置');
    gear.className += ' sn-gear';
    gear.onclick = function (e) {
      e.stopPropagation();
      togglePanel();
    };

    tools.appendChild(pin);   // 隐藏到托盘 → 锁定 → 置顶 → 设置
    tools.appendChild(gear);
    gearBtn = gear;

    if (!panel) buildPanel();
    hidePanel();

    var paperState = loadColor(KEY_PAPER, '#2d2d2d');
    var fontState = loadColor(KEY_FONT, '#ffffff');
    if (localStorage.getItem(KEY_PAPER)) applyPaper(paperState);
    if (localStorage.getItem(KEY_FONT)) applyFont(fontState);
  }

  document.addEventListener('click', function (e) {
    if (!panel || panel.classList.contains('sn-hidden')) return;
    if (panel.contains(e.target) || (gearBtn && gearBtn.contains(e.target))) return;
    hidePanel();
  });
  document.addEventListener('keydown', function (e) {
    if (e.key === 'Escape') hidePanel();
  });

  if (document.body) {
    document.head.appendChild(style);
  } else {
    document.addEventListener('DOMContentLoaded', function () { document.head.appendChild(style); });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', boot);
  } else {
    boot();
  }

  function boot() {
    inject();
    // Vue 渲染/路由切换可能重建工具条，监听后补挂
    var app = document.getElementById('app');
    if (app && typeof MutationObserver !== 'undefined') {
      new MutationObserver(function () { inject(); }).observe(app, { childList: true, subtree: true });
    }
  }
})();
