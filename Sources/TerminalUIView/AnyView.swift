
/// `AnyView` 是一个类型擦除的视图，它可以包装任何符合 `View` 协议的视图类型。
/// 通过使用 `AnyView`，你可以在不关心具体视图类型的情况下处理不同类型的视图，从而实现更灵活的布局和组合。
/// 
/// 如果子视图是的容器、叶子 View：
///   - 有 layoutnode
/// 如果子视图是客户端 View:
///   - 则一定是容器，也应该有 layoutnode
public struct AnyView: View {
    package let content: () -> any View

    /// 创建一个 `AnyView`，它包装了一个具体的视图。
    /// - Parameter view: 需要被包装的具体视图。
    public init<V: View>(_ view: V) {
        self.content = { view }
    }

    // 创建一个擦除类型的 `AnyView`，它包装了一个返回具体视图的闭包。
    /// - Parameter content: 返回需要被包装的具体视图的闭包。
    public init<V: View>(erasing view: V) {
        self.content = { view }
    }

    /// 创建一个 `AnyView`，它包装了一个返回具体视图的闭包。
    /// - Parameter content: 返回需要被包装的具体视图的闭包。
    public init<V: View>(_ content: @escaping () -> V) {
        self.content = { content() }
    }
}

extension AnyView: _NeverView {}


extension View {
    /// 将当前视图转换为 `AnyView`，实现类型擦除。
    /// - Returns: 一个类型为 `AnyView` 的视图，它包装了当前视图。
    public func eraseToAnyView() -> AnyView {
        AnyView(self)
    }
}
