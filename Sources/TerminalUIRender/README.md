# TerminalUIRender

`TerminalUIRender` 是布局树到 Canvas 的协调层。它很薄：不定义 View，不计算复杂
布局，也不编码终端输入。

模块接口为 package 级，外部客户端通过 `TerminalApp` 间接触发渲染。

## 渲染流程

`Render.render(_:in:to:)` 完成一帧中的两个步骤：

1. 对根 `_LayoutNode` 调用 `layout(in:)`，把最终画布边界分配给布局树。
2. 深度优先遍历节点，派生环境、应用裁剪，并调用可渲染节点的 `draw`。

遍历中的顺序很重要：

```text
解析当前节点环境
  -> 建立当前节点及后代共用的裁剪作用域
  -> 绘制当前节点
  -> 按 children 顺序绘制后代
```

先画父节点再画孩子，允许背景或容器表面被内容覆盖；ZStack 的声明顺序也因此形成
稳定层级。

## 环境传播

Render 不依赖具体 `_EnvironmentNode`，而是识别 `_EnvironmentLayoutNode` 能力。
环境节点复制父环境并写入修改值，新的快照只传给当前子树，兄弟分支不会互相污染。

可绘制节点收到已经解析的 `EnvironmentValues`，据此选择前景色、背景色、字体装饰
和焦点强调色。布局测量一般不应依赖渲染时才解析的样式。

## 裁剪

当节点遵循 `_ClippingLayoutNode` 时，Canvas 裁剪必须包裹节点自身及递归后代。
如果只裁剪当前节点，ScrollView 的内容和子边框仍会泄漏到视口外。嵌套裁剪由
Canvas 求交处理。

零宽或零高的 renderable 不会执行 draw，避免它在 frame 起点覆盖相邻边框。

## Canvas 桥接

`Canvas+View.swift` 提供使用 View 环境值绘制文本或样式的 package 扩展。底层 Core
仍不需要导入 `TerminalUIView`，从而保持 `Common -> Core` 的低层依赖关系。

## 扩展原则

- 新的节点绘制通常放在 Layout 节点的 `draw` 中，不需要修改 Render。
- 只有跨整棵树生效的遍历语义才应加入此模块。
- 跨层语义使用 Layout 中定义的窄能力协议，避免判断具体节点类型。
- 修改遍历顺序、环境或裁剪时，应运行背景、ScrollView、ZStack、sheet 和零尺寸测试。

