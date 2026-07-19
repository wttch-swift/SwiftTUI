/// 在同一矩形区域内按深度叠放子视图的容器。
///
/// 子视图按照数组顺序绘制，后绘制的内容会覆盖先绘制的单元格。
/// 容器尺寸取所有子节点宽度和高度的最大值。
extension ZStack: _LayoutNodeProducing {
    /// 构造负责重叠布局的节点。
    package func _makeLayoutNode() -> any _Layoutable {
        _ZStackLayoutNode(content: content, alignment: alignment)
    }
}

package func _makeZStackLayoutNode(
    children: [any _Layoutable],
    alignment: AlignmentEdge
) -> any _Layoutable {
    _ZStackLayoutNode(children: children, alignment: alignment)
}

private final class _ZStackLayoutNode: _LayoutContainerStorage, _ContainerLayoutable {
    let alignment: AlignmentEdge

    init<Content: View>(content: Content, alignment: AlignmentEdge) {
        self.alignment = alignment
        super.init(children: content._makeLayoutNodes())
    }

    init(children: [any _Layoutable], alignment: AlignmentEdge) {
        self.alignment = alignment
        super.init(children: children)
    }

    package func measure(proposed: ProposedSize) -> Size {
        let sizes = children.map { child in
            let flexible = child as? _FlexibleLayoutNode
            return child.measure(proposed: ProposedSize(
                width: flexible?.expandsHorizontally == true ? nil : proposed.width ?? Int.max,
                height: flexible?.expandsVertically == true ? nil : proposed.height ?? Int.max
            ))
        }
        let flexibleWidth = children.contains { ($0 as? _FlexibleLayoutNode)?.expandsHorizontally == true }
        let flexibleHeight = children.contains { ($0 as? _FlexibleLayoutNode)?.expandsVertically == true }
        let natural = Size(
            w: flexibleWidth ? proposed.width ?? sizes.map(\.w).max() ?? 0 : sizes.map(\.w).max() ?? 0,
            h: flexibleHeight ? proposed.height ?? sizes.map(\.h).max() ?? 0 : sizes.map(\.h).max() ?? 0
        )
        return Size(
            w: min(natural.w, proposed.width ?? natural.w),
            h: min(natural.h, proposed.height ?? natural.h)
        )
    }

    package func layout(in rect: Rect) {
        let sizes = children.map { child in
            let flexible = child as? _FlexibleLayoutNode
            let measured = child.measure(proposed: ProposedSize(
                width: flexible?.expandsHorizontally == true ? nil : rect.w,
                height: flexible?.expandsVertically == true ? nil : rect.h
            ))
            return Size(
                w: flexible?.expandsHorizontally == true ? rect.w : min(measured.w, rect.w),
                h: flexible?.expandsVertically == true ? rect.h : min(measured.h, rect.h)
            )
        }
        for (i, size) in sizes.enumerated() {
            let origin = alignedOrigin(parent: rect, child: size, alignment: alignment)
            children[i].layout(in: Rect(x: origin.x, y: origin.y, w: size.w, h: size.h))
        }
    }
}
