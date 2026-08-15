

/// 在子节点四周增加固定终端 cell 留白的布局包装节点。
package func _makePaddingLayoutNode(
    child: any _Layoutable,
    top: Int,
    right: Int,
    bottom: Int,
    left: Int
) -> any _Layoutable {
    _PaddingLayoutNode(child: child, top: top, right: right, bottom: bottom, left: left)
}

private final class _PaddingLayoutNode: _LayoutContainerStorage, _UnaryLayoutable {
    let top: Int
    let right: Int
    let bottom: Int
    let left: Int

    init(child: any _Layoutable, top: Int, right: Int, bottom: Int, left: Int) {
        self.top = top
        self.right = right
        self.bottom = bottom
        self.left = left
        super.init(children: [child])
    }

    /// 先扣除 padding 测量子节点，再把四边留白加回结果。
    package func measure(proposed: ProposedSize) -> Size {
        let horizontal = left + right
        let vertical = top + bottom
        let size = child.measure(
            proposed: ProposedSize(
                width: proposed.width.map { max(0, $0 - horizontal) },
                height: proposed.height.map { max(0, $0 - vertical) }
            )
        )
        return Size(w: size.w + horizontal, h: size.h + vertical)
    }

    /// 把父节点分配区域内缩后交给子节点。
    package func layout(in rect: Rect) {
        child.layout(
            in: Rect(
                x: rect.x + left,
                y: rect.y + top,
                w: max(0, rect.w - left - right),
                h: max(0, rect.h - top - bottom)
            )
        )
    }
}
