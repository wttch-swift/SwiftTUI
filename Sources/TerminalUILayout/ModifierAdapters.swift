import TerminalUIView

extension _PaddingLayoutView: _LayoutNodeProducing {
    package func _makeLayoutNode() -> any _LayoutNode {
        _PaddingLayoutNode(
            child: content._makeLayoutNode(),
            top: top,
            right: right,
            bottom: bottom,
            left: left
        )
    }
}

extension _FrameLayoutView: _LayoutNodeProducing {
    package func _makeLayoutNode() -> any _LayoutNode {
        _FrameLayoutNode(
            child: content._makeLayoutNode(),
            width: width,
            height: height,
            alignment: alignment
        )
    }
}

extension _BorderContent: _LayoutNodeProducing {
    package func _makeLayoutNode() -> any _LayoutNode {
        _BorderLayoutNode(child: content._makeLayoutNode(), color: color, style: style)
    }
}

extension _Background: _LayoutNodeProducing {
    package func _makeLayoutNode() -> any _LayoutNode {
        _BackgroundLayoutNode(
            content: content._makeLayoutNode(),
            background: background._makeLayoutNode(),
            alignment: alignment
        )
    }
}

private final class _BorderLayoutNode: _UnaryLayoutNode, _RenderableLayoutNode {
    let color: Color
    let style: BorderStyle

    init(child: any _LayoutNode, color: Color, style: BorderStyle) {
        self.color = color
        self.style = style
        super.init(child: child)
    }

    package override func measure(proposed: ProposedSize) -> Size {
        let childSize = child.measure(proposed: proposed)
        let ideal = Size(w: max(3, childSize.w), h: max(3, childSize.h))
        return Size(
            w: min(ideal.w, proposed.width ?? ideal.w),
            h: min(ideal.h, proposed.height ?? ideal.h)
        )
    }

    package override func layout(in rect: Rect) {
        frame = rect
        child.layout(
            in: Rect(
                x: rect.x + 1,
                y: rect.y + 1,
                w: max(0, rect.w - 2),
                h: max(0, rect.h - 2)
            )
        )
    }

    func draw(to canvas: Canvas, environment: EnvironmentValues) {
        let resolvedColor = environment._isFocusEffectEnabled && _containsFocusedTarget(in: child)
            ? environment._focusBorderColor
            : color
        canvas.drawBox(
            in: frame,
            style: style,
            foreground: resolvedColor,
            background: environment.backgroundColor
        )
    }
}

private final class _BackgroundLayoutNode: _ContainerLayoutNode {
    private let content: any _LayoutNode
    private let background: any _LayoutNode
    private let alignment: AlignmentEdge

    init(content: any _LayoutNode, background: any _LayoutNode, alignment: AlignmentEdge) {
        self.content = content
        self.background = background
        self.alignment = alignment
        _attachFocusEffectSource(content, to: background)
        super.init(children: [background, content])
    }

    package override func measure(proposed: ProposedSize) -> Size {
        content.measure(proposed: proposed)
    }

    package override func layout(in rect: Rect) {
        let backgroundSize = background.measure(
            proposed: ProposedSize(width: rect.w, height: rect.h)
        )
        let origin = alignedOrigin(parent: rect, child: backgroundSize, alignment: alignment)
        background.layout(
            in: Rect(x: origin.x, y: origin.y, w: backgroundSize.w, h: backgroundSize.h)
        )
        content.layout(in: rect)
    }
}
