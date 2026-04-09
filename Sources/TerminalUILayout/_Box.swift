
/// 边框需要框架内部绘制构造 layoutnode。
/// 使用叶子节点直接绘制边框。
extension _Box: _LayoutNodeProducing {
    package func _makeLayoutNode() -> any _LayoutNode {
        _BoxLayoutNode(style: style)
    }
}

/// Box 常作为 background 使用，因此通过 `focusEffectSource` 观察与它并列的
/// 前景内容，而不是只检查自己的布局子树。
private final class _BoxLayoutNode: _RenderableLayoutNode, _FocusEffectSourceLayoutNode {
    let style: BorderStyle
    var focusEffectSource: (any _LayoutNode)?
    private(set) var frame: Rect = .zero

    init(style: BorderStyle) {
        self.style = style
    }

    func measure(proposed: ProposedSize) -> Size {
        Size(w: proposed.width ?? 0, h: proposed.height ?? 0)
    }

    func layout(in rect: Rect) {
        frame = rect
    }

    func draw(to canvas: Canvas, environment: EnvironmentValues) {
        let hasFocus = focusEffectSource.map(_containsFocusedTarget) ?? false
        let foreground = environment._isFocusEffectEnabled && hasFocus
            ? environment._focusBorderColor
            : environment.foregroundColor ?? .white
        canvas.drawBox(
            in: frame,
            style: style,
            foreground: foreground,
            background: environment.backgroundColor
        )
    }
}
