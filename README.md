# sticky note

UOS / Deepin「桌面便签」（Electron）的精简本地版，**免安装压缩包**，解压即用。

| 项目 | 值 |
|---|---|
| 版本 | `1.1.0` |
| 形式 | `sticky-note-1.1.0-linux-arm64.tar.gz`（105 MB，解压后约 248 MB） |
| 运行环境 | UOS / Deepin，arm64，系统需有 GTK3 等基础库 |

## 功能

| 项目 | 说明 |
|---|---|
| 待办 / 已完成 | 主列表只显示待办标题（单行省略）；颜色标记、拖拽排序 |
| 设置 | 背景图、背景色、透明度、显示行数 |
| 右上角按钮 | 隐藏到托盘 → 锁定（鼠标穿透）→ 置顶（始终最前）→ 设置齿轮 |
| 托盘 | 单击托盘图标显示窗口；右键菜单：显示/隐藏、退出 |
| 设置齿轮 | 便签纸颜色(RGBA)、便签文字颜色(RGBA)，各 9 个预选色；卡片同纸色、文字/图标同文字色，低对比时自动兜底；开机自启、导出 Excel、使用指南 |
| 自适应提示色 | 软件提示文字与图标颜色根据便签纸明暗自动切换深/浅，无需单独设置 |
| 小窗口适配 | 设置菜单内容可滚动，窗口再小也能滚到导出、使用指南 |
| 图标风格 | 统一为 Apple 风极简线性 SVG，无 emoji |
| 使用指南 | 卡片底色跟随便签纸颜色，文字/图标与软件提示文本同色；方角卡片 |
| 待办详情 | 铅笔图标唤起；「笔记：」可编辑并单独保存；标题或笔记修改都会生成历史，按【标题】/【笔记】两行展示 |
| 字体 | 全应用霞鹜文楷 / LXGW WenKai Regular，字体随包附带，无需系统安装 |
| 导出 / 指南 | 原工具栏图标收进设置齿轮菜单 |

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

菜单图标会复制到 `~/.local/share/icons/hicolor/512x512/apps/sticky-note.png`，
与解压目录无关：以后移动或删除解压出来的文件夹，菜单图标仍正常显示。

移除：

```bash
rm -f ~/.local/share/applications/sticky-note.desktop \
      ~/.local/share/icons/hicolor/512x512/apps/sticky-note.png
```

便签数据保存在 `~/.config/todo-list`，删除目录或卸载菜单项都不会丢失。

## 图标

图标源文件在仓库根目录：`sticky-note.svg`。

- 构建时默认使用它，不再依赖 `~/Downloads` 或其他本地路径；把它删了也能照常构建
- 压缩包里也附带一份（`sticky-note.svg` 与渲染好的 `logo.png`），换图标重新构建可直接用它
- 换图标：`bash build.sh 你的图标.svg`，也支持直接传 PNG

## 许可

脚本以 MIT 许可发布，见 [LICENSE](LICENSE)。原程序版权归其作者所有，本仓库不提供原程序下载。
