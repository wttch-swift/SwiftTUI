/// 根据数据集动态生成一组同级 View。
///
/// `ForEach` 使用方式与 SwiftUI 一致：数据元素可以自行遵循
/// `Identifiable`，也可以通过 `id` 键路径显式指定身份。
extension ForEach: _MultiViewProducing, _LayoutNodeProducing {
    /// 容器调用此方法时，`ForEach` 不形成额外布局层，
    /// 而是把每个元素生成的节点展开成 VStack/HStack 的直接子节点。
    package func _makeLayoutNodes() -> [any _Layoutable] {
        data.flatMap { element in
            // 读取身份以保证该键路径与当前元素一起参与生成过程。
            // 当引入节点 diff 时，这里会将该值写入动态节点身份。
            _ = element[keyPath: id]
            return content(element)._makeLayoutNodes()
        }
    }

    /// 当 `ForEach` 被修饰器等场景当作单个 View 请求节点时，
    /// 使用顶部左对齐的 ZStack 作为退化包装。普通 Stack 会走上面的多节点路径。
    package func _makeLayoutNode() -> any _Layoutable {
        _ZStackLayoutNode(children: _makeLayoutNodes(), alignment: .topLeading)
    }
}
