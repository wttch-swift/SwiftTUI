

/// 弹性布局节点协议，表示该节点在布局时可以根据父容器的大小进行扩展。
protocol _FlexibleLayoutNode {
    /// 指示该节点是否在水平方向上可以扩展以填充父容器的剩余空间。
    var expandsHorizontally: Bool { get }

    /// 指示该节点是否在垂直方向上可以扩展以填充父容器的剩余空间。
    var expandsVertically: Bool { get }
}

extension _FlexibleLayoutNode where Self: _ContainerLayoutable {

}