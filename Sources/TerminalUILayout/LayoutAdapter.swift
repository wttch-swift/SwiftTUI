// MARK: - _ContainerLayoutNode (base)

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
    var focusScopeChildren: [any _Layoutable] { get }
}

/// 标记当前节点是否正在提供一个激活的模态焦点范围。
///
/// TerminalApp 用它判断 sheet 打开/关闭时是否需要重置焦点入口，避免沿用
/// 底层页面的焦点索引，也避免第一次 Tab 只是从“无焦点”进入弹窗。
package protocol _ModalFocusScopeLayoutNode {
    var isModalFocusScopeActive: Bool { get }
}

/// 在渲染遍历中为当前子树派生环境值的节点能力。
package protocol _EnvironmentLayoutNode {
    func applyingEnvironment(to environment: EnvironmentValues) -> EnvironmentValues
}

// MARK: - Modifier bridging

extension ModifiedContent: _LayoutNodeProducing
where Content: View, Modifier: ViewModifier {
    package func _makeLayoutNode() -> any _Layoutable {
        modifier.body(content: _ViewModifier_Content<Modifier>(content))._makeLayoutNode()
    }
}
