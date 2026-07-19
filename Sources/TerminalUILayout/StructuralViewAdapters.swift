import TerminalUIView

extension _ArrayView: _MultiViewProducing {
    package func _makeLayoutNodes() -> [any _Layoutable] {
        content.flatMap { $0._makeLayoutNodes() }
    }
}

extension _OptionalView: _MultiViewProducing {
    package func _makeLayoutNodes() -> [any _Layoutable] {
        content?._makeLayoutNodes() ?? []
    }
}

extension _ConditionalView: _MultiViewProducing {
    package func _makeLayoutNodes() -> [any _Layoutable] {
        switch self {
        case .trueContent(let content): content._makeLayoutNodes()
        case .falseContent(let content): content._makeLayoutNodes()
        }
    }
}

extension TupleView: _LayoutNodeProducing, _MultiViewProducing {
    package func _makeLayoutNodes() -> [any _Layoutable] {
        var nodes: [any _Layoutable] = []
        repeat nodes.append(contentsOf: (each value)._makeLayoutNodes())
        return nodes
    }

    package func _makeLayoutNode() -> any _Layoutable {
        _makeZStackLayoutNode(children: _makeLayoutNodes(), alignment: .topLeading)
    }
}

extension AnyView: _LayoutNodeProducing {
    package func _makeLayoutNode() -> any _Layoutable {
        content()._makeLayoutNode()
    }
}

extension EmptyView: _LayoutNodeProducing {
    package func _makeLayoutNode() -> any _Layoutable {
        _makeContainerLayoutNode(children: [])
    }
}

extension _ViewModifier_Content: _LayoutNodeProducing {
    package func _makeLayoutNode() -> any _Layoutable {
        content._makeLayoutNode()
    }
}

extension _EnvironmentWritingContent: _LayoutNodeProducing {
    package func _makeLayoutNode() -> any _Layoutable {
        _makeEnvironmentLayoutNode(child: content._makeLayoutNode(), update: update)
    }
}

extension _BackgroundColorFill: _LayoutNodeProducing {
    package func _makeLayoutNode() -> any _Layoutable {
        _makeLeafLayoutNode(
            fingerprint: { _ in
                var hasher = Hasher()
                hasher.combine(color)
                return hasher.finalize()
            }
        ) { canvas, frame, _ in
            canvas.fill(frame, background: color)
        }
    }
}
