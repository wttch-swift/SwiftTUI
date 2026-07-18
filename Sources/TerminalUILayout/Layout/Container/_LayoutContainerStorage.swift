

/// 用来存储 LayoutNode 布局数据的基类。
package class _LayoutContainerStorage {
    package var children: [any _Layoutable]

    init(children: [any _Layoutable]) {
        self.children = children
    }
} 
