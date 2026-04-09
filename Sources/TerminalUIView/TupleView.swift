/// 保存 `@ViewBuilder` 产生的静态异构子视图参数包。
public struct TupleView<each Content: View>: View, _NeverView {
    public typealias Body = Never

    public var value: (repeat each Content)

    public init(_ content: repeat each Content) {
        value = (repeat each content)
    }

}
