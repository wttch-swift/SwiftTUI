/// 布局树的渲染协调器。
///
/// 渲染分为两个阶段：先从根节点向下分配 frame，再深度优先遍历节点执行绘制。
/// 环境节点在遍历途中派生新的 `EnvironmentValues`，并只影响其后代。
package enum Render {
    /// 在指定边界内布局并绘制整棵节点树。
    /// - Parameters:
    ///   - root: 已由 View 展开得到的布局树根节点。
    ///   - bounds: 根节点可使用的最终画布区域。
    ///   - canvas: 接收字符单元格的目标画布。
    package static func render(_ root: any _LayoutNode, in bounds: Rect, to canvas: Canvas) {
        root.layout(in: bounds)
        draw(root, to: canvas, environment: EnvironmentValues())
    }

    /// 深度优先绘制节点，并沿当前分支传递解析后的环境值。
    private static func draw(_ node: any _LayoutNode, to canvas: Canvas, environment: EnvironmentValues) {
        // 环境修改必须先于当前节点绘制生效，并继续传给所有子节点。
        let resolved = (node as? any _EnvironmentLayoutNode)?.applyingEnvironment(to: environment)
            ?? environment

        // 将“节点自身 + 后代”作为一个绘制作用域供裁剪节点整体包裹。
        // 若只裁剪节点自身，ScrollView 的子内容仍会泄漏到视口之外。
        let drawNode = {
            // 零尺寸节点不应在 frame 起点写入字符，否则会覆盖相邻边框。
            if let renderable = node as? any _RenderableLayoutNode,
               renderable.frame.w > 0,
               renderable.frame.h > 0 {
                renderable.draw(to: canvas, environment: resolved)
            }
            if let container = node as? _ContainerLayoutNode {
                for child in container.children {
                    draw(child, to: canvas, environment: resolved)
                }
            }
        }

        if let clipping = node as? _ClippingLayoutNode {
            // Canvas 会把这里的区域与所有祖先裁剪区继续求交。
            canvas.withClip(clipping.clipRect, drawNode)
        } else {
            drawNode()
        }
    }
}
