/// 布局节点 — 纯 measure/layout 能力，不包含 children。
package protocol _LayoutNode {
    /// 测量布局节点的大小。
    /// - Parameter proposed: 提议的大小。
    /// - Returns: 测量后的大小。
    func measure(proposed: ProposedSize) -> Size

    /// 布局布局节点。
    /// - Parameter rect: 布局的矩形区域。
    func layout(in rect: Rect)
}
