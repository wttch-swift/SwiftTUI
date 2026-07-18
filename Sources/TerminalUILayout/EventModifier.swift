import TerminalUIView

extension _EventContent: _LayoutNodeProducing {
    package func _makeLayoutNode() -> any _Layoutable {
        _EventNode(
            child: content._makeLayoutNode(),
            action: action
        )
    }
}

package protocol _TerminalEventHandlingNode {
    func handle(_ event: TerminalEvent) -> TerminalEventResult
}

final class _EventNode: _LayoutContainerStorage, _PassthroughUnaryLayoutable, _TerminalEventHandlingNode {
    let action: (TerminalEvent) -> TerminalEventResult

    init(
        child: any _Layoutable,
        action: @escaping (TerminalEvent) -> TerminalEventResult
    ) {
        self.action = action
        super.init(children: [child])
    } 


    package func handle(_ event: TerminalEvent) -> TerminalEventResult {
        action(event)
    }
}
