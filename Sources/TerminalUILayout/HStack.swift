/// 将子视图从左到右排列的水平容器。
///
/// 容器宽度是所有子节点宽度之和，高度取最高子节点；`alignment`
/// 决定较矮子节点在容器高度内的垂直位置。
extension HStack: _LayoutNodeProducing {
    /// 为每个子视图创建节点，并交由水平布局节点完成测量和定位。
    package func _makeLayoutNode() -> any _Layoutable {
        _HStackLayoutNode(content: content, alignment: alignment)
    }
}

// MARK: - HStack

private class _HStackLayoutNode: _LayoutContainerStorage, _ContainerLayoutable {
    let alignment: VerticalAlignment

    init<Content: View>(content: Content, alignment: VerticalAlignment) {
        self.alignment = alignment
        super.init(children: content._makeLayoutNodes())
    }

    package func measure(proposed: ProposedSize) -> Size {
        let sizes = minimumSizes(proposed: proposed)
        let flexibleWidth = children.contains { ($0 as? _FlexibleLayoutNode)?.expandsHorizontally == true }
        let natural = Size(
            w: flexibleWidth ? proposed.width ?? sizes.reduce(0) { $0 + $1.w } : sizes.reduce(0) { $0 + $1.w },
            h: sizes.map(\.h).max() ?? 0
        )
        return Size(
            w: min(natural.w, proposed.width ?? natural.w),
            h: min(natural.h, proposed.height ?? natural.h)
        )
    }

    package func layout(in rect: Rect) {
        var sizes = minimumSizes(proposed: ProposedSize(width: rect.w, height: rect.h))
        let remainingWidth = rect.w - sizes.reduce(0) { $0 + $1.w }
        if remainingWidth >= 0 {
            distributeExtraWidth(remainingWidth, into: &sizes)
        } else {
            shrinkOverflow(-remainingWidth, in: &sizes)
        }
        var x = rect.x
        for (i, size) in sizes.enumerated() {
            let assignedWidth = min(size.w, max(0, rect.maxX - x))
            let flexible = children[i] as? _FlexibleLayoutNode
            let assignedHeight = flexible?.expandsVertically == true
                ? rect.h
                : min(size.h, rect.h)
            let y = switch alignment {
            case .top: rect.y
            case .center: rect.y + max(0, rect.h - assignedHeight) / 2
            case .bottom: rect.y + max(0, rect.h - assignedHeight)
            }
            children[i].layout(in: Rect(x: x, y: y, w: assignedWidth, h: assignedHeight))
            x += assignedWidth
        }
    }

    private func minimumSizes(proposed: ProposedSize) -> [Size] {
        children.map { child in
            let flexible = child as? _FlexibleLayoutNode
            return child.measure(proposed: ProposedSize(
                width: flexible?.expandsHorizontally == true ? nil : proposed.width ?? Int.max,
                height: flexible?.expandsVertically == true ? nil : proposed.height ?? Int.max
            ))
        }
    }

    private func distributeExtraWidth(_ extra: Int, into sizes: inout [Size]) {
        let flexibleIndices = children.indices.filter {
            (children[$0] as? _FlexibleLayoutNode)?.expandsHorizontally == true
        }
        guard extra > 0, !flexibleIndices.isEmpty else { return }

        let base = extra / flexibleIndices.count
        let remainder = extra % flexibleIndices.count
        for (offset, index) in flexibleIndices.enumerated() {
            sizes[index] = Size(
                w: sizes[index].w + base + (offset >= flexibleIndices.count - remainder ? 1 : 0),
                h: sizes[index].h
            )
        }
    }

    private func shrinkOverflow(_ overflow: Int, in sizes: inout [Size]) {
        var remaining = overflow
        let flexibleIndices = children.indices.filter {
            (children[$0] as? _FlexibleLayoutNode)?.expandsHorizontally == true
        }

        shrink(indices: flexibleIndices, remaining: &remaining, sizes: &sizes)
        guard remaining > 0 else { return }

        // 如果固定内容本身也超过容器宽度，只能从前向后继续压缩；这和
        // VStack 的溢出策略一致，尽量为靠后的状态/边距内容保留空间。
        shrink(indices: Array(children.indices), remaining: &remaining, sizes: &sizes)
    }

    private func shrink(indices: [Int], remaining: inout Int, sizes: inout [Size]) {
        for index in indices where remaining > 0 {
            let reduction = min(sizes[index].w, remaining)
            sizes[index] = Size(w: sizes[index].w - reduction, h: sizes[index].h)
            remaining -= reduction
        }
    }
}
