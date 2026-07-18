

/// Never 扩展 View 协议。
extension Never : View {
    public typealias Body = Never

    public var body: Never {
        // 因为 Never 没有实例，这里无法返回
        // 所以直接调用 fatalError
        fatalError("Never 类型的 body 永远不应该被调用")
    }
}


/// 告知编译器 Never 类型的视图永远不会被实例化，因此它的 body 永远不会被调用。
package protocol _NeverView: View where Body == Never {}

extension _NeverView {
    public var body: Never {
        fatalError("Never 类型的 body 永远不应该被调用")
    }
}
