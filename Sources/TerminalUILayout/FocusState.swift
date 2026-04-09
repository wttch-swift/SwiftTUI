import TerminalUIView

extension _FocusedView: _LayoutNodeProducing {
    package func _makeLayoutNode() -> any _LayoutNode {
        let child = content._makeLayoutNode()
        guard let focusable = _firstFocusTargetNode(in: child) else { return child }
        focusable.focusBindingDidAttach()
        return _FocusedLayoutNode(
            child: child,
            focusable: focusable,
            requestsFocus: requestsFocus,
            updateFocus: updateFocus
        )
    }
}

/// FocusState 与具体输入节点之间的内部桥梁。
package protocol _FocusBindingLayoutNode: _FocusableLayoutNode {
    var requestsFocus: Bool { get }
}

private final class _FocusedLayoutNode: _UnaryLayoutNode, _FocusBindingLayoutNode,
    _FlexibleLayoutNode {
    let focusable: any _FocusTargetLayoutNode
    let readFocus: () -> Bool
    let updateFocus: (Bool) -> Void

    var requestsFocus: Bool { readFocus() }
    var isFocused: Bool { focusable.isFocused }
    var expandsHorizontally: Bool {
        (child as? any _FlexibleLayoutNode)?.expandsHorizontally ?? false
    }
    var expandsVertically: Bool {
        (child as? any _FlexibleLayoutNode)?.expandsVertically ?? false
    }

    init(
        child: any _LayoutNode,
        focusable: any _FocusTargetLayoutNode,
        requestsFocus: @escaping () -> Bool,
        updateFocus: @escaping (Bool) -> Void
    ) {
        self.focusable = focusable
        self.readFocus = requestsFocus
        self.updateFocus = updateFocus
        super.init(child: child)
    }

    package override func measure(proposed: ProposedSize) -> Size {
        child.measure(proposed: proposed)
    }

    package override func layout(in rect: Rect) {
        child.layout(in: rect)
    }

    func setFocused(_ focused: Bool) {
        focusable.setFocused(focused)
        if requestsFocus != focused { updateFocus(focused) }
    }

    func handleFocusedKey(_ event: KeyPress) -> KeyPress.Result {
        focusable.handleFocusedKey(event)
    }

    func restoreInteractionState(from node: any _FocusTargetLayoutNode) {
        guard let previous = node as? _FocusedLayoutNode else { return }
        focusable.restoreInteractionState(from: previous.focusable)
    }
}

private func _firstFocusTargetNode(in node: any _LayoutNode) -> (any _FocusTargetLayoutNode)? {
    if let focusable = node as? any _FocusTargetLayoutNode { return focusable }
    guard let container = node as? _ContainerLayoutNode else { return nil }
    let children = (node as? any _FocusScopeLayoutNode)?.focusScopeChildren
        ?? container.children
    for child in children {
        if let focusable = _firstFocusTargetNode(in: child) { return focusable }
    }
    return nil
}

/// 判断一棵布局子树中是否存在当前获得焦点的交互目标。
///
/// 通用边框通过这个查询实现一致的默认焦点效果。遇到 FocusState 包装节点时
/// 直接读取包装节点即可；不再向内递归，避免同一个目标被重复解释。
package func _containsFocusedTarget(in node: any _LayoutNode) -> Bool {
    if let focusable = node as? any _FocusTargetLayoutNode {
        return focusable.isFocused
    }
    guard let container = node as? _ContainerLayoutNode else { return false }
    let children = (node as? any _FocusScopeLayoutNode)?.focusScopeChildren
        ?? container.children
    return children.contains(where: _containsFocusedTarget)
}

/// 允许 background 中的装饰节点观察其对应前景内容的焦点状态。
package protocol _FocusEffectSourceLayoutNode: AnyObject {
    var focusEffectSource: (any _LayoutNode)? { get set }
}

/// 把前景内容连接到背景子树里所有支持焦点效果的装饰节点。
package func _attachFocusEffectSource(
    _ source: any _LayoutNode,
    to node: any _LayoutNode
) {
    if let effect = node as? any _FocusEffectSourceLayoutNode {
        effect.focusEffectSource = source
    }
    guard let container = node as? _ContainerLayoutNode else { return }
    for child in container.children {
        _attachFocusEffectSource(source, to: child)
    }
}
