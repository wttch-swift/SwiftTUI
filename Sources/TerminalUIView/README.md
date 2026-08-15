# TerminalUIView

`TerminalUIView` 是框架的声明层。它定义应用作者看到的 SwiftUI 风格类型，但不
包含 `_LayoutNode`、Canvas 或具体布局算法。

最终客户端应 `import TerminalUI`；门面会重新导出本模块。把声明单独放在这里的
核心目的，是让 View 模型不依赖其终端实现。

## 主要 API

- 组合：`View`、`ViewBuilder`、`AnyView`、`EmptyView`、`ViewModifier`。
- 容器：`HStack`、`VStack`、`LazyVStack`、`ZStack`、`GroupBox`、`ScrollView`、`TabView`。
- 基础视图：`Text`、`Spacer`、`ProgressBar`、`Toggle`、`TextField`。
- 数据视图：`ForEach`、`Table`、`TableColumn`、`GeometryReader`。
- 身份：`View.id(_:)`，以及 `ForEach`、`LazyVStack` 的数据 ID 会保留到布局节点。
- 状态：`State`、`Binding`、`FocusState`。
- 交互：`KeyPress`、`onKeyPress`、`focused`、`sheet`、`toast`。
- Modifier：`frame`、`padding`、`background`、`bordered`、颜色、焦点效果、
  字体装饰和行数限制。

## 声明不执行布局

例如 `Text` 只保存字符串，`VStack` 只保存 alignment 和 builder 生成的 content。
它们不会实现 `_makeLayoutNode()`，因为该协议位于 `TerminalUILayout`：

```swift
public struct Text: View {
    public let text: String
}
```

Layout target 通过 retroactive conformance 为这些类型补上节点生成能力。这样可以
独立演进公共声明和内部算法，也能避免客户端接触 LayoutNode。

## 状态和刷新

`State` 使用引用存储，使声明式 View 被重建后仍可保留同步值语义。修改状态会经
`TerminalStateRuntime` 发布重绘事件；`TerminalApp` 在事件循环下一轮重建布局树。
`Binding` 用 getter/setter 连接控件和状态，`FocusState` 则描述哪一个可聚焦 View
应该拥有键盘焦点。

```swift
struct Form: View {
    enum Field: Hashable { case name }

    @State private var name = ""
    @FocusState private var focus: Field?

    var body: some View {
        TextField("Name", text: $name)
            .focused($focus, equals: .name)
            .bordered()
    }
}
```

焦点外观默认由环境中的统一强调色控制。可使用 `focusBorderColor(_:)` 修改颜色，
或使用 `focusEffectDisabled()` 关闭默认边框反馈，而不影响控件接收按键。

## 环境值

颜色、文本装饰、行数限制和焦点效果通过 `EnvironmentValues` 沿子树传播。环境键
目前是 package 内部协议，客户端使用公开 modifier 写入已有值，而不是自行定义
EnvironmentKey。

背景色既写入环境，也创建填充布局区域的背景声明；这是为了覆盖 padding、Spacer
等没有直接绘制字符的区域。

## 新增声明类型

基础 View 应只保存不可变配置、Binding 或必要的持久状态引用，不应导入 Core、
Layout、Render。新增类型后，在 `TerminalUILayout` 中实现对应适配和节点。若功能
可由已有 View 组合表达，优先实现 `body`，无需新增布局节点。
