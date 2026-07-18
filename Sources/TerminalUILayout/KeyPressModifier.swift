extension _KeyPressContent: _LayoutNodeProducing {
    package func _makeLayoutNode() -> any _LayoutNode {
        _KeyPressNode(
            child: content._makeLayoutNode(),
            keys: keys,
            action: action
        )
    }
}

package protocol _KeyPressHandlingNode {
    func handle(_ event: KeyPress) -> KeyPress.Result
}

final class _KeyPressNode: _UnaryLayoutNode, _KeyPressHandlingNode {
    let keys: Set<KeyPress.Key>?
    let action: (KeyPress) -> KeyPress.Result

    init(
        child: any _LayoutNode,
        keys: Set<KeyPress.Key>?,
        action: @escaping (KeyPress) -> KeyPress.Result
    ) {
        self.keys = keys
        self.action = action
        super.init(child: child)
    }

    package override func measure(proposed: ProposedSize) -> Size {
        child.measure(proposed: proposed)
    }

    package override func layout(in rect: Rect) {
        child.layout(in: rect)
    }

    package func handle(_ event: KeyPress) -> KeyPress.Result {
        guard keys?.contains(event.key) ?? true else { return .ignored }
        return action(event)
    }
}

extension _KeyPressNode: _TerminalEventHandlingNode {
    package func handle(_ event: TerminalEvent) -> TerminalEventResult {
        guard case .key(let keyPress) = event else { return .ignored }
        return switch handle(keyPress) {
        case .handled: TerminalEventResult.handled
        case .ignored: TerminalEventResult.ignored
        }
    }
}
