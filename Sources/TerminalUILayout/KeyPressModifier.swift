extension _KeyPressContent: _LayoutNodeProducing {
    package func _makeLayoutNode() -> any _Layoutable {
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

final class _KeyPressNode: _LayoutContainerStorage, _PassthroughUnaryLayoutable, _KeyPressHandlingNode {
    let keys: Set<KeyPress.Key>?
    let action: (KeyPress) -> KeyPress.Result

    init(
        child: any _Layoutable,
        keys: Set<KeyPress.Key>?,
        action: @escaping (KeyPress) -> KeyPress.Result
    ) {
        self.keys = keys
        self.action = action
        super.init(children: [child])
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
