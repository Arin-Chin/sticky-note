# sticky note

UOS / Deepin「桌面便签」（Electron，包名 `todo-list`）的去广告本地优化版 + 一键安装包。

去掉打赏图标与标题栏多余文字，换上新图标，应用名改成 `sticky note`，其余功能原样保留。
**不需要重新编译、不需要联网、不需要下载原程序**——安装包由你本机已安装的那份直接构建。

## 效果

| 项目 | 原版 | sticky note |
|---|---|---|
| 工具栏 ☕「请作者喝咖啡」 | 显示 | 隐藏 |
| 左上角应用名 | 桌面便签 | 隐藏 |
| 右上角标语 | 记清，办明，不遗漏 | 隐藏 |
| 应用名（标题/启动器/托盘提示） | 桌面便签 | sticky note |
| 图标 | 原图标 | 自定义 SVG（启动器 + 托盘 + 窗口） |
| 使用指南底部 | `sticky note v0.2.3` + `Powered by 万能小林子` | 整块移除 |
| 作者/推广信息 | package.json 作者、GitHub 主页、打赏文案与支付地址 | 全部清除 |
| 待办 / 已完成 / 导出 / 锁定 / 设置 | 有 | 不变 |
| 数据目录 | `~/.config/todo-list` | **不变**，历史便签照常 |

工具栏保留：使用指南、导出 Excel、隐藏到托盘、锁定（鼠标穿透）。窗口拖动区仍在。

## 一键安装

安装包：`todo-list_1.1.0_arm64.deb`（Release 附件，62 MB）

**方式一：双击** —— 用系统「软件包安装器」打开 `.deb`，点安装。

**方式二：命令行**

```bash
sudo dpkg -i todo-list_1.1.0_arm64.deb
```

包名沿用原包 `todo-list`、版本号更高（`1.1.0 > 0.2.3`），属于正常升级安装：
不会残留两个启动图标，`~/.config/todo-list` 里的便签数据保持不动。

装完启动器里就是 **sticky note**。

## 还原原版

```bash
sudo apt install --reinstall todo-list
```
（若软件源里没有这个包，重装官方原版 `.deb` 即可。）

## 自己构建安装包

需要：`dpkg-deb`、`rsvg-convert`（`apt install librsvg2-bin`）、本机已安装原版程序。

```bash
bash build-deb.sh                          # 用 /home/user/Downloads/sticky-note.svg
bash build-deb.sh /path/to/your-icon.svg   # 换自己的图标
```

产物 `todo-list_1.1.0_arm64.deb`，脚本会打印 SHA256。
程序装在非默认目录时：`SN_APP_DIR=/path/to/桌面便签 bash build-deb.sh`

## 不用安装包，只打补丁（可选）

不想动 dpkg，只补丁本机这一份：

```bash
sudo bash install.sh            # 就地替换 app.asar，备份为 app.asar.orig
sudo bash install.sh uninstall  # 还原
bash install.sh build out.asar  # 只生成补丁包，不写系统
```

## 原理

1. 解析 `resources/app.asar`（Electron 归档格式）到内存
2. 文本替换：`productName`、窗口标题、`index.html` 的 `<title>`
3. 在 `css/app.<hash>.css` 末尾追加隐藏规则：
   ```css
   .drag-nav b, .drag-nav i, .tool-btn.coffee-btn { display: none !important; }
   ```
4. 清除作者/推广信息：`author`、`homepage`、`Powered by 万能小林子`、打赏文案与 `xiaolinwl.com` 支付地址（含 sourcemap）
5. 用 `rsvg-convert` 把 SVG 渲染成 16–512px PNG，替换 asar 内 `logo.png` / `tray.png` / `icons/*`
6. 自检通过后重新打包，连同图标和启动项一起打成 `.deb`

替换处数量对不上会直接报错退出，不会写出半成品。

## 兼容性

- 在 UOS Desktop 20 Professional 上实测：原版 `todo-list` v0.2.3 / arm64 / Electron 13
- 脚本按 `app.<hash>.js` 通配定位文件，替换是幂等的，可重复执行
- 逻辑改动大时会报「版本不匹配」并安全退出，不会写出半成品
- 包名保持 `todo-list` 是为了覆盖升级与共用数据目录；不要同时保留两个不同名的包

## 免责声明

- 安装包基于**你本机已安装的副本**构建，仅供个人本地使用
- 原程序版权归其作者所有（应用内作者：xiaolin），本项目与之无关联，不提供原程序下载
- 本仓库代码（`install.sh` / `build-deb.sh`）以 MIT 许可发布，见 [LICENSE](LICENSE)
