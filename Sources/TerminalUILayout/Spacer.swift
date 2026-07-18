/// 只参与布局、不向画布写入字符的弹性空白视图。
///
/// 可用于显式制造 Stack 间距，或为叠放内容预留绘制区域。
extension Spacer: _LayoutNodeProducing {
    package func _makeLayoutNode() -> any _LayoutNode { _SpacerLayoutNode(width: width, height: height) }
}

final class _SpacerLayoutNode: _RenderReusableLayoutNode, _FlexibleLayoutNode {
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

    func renderFingerprint(environment: EnvironmentValues) -> Int {
        // Spacer 自身通常不画内容，但背景色存在时会填满 frame。frame 和相关
        // 前景/背景都必须纳入 fingerprint，否则 Stack 背景变化会被错误复用。
        var hasher = Hasher()
        hasher.combine(width)
        hasher.combine(height)
        hasher.combine(frame)
        hasher.combine(environment.foregroundColor)
        hasher.combine(environment.backgroundColor)
        return hasher.finalize()
    }
}
