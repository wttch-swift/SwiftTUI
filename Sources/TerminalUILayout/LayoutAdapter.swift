// MARK: - _ContainerLayoutNode (base)

/// 容器布局节点基类。子类覆盖 measure/layout 方法实现不同行为。
package class _ContainerLayoutNode: _LayoutNode {
    package var children: [any _LayoutNode]
    package var frame: Rect = .zero

    init(children: [any _LayoutNode]) {
        self.children = children
    }

    init<Content: View>(content: Content) {
        self.children = content._makeLayoutNodes()
    }

    package func measure(proposed: ProposedSize) -> Size { .zero }
    package func layout(in rect: Rect) { frame = rect }

    func measureSizes(proposed: ProposedSize) -> [Size] {
        children.map {
            $0.measure(proposed: ProposedSize(
                width: proposed.width ?? Int.max,
                height: proposed.height ?? Int.max
            ))
        }
    }
}

package protocol _FlexibleLayoutNode {
    var expandsHorizontally: Bool { get }
    var expandsVertically: Bool { get }
}

/// 将当前节点及其子树的绘制限制在指定矩形内。
///
/// 裁剪是渲染能力而非容器继承关系：任何 LayoutNode 都可声明裁剪区域，
/// Render 会在绘制该节点及递归绘制其后代期间共同应用它。
package protocol _ClippingLayoutNode {
    var clipRect: Rect { get }
}

/// 模态容器可限制焦点和导航遍历到当前激活的子树。
package protocol _FocusScopeLayoutNode {
    var focusScopeChildren: [any _LayoutNode] { get }
}

/// 在渲染遍历中为当前子树派生环境值的节点能力。
package protocol _EnvironmentLayoutNode {
    func applyingEnvironment(to environment: EnvironmentValues) -> EnvironmentValues
}

/// 只有一个子节点的容器基类，适合 frame、padding、environment 这类包装节点。
class _UnaryLayoutNode: _ContainerLayoutNode {
    let child: any _LayoutNode

    init(child: any _LayoutNode) {
        self.child = child
        super.init(children: [child])
    }
}

// MARK: - Modifier bridging

extension ModifiedContent: _LayoutNodeProducing
where Content: View, Modifier: ViewModifier {
    package func _makeLayoutNode() -> any _LayoutNode {
        modifier.body(content: _ViewModifier_Content<Modifier>(content))._makeLayoutNode()
    }
}
