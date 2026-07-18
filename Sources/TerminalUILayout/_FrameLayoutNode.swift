

/// 为子节点提供可选固定尺寸，并在该区域内执行对齐的布局包装节点。
///
/// 未指定的轴沿用子节点测量结果；真正布局时目标尺寸不会超过父节点
/// 分配的 `rect`，防止子节点写出父布局范围。
final class _FrameLayoutNode: _LayoutContainerStorage, _UnaryLayoutable {
    let width: Int?
    let height: Int?
    let alignment: AlignmentEdge

    init(child: any _Layoutable, width: Int?, height: Int?, alignment: AlignmentEdge) {
        self.width = width
        self.height = height
        self.alignment = alignment
        super.init(children: [child])
    }

    /// 返回显式尺寸，或回退到子节点的理想尺寸。
    package func measure(proposed: ProposedSize) -> Size {
        let childSize = child.measure(proposed: proposed)
        return Size(w: width ?? childSize.w, h: height ?? childSize.h)
    }

    /// 根据 alignment 计算子节点在最终 frame 中的原点。
    package func layout(in rect: Rect) {
        let measuredSize = child.measure(proposed: ProposedSize(width: rect.w, height: rect.h))
        let targetSize = Size(
            w: min(rect.w, width ?? measuredSize.w),
            h: min(rect.h, height ?? measuredSize.h)
        )
        let origin = alignedOrigin(
            parent: rect,
            child: targetSize,
            alignment: alignment
        )
        child.layout(in: Rect(x: origin.x, y: origin.y, w: targetSize.w, h: targetSize.h))
    }
}
