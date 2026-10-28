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
