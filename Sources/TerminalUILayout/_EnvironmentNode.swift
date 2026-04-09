/// 环境节点：包装一个子节点，并为整棵子树注入环境值。
///
/// 它对测量和布局完全透明；只有 Render 遍历到该节点时才复制父环境、
/// 执行 `update`，随后把新值传给子节点。复制语义保证兄弟分支互不污染。
final class _EnvironmentNode: _UnaryLayoutNode, _EnvironmentLayoutNode {
    let update: (inout EnvironmentValues) -> Void

    init(child: any _LayoutNode, update: @escaping (inout EnvironmentValues) -> Void) {
        self.update = update
        super.init(child: child)
    }

    package override func measure(proposed: ProposedSize) -> Size { child.measure(proposed: proposed) }
    package override func layout(in rect: Rect) { child.layout(in: rect) }

    /// 基于父环境生成当前子树可见的环境快照。
    package func applyingEnvironment(to environment: EnvironmentValues) -> EnvironmentValues {
        var result = environment
        update(&result)
        return result
    }
}
