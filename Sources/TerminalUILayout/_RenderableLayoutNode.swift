
/// 可以渲染的布局节点。
package protocol _RenderableLayoutNode: _LayoutNode {
    /// 布局节点的矩形区域。
    var frame: Rect { get }

    /// 绘制布局节点。
    /// - Parameters:
    ///   - canvas: 绘制的画布。
    ///   - environment: 环境值。
    func draw(to canvas: Canvas, environment: EnvironmentValues)
}
