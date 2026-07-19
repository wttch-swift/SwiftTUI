

/// 可布局容器。
/// 纯 measure/layout 能力，包含 children。
package protocol _ContainerLayoutable: _Layoutable {

    /// 子节点数组。
    var children: [any _Layoutable] { get }
}


/// 容器布局节点基类。子类覆盖 measure/layout 方法实现不同行为。
package func _makeContainerLayoutNode(children: [any _Layoutable]) -> any _Layoutable {
    _ContainerLayoutNode(children: children)
}

private final class _ContainerLayoutNode: _LayoutContainerStorage, _ContainerLayoutable {
    package func measure(proposed: ProposedSize) -> Size { .zero }
    package func layout(in rect: Rect) {}
}
