@resultBuilder
public enum ViewBuilder {

    /// 将单个视图表达式转换为视图。
    /// 1. 链式修饰符，比如 `.foregroundColor(.red)`，会被编译器拆解为多个表达式，最终会调用这个方法。
    /// 2. 条件编译`#if`/`#else`/`#endif` 也会被编译器拆解为多个表达式，最终会调用这个方法。
    /// - Parameter expression: 单个视图表达式。
    public static func buildExpression<Content: View>(_ expression: Content) -> Content {
        expression
    }

    /// 将单个代码块转换为视图。
    public static func buildBlock<Content: View>(_ content: Content) -> Content {
        content
    }

    public static func buildBlock<each Content: View>(
        _ content: repeat each Content
    ) -> TupleView<repeat each Content> {
        TupleView(repeat each content)
    }

    public static func buildOptional<Content: View>(_ component: Content?) -> _OptionalView<Content>
    {
        _OptionalView(content: component)
    }

    public static func buildEither<TrueContent: View, FalseContent: View>(
        first component: TrueContent
    ) -> _ConditionalView<TrueContent, FalseContent> {
        .trueContent(component)
    }

    public static func buildEither<TrueContent: View, FalseContent: View>(
        second component: FalseContent
    ) -> _ConditionalView<TrueContent, FalseContent> {
        .falseContent(component)
    }

    public static func buildArray<Content: View>(_ components: [Content]) -> _ArrayView<Content> {
        _ArrayView(components)
    }

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
