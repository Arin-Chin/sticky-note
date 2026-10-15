# sticky note

UOS / Deepin「桌面便签」（Electron，包名 `todo-list`）的精简本地版。

> 本仓库只包含打包脚本。安装包由**你本机已安装的原程序**现场构建，仓库不附带、也不分发原程序的任何文件。

## 效果

| 项目 | 原版 | sticky note |
|---|---|---|
| 工具栏 ☕ 打赏按钮 | 有 | **删除**（含路由、窗口、支付接口、页面文件） |
| 打赏窗口 / 支付接口 | 有 | **删除**（`openDonateWindow`、`createPaymentOrder` 已不存在） |
| 左上角应用名 | 桌面便签 | 隐藏 |
| 右上角标语 | 记清，办明，不遗漏 | 隐藏 |
| 使用指南底部 | `sticky note v0.2.3` + `Powered by 万能小林子` | 整块移除 |
| 作者 / 推广信息 | 作者字段、GitHub 主页、打赏文案、支付地址 | 全部清除 |
| sourcemap | 11 个 `.js.map`（含原始源码） | **删除** |
| 图标 | 原图标 | 自定义 SVG（启动器 + 托盘 + 窗口） |
| 应用名 | 桌面便签 | sticky note |
| 待办 / 已完成 / 设置 / 导出 / 锁定 | 有 | 不变 |
| 数据目录 | `~/.config/todo-list` | **不变**，历史便签照常 |

| 项目 | 值 |
|---|---|
| 版本 | `1.1.0` |
| 包名 | `todo-list`（沿用原包，用于正常升级覆盖） |
| 架构 | arm64 |
| 大小 | 61 MB |

## 一键安装

Release 附件：`todo-list_1.1.0_arm64.deb`

**双击**用系统软件包安装器安装，或：

```bash
sudo dpkg -i todo-list_1.1.0_arm64.deb
```

包名沿用 `todo-list` 且版本号更高（`1.1.0 > 0.2.3`），属于正常升级安装：不会残留两个启动图标，`~/.config/todo-list` 里的便签数据保持不动。

## 自己构建

需要：`dpkg-deb`、`rsvg-convert`（`apt install librsvg2-bin`）、本机已安装原版程序。

```bash
bash build-deb.sh                            # 用 /home/user/Downloads/sticky-note.svg
bash build-deb.sh /path/to/your-icon.svg      # 换自己的图标
SN_APP_DIR=/path/to/桌面便签 bash build-deb.sh  # 指定原程序目录
```

产物为 `todo-list_1.1.0_arm64.deb`，脚本会打印 SHA256。

不想动 dpkg，只给本机这一份打补丁：

```bash
bash install.sh build /tmp/app.asar   # 只生成补丁包，不写系统
sudo bash install.sh                  # 就地替换 app.asar（备份为 app.asar.orig）
sudo bash install.sh uninstall        # 还原
```

## 原理

1. 解析 `resources/app.asar`（Electron 归档格式）到内存
2. 文本替换：`productName`、窗口标题、版本号、`index.html` 的 `<title>`
3. 追加 CSS 隐藏标题栏应用名与标语
4. 用 `rsvg-convert` 把 SVG 渲染成 16–512px PNG，替换 asar 内 `logo.png` / `tray.png` / `icons/*`
5. 自检通过后重新打包，连同图标、启动项、Debian 文档一起打成 `.deb`

## 兼容性

- 实测环境：UOS Desktop 20 Professional，原版 `todo-list` v0.2.3 / arm64 / Electron 13
- 脚本按 `app.<hash>.js` 通配定位文件；原程序逻辑改动过大时会报「版本不匹配」并安全退出

- 本仓库脚本以 MIT 许可发布，见 [LICENSE](LICENSE)
