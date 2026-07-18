

/// 布局穿透的 layout 协议。
/// 
/// 代理子节点的 measure/layout 方法，通常用于包装一个子节点并在其上添加额外的行为。
package protocol _PassthroughUnaryLayoutable: _UnaryLayoutable {

}


/// 默认实现，直接代理子节点的 measure/layout 方法。
package extension _PassthroughUnaryLayoutable where Self: _LayoutContainerStorage {
    
    func measure(proposed: ProposedSize) -> Size {
        children[0].measure(proposed: proposed)
    }

    func layout(in rect: Rect) {
        children[0].layout(in: rect)
    }
}
