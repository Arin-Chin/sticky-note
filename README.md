# sticky-note-debrand

UOS / Deepin 上「桌面便签」（Electron，`/opt/桌面便签/todo-list`）的自用精简补丁：
去掉打赏图标和标题栏多余文字，应用名改成 `sticky note`，其余功能原样保留。

- **不需要**重新编译，**不需要**联网，**不需要**下载原程序
- 直接补丁你本机已安装的那份 `app.asar`，原文件自动备份
- 便签数据目录 `~/.config/todo-list` 不变，历史数据照常用

## 效果

| 项目 | 原版 | 补丁后 |
|---|---|---|
| 工具栏 ☕「请作者喝咖啡」 | 显示 | 隐藏 |
| 左上角应用名 | 桌面便签 | 隐藏 |
| 右上角标语 | 记清，办明，不遗漏 | 隐藏 |
| 应用名（标题/启动器/托盘） | 桌面便签 | sticky note |
| 待办 / 已完成 / 导出 / 锁定 / 设置 | 有 | 不变 |
| 数据目录 | `~/.config/todo-list` | 不变 |

工具栏保留：使用指南、导出 Excel、隐藏到托盘、锁定（鼠标穿透）。窗口拖动区仍在，不受隐藏文字影响。

## 安装

```bash
git clone https://github.com/Arin-Chin/sticky-note-debrand.git
cd sticky-note-debrand
sudo bash install.sh
```

会在需要时提示输入 sudo 密码。安装完自动重启应用，启动器里出现 `sticky note`。

## 卸载（还原原版）

```bash
sudo bash install.sh uninstall
```

## 只生成补丁包，先检查不改系统

```bash
bash install.sh build /tmp/app.asar    # 免密码，输出打好补丁的 asar
```

应用装在非默认目录时：

```bash
SN_APP_DIR=/path/to/桌面便签 sudo -E bash install.sh
```

## 原理

1. 解析 `resources/app.asar`（Electron 归档格式）到内存
2. 文本替换：`package.json` / `background.js` / `js/app.<hash>.js` 里的 `productName` 与窗口标题，`index.html` 的 `<title>`
3. 在 `css/app.<hash>.css` 末尾追加一条 CSS 规则隐藏打赏按钮和标题栏文字：
   ```css
   .drag-nav b, .drag-nav i, .tool-btn.coffee-btn { display: none !important; }
   ```
4. 自检通过后重新打包，就地替换原 `app.asar`（备份为 `resources/app.asar.orig`）

只在做了文本替换且自检通过后才写入；替换处数量对不上会直接报错退出，不会写出半成品。

## 兼容性

- 在 UOS Desktop 20 Professional（`桌面便签` v0.2.3，Electron 13）上实测通过
- 脚本按 `app.<hash>.js` 通配定位文件，小版本更新后 hash 变化仍可使用；逻辑改动过大时会报“版本不匹配”并安全退出
- 不修改原版程序文件本身，不重打包 Electron 运行时

## 免责声明

- 仅修改你本机已安装的副本，供个人本地使用；不分发原程序的任何文件
- 原程序版权归其作者所有（应用内作者：xiaolin），本项目与之无关联
- 本仓库代码（`install.sh`）以 MIT 许可发布，见 [LICENSE](LICENSE)
