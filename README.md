# sticky note

UOS / Deepin「桌面便签」（Electron）的精简本地版，**免安装压缩包**，解压即用。

| 项目 | 值 |
|---|---|
| 版本 | `1.1.0` |
| 形式 | `sticky-note-1.1.0-linux-arm64.tar.gz`（81 MB，解压后约 199 MB） |
| 运行环境 | UOS / Deepin，arm64，系统需有 GTK3 等基础库 |

## 功能

| 项目 | 说明 |
|---|---|
| 待办 / 已完成 | 原有功能，含颜色标记、修改历史、拖拽排序 |
| 设置 | 背景图、背景色、透明度、显示行数 |
| 右上角按钮 | 隐藏到托盘 → 锁定（鼠标穿透）→ 置顶（始终最前）→ 设置齿轮 |
| 设置齿轮 | 便签纸颜色（RGBA）、字体颜色（RGBA），各 9 个预选色，可调透明度 |
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

## 许可

脚本以 MIT 许可发布，见 [LICENSE](LICENSE)。原程序版权归其作者所有，本仓库不提供原程序下载。
