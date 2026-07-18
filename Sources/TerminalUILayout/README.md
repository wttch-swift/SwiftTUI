# TerminalUILayout

`TerminalUILayout` 连接声明式 View 和终端布局树。它依赖 Foundation、Core 和 View，
但不负责最终的树遍历输出。

本模块属于 package 内部实现：`_LayoutNode`、节点基类和适配协议都不是客户端 API。

## 两阶段布局

所有节点实现 `_LayoutNode` 的两个操作：

```swift
func measure(proposed: ProposedSize) -> Size
func layout(in rect: Rect)
```

`measure` 在父节点给出的可选约束内计算期望尺寸；`layout` 接收最终矩形并为子节点
分配 frame。测量不应绘制，也不应假设最终一定获得期望尺寸。

`_LayoutNode` 本身不要求 children。容器行为由 `_ContainerLayoutNode` 提供，只有
一个孩子的 frame、padding、environment 等包装节点复用模块内部的
`_UnaryLayoutNode`。只有需要写 Canvas 的节点才遵循 `_RenderableLayoutNode`。

## View 适配

`_LayoutNodeProducing` 和 `_MultiViewProducing` 定义在本模块。基础 View 通过扩展
获得实现，例如 Text、Stack、Table、ScrollView 和各种 modifier。普通业务 View
只实现 `body`，`View._makeLayoutNode()` 会递归展开 body，直到遇到基础 View。

`TupleView`、条件 View、数组 View 和 `ForEach` 使用 multi-view 适配展开为同级
节点；容器因此无需知道 `ViewBuilder` 的具体组合类型。

新增基础 View 时遵循以下顺序：

1. 在 `TerminalUIView` 定义纯声明和公共构造器。
2. 在本模块添加 `_LayoutNodeProducing` 扩展。
3. 实现最小节点类型及 measure/layout。
4. 仅在节点有直接可见内容时实现 `_RenderableLayoutNode.draw`。
5. 添加受限空间、零尺寸、宽字符及状态重建测试。

## 能力协议

布局树除继承关系外，还通过窄协议向宿主和 Render 暴露行为：

- `_FlexibleLayoutNode`：声明横向或纵向弹性扩张。
- `_ClippingLayoutNode`：裁剪当前节点及其后代。
- `_EnvironmentLayoutNode`：为当前渲染分支派生环境值。
- `_FocusScopeLayoutNode`：限制模态界面中的焦点遍历范围。
- `_FocusableLayoutNode`：处理当前焦点的键盘事件。
- `_TabSelectionNode`、`_TabNavigationNode`：保持和切换标签选择。

优先添加精确的能力协议，不要让 Render 或 TerminalApp 判断具体节点类。

## 重要实现

- Stack：测量子节点，分配固定空间与 Spacer 剩余空间，并按 alignment 定位。
- Text：按 cell 宽度换行，尊重显式换行和 lineLimit，空间不足时添加省略号。
- TextField：维护 grapheme 级光标和水平视口，焦点时在当前插入位置显示细竖条光标。
- ScrollView：分别维护内容尺寸、视口、滚动上限和偏移，并提供裁剪区域。
- Table：测量列内容、共享边框连接点，并在约束宽度内换行。
- Presentation：通过 Z 轴布局显示 sheet/toast，并隔离模态焦点范围。

## 边界约束

布局节点可以依赖 Core 的 Canvas 类型来声明 draw 签名，但实际遍历顺序、环境派生
和裁剪作用域由 `TerminalUIRender` 管理。不要在 measure/layout 中直接 flush 输出，
也不要从 Layout 反向启动终端事件循环。
