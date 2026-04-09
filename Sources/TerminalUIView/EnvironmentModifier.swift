
// public protocol EnvironmentalModifier : ViewModifier where Self.Body == Never {
//     associatedtype ResolvedModifier: ViewModifier
// }

public struct _EnvironmentWritingContent<Content: View>: View, _NeverView {
    public typealias Body = Never

    package let content: Content
    package let update: (inout EnvironmentValues) -> Void

    package init<T>(content: Content, keyPath: WritableKeyPath<EnvironmentValues, T>, value: T) {
        self.content = content
        self.update = { $0[keyPath: keyPath] = value }
    }

}


public extension View {
    /// 从当前视图开始，向下传递一个环境值。
    /// - Parameters:
    ///   - keyPath: 环境值的键路径。
    ///   - value: 要传递的环境值。
    func environment<T>(_ keyPath: WritableKeyPath<EnvironmentValues, T>, _ value: T) -> _EnvironmentWritingContent<Self> {
        _EnvironmentWritingContent(
            content: self, 
            keyPath: keyPath, value: value
        )
    }
}
