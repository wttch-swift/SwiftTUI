import TerminalUIView

extension _EventContent: _LayoutNodeProducing {
    package func _makeLayoutNode() -> any _LayoutNode {
        _EventNode(
            child: content._makeLayoutNode(),
            action: action
        )
    }
}

package protocol _TerminalEventHandlingNode {
    func handle(_ event: TerminalEvent) -> TerminalEventResult
}

final class _EventNode: _UnaryLayoutNode, _TerminalEventHandlingNode {
    let action: (TerminalEvent) -> TerminalEventResult

    init(
        child: any _LayoutNode,
        action: @escaping (TerminalEvent) -> TerminalEventResult
    ) {
        self.action = action
        super.init(child: child)
    }

    package override func measure(proposed: ProposedSize) -> Size {
        child.measure(proposed: proposed)
    }

    package override func layout(in rect: Rect) {
        child.layout(in: rect)
    }

    package func handle(_ event: TerminalEvent) -> TerminalEventResult {
        action(event)
    }
}
