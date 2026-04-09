import TerminalUIView

extension _ArrayView: _MultiViewProducing {
    package func _makeLayoutNodes() -> [any _LayoutNode] {
        content.flatMap { $0._makeLayoutNodes() }
    }
}

extension _OptionalView: _MultiViewProducing {
    package func _makeLayoutNodes() -> [any _LayoutNode] {
        content?._makeLayoutNodes() ?? []
    }
}

extension _ConditionalView: _MultiViewProducing {
    package func _makeLayoutNodes() -> [any _LayoutNode] {
        switch self {
        case .trueContent(let content): content._makeLayoutNodes()
        case .falseContent(let content): content._makeLayoutNodes()
        }
    }
}

extension TupleView: _LayoutNodeProducing, _MultiViewProducing {
    package func _makeLayoutNodes() -> [any _LayoutNode] {
        var nodes: [any _LayoutNode] = []
        repeat nodes.append(contentsOf: (each value)._makeLayoutNodes())
        return nodes
    }

    package func _makeLayoutNode() -> any _LayoutNode {
        _ZStackLayoutNode(children: _makeLayoutNodes(), alignment: .topLeading)
    }
}

extension AnyView: _LayoutNodeProducing {
    package func _makeLayoutNode() -> any _LayoutNode {
        content()._makeLayoutNode()
    }
}

extension EmptyView: _LayoutNodeProducing {
    package func _makeLayoutNode() -> any _LayoutNode {
        _ContainerLayoutNode(children: [])
    }
}

extension _ViewModifier_Content: _LayoutNodeProducing {
    package func _makeLayoutNode() -> any _LayoutNode {
        content._makeLayoutNode()
    }
}

extension _EnvironmentWritingContent: _LayoutNodeProducing {
    package func _makeLayoutNode() -> any _LayoutNode {
        _EnvironmentNode(child: content._makeLayoutNode(), update: update)
    }
}

extension _BackgroundColorFill: _LayoutNodeProducing {
    package func _makeLayoutNode() -> any _LayoutNode {
        _LeafNode { canvas, frame, _ in
            canvas.fill(frame, background: color)
        }
    }
}
