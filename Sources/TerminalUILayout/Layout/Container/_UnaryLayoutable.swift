

/// 容器布局节点协议。用于标记一个布局节点是容器布局节点。
package protocol _UnaryLayoutable: _ContainerLayoutable {
    var child: any _Layoutable { get }
}

/// 默认把第一个 children 作为 child。
package extension _UnaryLayoutable {
    var child: any _Layoutable { children[0] }
}
