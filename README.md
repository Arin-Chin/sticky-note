# sticky note

UOS / Deepin「桌面便签」（Electron）的精简本地版，**免安装压缩包**，解压即用，不依赖系统里是否装过原程序。

| 项目 | 值 |
|---|---|
| 版本 | `1.1.0` |
| 形式 | `sticky-note-1.1.0-linux-arm64.tar.gz`（81 MB，解压后约 199 MB） |
| 运行环境 | UOS / Deepin，arm64，系统需有 GTK3 等基础库 |
| 数据目录 | `~/.config/todo-list` |

## 功能

| 项目 | 说明 |
|---|---|
| 待办 / 已完成 | 原有功能，含颜色标记、修改历史、拖拽排序 |
| 设置 | 背景图、背景色、透明度、显示行数 |
| 其他 | 导出 Excel、隐藏到托盘、锁定（鼠标穿透）、始终置顶、开机自启 |
| 打赏 / 捐赠 | 已整段删除：工具栏 ☕ 按钮、打赏窗口、`/donate` 路由、支付接口与页面文件 |
| 作者与推广信息 | 已清除：作者字段、GitHub 主页、`Powered by 万能小林子`、打赏文案、支付地址 |
| 使用指南 | 移除底部的版本号与作者信息，帮助内容保留 |
| 标题栏 | 隐藏左上角应用名、右上角「记清，办明，不遗漏」 |
| sourcemap | 已删除 11 个 `.js.map`（开发产物，含原始源码） |
| 应用名 | 改为 `sticky note`（窗口标题、托盘提示、应用菜单） |
| 图标 | 自定义 SVG（窗口、托盘、应用菜单） |

## 使用

```bash
tar xzf sticky-note-1.1.0-linux-arm64.tar.gz
cd sticky-note-1.1.0-linux-arm64
./sticky-note.sh          # 启动
```

加入应用菜单（可选，不需要 root）：

```bash
./install-desktop.sh
```

移除：删掉解压出来的目录即可；如果加过菜单，再删 `~/.local/share/applications/sticky-note.desktop`。
便签数据在 `~/.config/todo-list`，不会随目录删除而丢失。

## 自己构建

需要 `rsvg-convert`（`apt install librsvg2-bin`）和本机已安装的原程序：

```bash
bash build.sh                                  # 默认用 /home/user/Downloads/sticky-note.svg
bash build.sh /path/to/your-icon.svg           # 换图标
SN_APP_DIR=/path/to/桌面便签 bash build.sh      # 指定原程序目录
```

产物为 `sticky-note-1.1.0-linux-arm64.tar.gz`，脚本会打印 SHA256。

## 兼容性

- 实测环境：UOS Desktop 20 Professional，原版「桌面便签」v0.2.3 / arm64 / Electron 13
- 脚本按 `app.<hash>.js` 通配定位文件；原程序逻辑改动过大时会报「版本不匹配」并安全退出，不会写出半成品

## 许可

脚本以 MIT 许可发布，见 [LICENSE](LICENSE)。原程序版权归其作者所有，本仓库不提供原程序下载。
