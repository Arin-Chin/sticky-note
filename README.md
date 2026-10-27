# sticky note

本地便签，免安装，解压即用。

- UOS / Deepin arm64：`sticky-note-1.0.4-uos-arm64.tar.gz`
- Windows x64：`sticky-note-1.0.4-windows-x64.zip`
- 版本：`1.0.4`

## 功能

- 待办 / 已完成，支持颜色标记、拖拽排序、单行标题
- 待办详情：可编辑笔记，标题与笔记的修改都会记录历史
- 置顶、锁定（鼠标穿透）、隐藏到托盘
- 便签纸 / 文字 / 界面配色，自动保证可读性
- 开机自启、导出 Excel、使用指南

## 使用

**UOS / Deepin**

```bash
tar xzf sticky-note-1.0.4-uos-arm64.tar.gz
cd sticky-note-1.0.4-uos-arm64
./sticky-note.sh
```

可选加入应用菜单：`./install-desktop.sh`

**Windows**

解压后双击 `sticky-note.exe`。

数据位置：UOS 为 `~/.config/todo-list`，Windows 为 `%APPDATA%\todo-list`。

## 许可

脚本以 MIT 许可发布，见 [LICENSE](LICENSE)。原程序版权归其作者所有。
