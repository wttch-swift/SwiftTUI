import TerminalUIView

/// 基础视图到布局系统的内部桥梁。
///
/// 它不属于公共 API：业务视图通常只需实现 `body`，框架基础视图才直接
/// 生成节点，从而避免构造没有意义的中间 View。
package protocol _LayoutNodeProducing {
    func _makeLayoutNode() -> any _Layoutable
}

/// 能够在容器中展开为多个同级布局节点的 View。
package protocol _MultiViewProducing {
    func _makeLayoutNodes() -> [any _Layoutable]
}

package extension View {
    /// 递归展开组合视图，直到得到可直接参与布局的节点。
    func _makeLayoutNode() -> any _Layoutable {
        if let primitive = self as? any _LayoutNodeProducing {
            return primitive._makeLayoutNode()
        }
        return body._makeLayoutNode()
    }


    /// 展开组合视图，直到得到可直接参与布局的节点列表。
    func _makeLayoutNodes() -> [any _Layoutable] {
        if let list = self as? any _MultiViewProducing {
            return list._makeLayoutNodes()
        }
        return [_makeLayoutNode()]
    }
}
