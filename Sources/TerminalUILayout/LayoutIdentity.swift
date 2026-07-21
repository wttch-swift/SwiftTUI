/// Stable identity attached to layout nodes produced by dynamic collections.
/// The identity is internal to the layout layer; public Views continue to use
/// SwiftUI-style `ForEach(data, id:)` without knowing about layout nodes.
package protocol _IdentifiedLayoutNode: _Layoutable {
    var reconciliationID: AnyHashable { get }
    var reconciliationChildIndex: Int { get }
}

package func _makeIdentifiedLayoutNode(
    child: any _Layoutable,
    id: AnyHashable,
    childIndex: Int
) -> any _Layoutable {
    _IdentityLayoutNode(
        child: child,
        id: id,
        childIndex: childIndex
    )
}

private final class _IdentityLayoutNode: _LayoutContainerStorage, _PassthroughUnaryLayoutable,
    _IdentifiedLayoutNode {
    let reconciliationID: AnyHashable
    let reconciliationChildIndex: Int

    init(child: any _Layoutable, id: AnyHashable, childIndex: Int) {
        reconciliationID = id
        reconciliationChildIndex = childIndex
        super.init(children: [child])
    }
}

extension _IdentityView: _LayoutNodeProducing {
    package func _makeLayoutNode() -> any _Layoutable {
        _makeIdentifiedLayoutNode(child: content._makeLayoutNode(), id: id, childIndex: 0)
    }
}
