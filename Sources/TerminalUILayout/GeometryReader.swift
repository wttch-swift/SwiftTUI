extension GeometryReader: _LayoutNodeProducing {
    package func _makeLayoutNode() -> any _Layoutable {
        _GeometryReaderLayoutNode(content: {
            _makeZStackLayoutNode(children: content($0)._makeLayoutNodes(), alignment: .topLeading)
        })
    }
}

private final class _GeometryReaderLayoutNode: _LayoutContainerStorage, _ContainerLayoutable {
    private let content: (GeometryProxy) -> any _Layoutable
    private var resolvedChild: (any _Layoutable)?
    private var resolvedFrame: Rect?

    init(content: @escaping (GeometryProxy) -> any _Layoutable) {
        self.content = content
        super.init(children: [])
    }

    package func measure(proposed: ProposedSize) -> Size {
        Size(w: max(0, proposed.width ?? 0), h: max(0, proposed.height ?? 0))
    }

    package func layout(in rect: Rect) {
        let child: any _Layoutable
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
