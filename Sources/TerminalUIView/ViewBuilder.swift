/// 模拟 SwiftUI 的 `ViewBuilder`，用于构建视图。
@resultBuilder
public enum ViewBuilder {

    /// 在 builder 代码块中遇到一个普通表达式时调用，把表达式先转换为组件。
    ///
    /// 例如：
    /// ```swift
    /// VStack {
    ///     Text("Hi")
    /// }
    ///
    /// // 近似展开为：
    /// ViewBuilder.buildBlock(
    ///     ViewBuilder.buildExpression(Text("Hi"))
    /// )
    /// ```
    /// - Parameter expression: 单个视图表达式。
    public static func buildExpression<Content: View>(_ expression: Content) -> Content {
        expression
    }

    /// 在 builder 代码块只产生一个组件时调用，作为代码块的最终组合结果。
    ///
    /// 例如：
    /// ```swift
    /// @ViewBuilder var body: some View {
    ///     Text("Only")
    /// }
    ///
    /// // 近似展开为：
    /// ViewBuilder.buildBlock(
    ///     ViewBuilder.buildExpression(Text("Only"))
    /// )
    /// ```
    public static func buildBlock<Content: View>(_ content: Content) -> Content {
        content
    }

    /// 在 builder 代码块产生多个同级组件时调用，把它们组合成 `TupleView`。
    ///
    /// 例如：
    /// ```swift
    /// VStack {
    ///     Text("A")
    ///     Text("B")
    /// }
    ///
    /// // 近似展开为：
    /// ViewBuilder.buildBlock(
    ///     ViewBuilder.buildExpression(Text("A")),
    ///     ViewBuilder.buildExpression(Text("B"))
    /// )
    /// ```
    public static func buildBlock<each Content: View>(
        _ content: repeat each Content
    ) -> TupleView<repeat each Content> {
        TupleView(repeat each content)
    }

    /// 在 builder 代码块中遇到没有 `else` 的 `if` 时调用，表示该分支可能没有内容。
    ///
    /// 例如：
    /// ```swift
    /// VStack {
    ///     if isVisible {
    ///         Text("Visible")
    ///     }
    /// }
    ///
    /// // 近似展开为：
    /// ViewBuilder.buildOptional(
    ///     isVisible
    ///         ? ViewBuilder.buildBlock(ViewBuilder.buildExpression(Text("Visible")))
    ///         : nil
    /// )
    /// ```
    public static func buildOptional<Content: View>(_ component: Content?) -> _OptionalView<Content>
    {
        _OptionalView(content: component)
    }

    /// 在 builder 代码块中遇到 `if` / `else`，并选择 `if` 分支时调用。
    ///
    /// 例如：
    /// ```swift
    /// if isOn {
    ///     Text("On")
    /// } else {
    ///     Text("Off")
    /// }
    ///
    /// // isOn == true 时，近似展开为：
    /// ViewBuilder.buildEither(
    ///     first: ViewBuilder.buildBlock(ViewBuilder.buildExpression(Text("On")))
    /// )
    /// ```
    public static func buildEither<TrueContent: View, FalseContent: View>(
        first component: TrueContent
    ) -> _ConditionalView<TrueContent, FalseContent> {
        .trueContent(component)
    }

    /// 在 builder 代码块中遇到 `if` / `else`，并选择 `else` 分支时调用。
    ///
    /// 例如：
    /// ```swift
    /// if isOn {
    ///     Text("On")
    /// } else {
    ///     Text("Off")
    /// }
    ///
    /// // isOn == false 时，近似展开为：
    /// ViewBuilder.buildEither(
    ///     second: ViewBuilder.buildBlock(ViewBuilder.buildExpression(Text("Off")))
    /// )
    /// ```
    public static func buildEither<TrueContent: View, FalseContent: View>(
        second component: FalseContent
    ) -> _ConditionalView<TrueContent, FalseContent> {
        .falseContent(component)
    }

    /// 在 builder 代码块中遇到 `for` 循环时调用，把每次循环产生的组件数组合并起来。
    ///
    /// 例如：
    /// ```swift
    /// VStack {
    ///     for name in names {
    ///         Text(name)
    ///     }
    /// }
    ///
    /// // 近似展开为：
    /// ViewBuilder.buildArray(
    ///     names.map { name in
    ///         ViewBuilder.buildBlock(ViewBuilder.buildExpression(Text(name)))
    ///     }
    /// )
    /// ```
    public static func buildArray<Content: View>(_ components: [Content]) -> _ArrayView<Content> {
        _ArrayView(components)
    }

    /// 在 builder 代码块中遇到 `if #available` 等可用性检查时调用，用类型擦除隐藏只在部分平台可见的具体类型。
    ///
    /// 例如：
    /// ```swift
    /// if #available(macOS 15, *) {
    ///     Text("New")
    /// } else {
    ///     Text("Old")
    /// }
    ///
    /// // 可用性分支中的组件会近似展开为：
    /// ViewBuilder.buildLimitedAvailability(
    ///     ViewBuilder.buildBlock(ViewBuilder.buildExpression(Text("New")))
    /// )
    /// ```
    public static func buildLimitedAvailability<Content: View>(_ component: Content) -> AnyView {
        AnyView(component)
    }
}

public struct _ArrayView<Content: View>: View, _NeverView {
    public typealias Body = Never
    package let content: [Content]

    public init(_ content: [Content]) { self.content = content }
}

public struct _OptionalView<Content: View>: View, _NeverView {
    public typealias Body = Never
    package let content: Content?
}

public enum _ConditionalView<TrueContent: View, FalseContent: View>: View, _NeverView {
    public typealias Body = Never
    case trueContent(TrueContent)
    case falseContent(FalseContent)

}
