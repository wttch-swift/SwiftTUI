

/// 可以通过 `modifier` 修饰的内容。
public struct ModifiedContent<Content, Modifier> {
    /// 被修饰的内容。
    public var content: Content
    /// 修饰器。
    public var modifier: Modifier
}

/// 当 `Content` 是 `View`
/// `Modifier` 是 `ViewModifier` 时，`ModifiedContent` 也可以作为 `View`。
extension ModifiedContent: View, _NeverView where Content: View, Modifier: ViewModifier {
    public typealias Body = Never

}

// extension ModifiedContent: ViewModifier where Content: ViewModifier, Modifier: ViewModifier {

// }


public extension View {
    /// 返回一个新的视图，它是当前视图的修饰版本。
    /// - Parameter modifier: 修饰器。
    /// - Returns: 修饰后的视图。
    func modifier<M: ViewModifier>(_ modifier: M) -> ModifiedContent<Self, M> {
        ModifiedContent(content: self, modifier: modifier)
    }
}



/// 视图修饰器
public protocol ViewModifier {
    /// 视图修饰器的内容类型。
    associatedtype Body: View
    /// 视图修饰器收到的框架内容包装类型。
    typealias Content = _ViewModifier_Content<Self>

    // @ViewBuilder
    func body(content: Content) -> Body
}

/// ViewModifier 的内容代理。它隐藏被修饰 View 的具体类型，但不会引入 AnyView。
public struct _ViewModifier_Content<Modifier: ViewModifier>: View, _NeverView {
    package let content: any View

    package init<Content: View>(_ content: Content) {
        self.content = content
    }
}

/// `Body == Never` 的 primitive modifier 不提供声明式 body。
extension ViewModifier where Body == Never {
    public func body(content: Content) -> Body {
        fatalError("Never")
    }
}
