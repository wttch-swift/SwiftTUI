extension GeometryReader: _LayoutNodeProducing {
    package func _makeLayoutNode() -> any _LayoutNode {
        _GeometryReaderLayoutNode(content: {
            _ZStackLayoutNode(content: content($0), alignment: .topLeading)
        })
    }
}

private final class _GeometryReaderLayoutNode: _ContainerLayoutNode {
    private let content: (GeometryProxy) -> any _LayoutNode
    private var resolvedChild: (any _LayoutNode)?
    private var resolvedFrame: Rect?

    init(content: @escaping (GeometryProxy) -> any _LayoutNode) {
        self.content = content
        super.init(children: [])
    }

    package override func measure(proposed: ProposedSize) -> Size {
        Size(w: max(0, proposed.width ?? 0), h: max(0, proposed.height ?? 0))
    }

    package override func layout(in rect: Rect) {
        frame = rect
        let child: any _LayoutNode
        if let existing = resolvedChild, resolvedFrame == rect {
            child = existing
        } else {
            let proxy = GeometryProxy(frame: rect)
            child = content(proxy)
            resolvedChild = child
            resolvedFrame = rect
            children = [child]
        }
        child.layout(in: rect)
    }
}
