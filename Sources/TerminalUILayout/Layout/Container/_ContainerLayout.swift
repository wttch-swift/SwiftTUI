

/// 可布局容器。
/// 纯 measure/layout 能力，包含 children。
package protocol _ContainerLayoutable: _Layoutable {

    /// 子节点数组。
    var children: [any _Layoutable] { get }
}
