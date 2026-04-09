/// 叶子布局节点，表示布局树中的一个叶子节点。
final class _LeafNode: _RenderableLayoutNode {

    /// 叶子节点的固有大小。
    /// 如果未指定固有大小，则叶子节点的大小将由父节点的提议大小决定。
    private let intrinsicSize: Size?

    /// 叶子节点的绘制闭包。
    private let drawBody: (Canvas, Rect, EnvironmentValues) -> Void

    /// 叶子节点的矩形区域。
    private(set) var frame: Rect = .zero

    /// 构造函数，创建一个叶子布局节点。
    /// - Parameters:
    ///  - size: 叶子节点的固有大小。 如果不指定，则叶子节点的大小将由父节点的提议大小决定。
    ///  - draw: 叶子节点的绘制闭包。
    init(size: Size? = nil, draw: @escaping (Canvas, Rect, EnvironmentValues) -> Void = { _, _, _ in }) {
        intrinsicSize = size
        drawBody = draw
    }

    /// 测量叶子节点的大小。
    /// - Parameter proposed: 提议的大小。
    /// - Returns: 叶子节点的实际大小。
    func measure(proposed: ProposedSize) -> Size {
        if let intrinsicSize {
            return Size(
                w: min(intrinsicSize.w, proposed.width ?? intrinsicSize.w),
                h: min(intrinsicSize.h, proposed.height ?? intrinsicSize.h)
            )
        }
        return Size(w: proposed.width ?? 0, h:proposed.height ?? 0)
    }

    /// 布局叶子节点。
    /// 将叶子节点的矩形区域设置为给定的矩形区域。
    /// - Parameter rect: 布局的矩形区域。
    func layout(in rect: Rect) { frame = rect }

    /// 绘制叶子节点。
    /// - Parameters:
    ///   - canvas: 绘制的画布。
    ///   - environment: 环境值。
    func draw(to canvas: Canvas, environment: EnvironmentValues) {
        drawBody(canvas, frame, environment)
    }
}
