# TerminalUICore

`TerminalUICore` 是字符画布和 ANSI 输出实现。它只依赖 `TerminalUICommon`，不认识
`View`、布局节点或焦点系统。

该 target 没有公共产品接口。`Canvas`、`_Cell` 和 `_CellStyle` 使用 Swift
`package` 访问级别，只允许同一 package 中的 Layout、Render 和 TerminalUI 宿主
使用。

## Canvas

`Canvas` 持有固定宽高的二维 cell 网格，并提供：

- 清空、矩形填充和文本绘制；
- 单线、圆角线、双线等边框绘制与交叉点合并；
- 嵌套裁剪区域；
- 双宽字符 continuation cell 管理；
- 完整 ANSI 输出；
- 与上一帧比较后的绝对行增量输出。

Canvas 坐标全部使用 `TerminalUICommon.Rect` 和终端 cell。写入双宽字符时必须同时
维护其占用的两个位置；覆盖其中任意一格时，也必须清理另一格，防止残留字符。

## Cell 与样式

`_Cell` 保存一个可见字符、样式和空白语义。`_CellStyle` 保存前景色、背景色、
粗体、斜体、下划线、删除线和反色。输出时会批量合并相邻且样式相同的 cell，
减少 ANSI 状态切换。

空格与未绘制 cell 不是完全相同的概念。背景填充、边框覆盖和差异输出依赖这一
区分，因此不要把网格简化成 `[[Character]]`。

## 模块边界

Core 应回答“如何把 cell 写到终端字符串”，但不回答：

- View 应该生成什么布局节点；
- 一个节点应该获得多大的 frame；
- 环境值如何沿 View 树传播；
- 按键应该交给哪个焦点控件。

这些职责分别属于 `TerminalUILayout`、`TerminalUIRender` 和 `TerminalUI`。

## 修改建议

涉及 `drawText`、裁剪或宽字符覆盖时，至少测试画布边缘、零尺寸区域、组合字符、
双宽字符相互覆盖和嵌套裁剪。涉及输出优化时，应同时比较首帧完整输出和后续帧
差异输出，确保终端底部不会因换行发生滚屏。

