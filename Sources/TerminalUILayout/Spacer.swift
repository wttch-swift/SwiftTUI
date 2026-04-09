/// 只参与布局、不向画布写入字符的弹性空白视图。
///
/// 可用于显式制造 Stack 间距，或为叠放内容预留绘制区域。
extension Spacer: _LayoutNodeProducing {
    package func _makeLayoutNode() -> any _LayoutNode { _SpacerLayoutNode(width: width, height: height) }
}

final class _SpacerLayoutNode: _RenderableLayoutNode, _FlexibleLayoutNode {
    let width: Int?
    let height: Int?
    private(set) var frame = Rect(x: 0, y: 0, w: 0, h: 0)

    var expandsHorizontally: Bool { width == nil }
    var expandsVertically: Bool { height == nil }

    init(width: Int?, height: Int?) {
        self.width = width.map { max(0, $0) }
        self.height = height.map { max(0, $0) }
    }

    func measure(proposed: ProposedSize) -> Size {
        Size(w: width ?? proposed.width ?? 0, h: height ?? proposed.height ?? 0)
    }

    func layout(in rect: Rect) { frame = rect }

    /// Spacer 默认仍然不产生可见内容；只有继承到背景色时才用空格填充
    /// 已分配区域，使 Stack 的整行或整列背景能够跨过弹性空白连续显示。
    func draw(to canvas: Canvas, environment: EnvironmentValues) {
        guard let background = environment.backgroundColor, frame.w > 0, frame.h > 0 else {
            return
        }

        let row = String(repeating: " ", count: frame.w)
        for y in frame.y..<frame.maxY {
            canvas.drawText(
                x: frame.x,
                y: y,
                text: row,
                foreground: environment.foregroundColor ?? .white,
                background: background
            )
        }
    }
}
