/// Matches freshly generated layout nodes with the preceding frame and moves
/// transient interaction state to the new instances. Identity-aware matching is
/// deliberately kept outside View construction, layout, and rendering so the
/// existing pipeline remains unchanged.
package enum LayoutReconciler {
    private struct IdentityKey: Hashable {
        let id: AnyHashable
        let childIndex: Int
    }

    package static func reconcile(
        from previous: (any _Layoutable)?,
        to current: any _Layoutable
    ) {
        guard let previous else { return }
        reconcileMatched(from: previous, to: current)
    }

    private static func reconcileMatched(
        from previous: any _Layoutable,
        to current: any _Layoutable
    ) {
        guard nodesMatch(previous, current) else { return }

        if let oldTab = previous as? any _TabSelectionNode,
           let newTab = current as? any _TabSelectionNode {
            newTab.restoreSelection(from: oldTab.selectedIndex)
        }
        if let oldTarget = previous as? any _FocusTargetLayoutNode,
           let newTarget = current as? any _FocusTargetLayoutNode {
            newTarget.restoreInteractionState(from: oldTarget)
            // A FocusState wrapper is the state boundary and forwards to its
            // target. Descending further would restore that target twice.
            if current is any _FocusBindingLayoutNode { return }
        }

        guard let oldContainer = previous as? any _ContainerLayoutable,
              let newContainer = current as? any _ContainerLayoutable else { return }

        var oldByIdentity: [IdentityKey: any _Layoutable] = [:]
        for child in oldContainer.children {
            if let key = identityKey(in: child) {
                oldByIdentity[key] = child
            }
        }

        for (index, newChild) in newContainer.children.enumerated() {
            if let key = identityKey(in: newChild) {
                if let oldChild = oldByIdentity[key] {
                    reconcileMatched(from: oldChild, to: newChild)
                }
                continue
            }
            guard oldContainer.children.indices.contains(index) else { continue }
            reconcileMatched(from: oldContainer.children[index], to: newChild)
        }
    }

    private static func nodesMatch(
        _ previous: any _Layoutable,
        _ current: any _Layoutable
    ) -> Bool {
        let oldIdentity = identityKey(in: previous)
        let newIdentity = identityKey(in: current)
        if oldIdentity != nil || newIdentity != nil {
            guard oldIdentity == newIdentity else { return false }
        }
        return ObjectIdentifier(type(of: previous)) == ObjectIdentifier(type(of: current))
    }

    /// An explicit `.id` may sit below transparent unary modifiers. Looking
    /// through that chain keeps identity stable regardless of modifier order.
    private static func identityKey(in root: any _Layoutable) -> IdentityKey? {
        var node = root
        while true {
            if let identified = node as? any _IdentifiedLayoutNode {
                return IdentityKey(
                    id: identified.reconciliationID,
                    childIndex: identified.reconciliationChildIndex
                )
            }
            guard let unary = node as? any _UnaryLayoutable else { return nil }
            node = unary.child
        }
    }
}
