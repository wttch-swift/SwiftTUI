
/// 空视图，使用空容器实现。
public struct EmptyView: View {
    
    /// 创建一个空视图实例。
    public init() {}
}


/// 没有实际子 View，作为一个布局节点，使用空容器实现。
extension EmptyView: _NeverView {}
