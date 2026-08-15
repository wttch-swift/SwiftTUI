
/// 可以渲染的布局节点。
package protocol _RenderableLayoutNode: _Layoutable {
    /// 布局节点的矩形区域。
    var frame: Rect { get }

    /// 绘制布局节点。
    /// - Parameters:
    ///   - canvas: 绘制的画布。
    ///   - environment: 环境值。
    func draw(to canvas: Canvas, environment: EnvironmentValues)
}

/// 可被 RenderCache 按结构路径和指纹复用绘制快照的安全叶子节点。
///
/// 只给没有子节点、且绘制结果完全由自身属性、Binding 当前值、frame 与
/// environment 决定的节点实现。未实现的节点永远走普通绘制路径。
package protocol _RenderReusableLayoutNode: _RenderableLayoutNode {
    /// 返回影响 draw 结果的轻量指纹。
    ///
    /// fingerprint 不需要跨进程稳定，只需要在同一次运行的相邻帧里能判断“这次
    /// 会不会画出同样的 cell”。实现时要把文字、样式、Binding 当前值、焦点状态、
    /// 相关 environment 等都会改变输出的输入放进去。
    func renderFingerprint(environment: EnvironmentValues) -> Int
}
