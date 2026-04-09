/// 将子视图从上到下排列的垂直容器。
///
/// `VStack` 本身只保存声明得到的泛型 `Content` 和水平对齐方式，真正的
/// 测量与布局由 `_VStackLayoutNode` 完成。布局规则如下：
///
/// - 理想宽度取所有子节点理想宽度的最大值；
/// - 理想高度取所有子节点理想高度之和；
/// - 存在纵向可伸缩节点（例如 `Spacer()`）时，它会接收容器的剩余高度；
/// - 内容总高度超过容器时，先压缩可伸缩节点，再从前向后压缩普通内容，
///   从而为位于尾部的状态栏或操作栏保留空间；
/// - `alignment` 决定较窄子节点在容器宽度内的水平位置。
extension VStack: _LayoutNodeProducing {
    /// 构造负责纵向测量与定位的布局节点。
    package func _makeLayoutNode() -> any _LayoutNode {
        _VStackLayoutNode(content: content, alignment: alignment)
    }
}


final class _VStackLayoutNode: _ContainerLayoutNode {
    /// 子节点在水平方向上的对齐方式。
    let alignment: HorizontalAlignment

    init<Content: View>(content: Content, alignment: HorizontalAlignment) {
        self.alignment = alignment
        super.init(content: content)
    }

    /// 计算当前节点在父节点给定尺寸建议下希望占用的尺寸。
    ///
    /// `minimumSizes` 会先分别测量每个子节点。普通子节点会收到父节点在
    /// 对应轴上的尺寸建议；可伸缩子节点在其伸缩轴上收到 `nil`，因此这里只
    /// 得到它的最小尺寸，而不会让单个 `Spacer` 提前吞掉全部可用空间。
    ///
    /// 如果包含纵向可伸缩节点，VStack 的理想高度优先采用父节点建议高度，
    /// 这样 `Spacer()` 才能把容器撑满；否则高度就是所有子节点高度之和。
    /// 最终结果仍会被 proposal 截断，保证测量结果不越过父布局的约束。
    package override func measure(proposed: ProposedSize) -> Size {
        let sizes = minimumSizes(proposed: proposed)
        let flexibleHeight = children.contains { ($0 as? _FlexibleLayoutNode)?.expandsVertically == true }
        let natural = Size(
            w: sizes.map(\.w).max() ?? 0,
            h: flexibleHeight ? proposed.height ?? sizes.reduce(0) { $0 + $1.h } : sizes.reduce(0) { $0 + $1.h }
        )
        return Size(
            w: min(natural.w, proposed.width ?? natural.w),
            h: min(natural.h, proposed.height ?? natural.h)
        )
    }

    /// 在父节点分配的最终矩形内确定每个子节点的位置和尺寸。
    ///
    /// 布局分为三个阶段：
    ///
    /// 1. 重新取得所有子节点的最小尺寸；
    /// 2. 有剩余空间时分给纵向可伸缩节点，空间不足时压缩已有尺寸；
    /// 3. 从上向下累加 `y`，并根据 `alignment` 计算每个子节点的 `x`。
    ///
    /// 第 2 步会在定位前完成，因此所有子节点高度之和不会超过 `rect.h`，
    /// 后面的子节点不会再因为顺序截断而意外得到零高度。
    package override func layout(in rect: Rect) {
        super.layout(in: rect)
        var sizes = minimumSizes(proposed: ProposedSize(width: rect.w, height: rect.h))
        let remainingHeight = rect.h - sizes.reduce(0) { $0 + $1.h }
        if remainingHeight >= 0 {
            distributeExtraHeight(remainingHeight, into: &sizes)
        } else {
            shrinkOverflow(-remainingHeight, in: &sizes)
        }
        var y = rect.y
        for (i, size) in sizes.enumerated() {
            let flexible = children[i] as? _FlexibleLayoutNode
            let assignedWidth = flexible?.expandsHorizontally == true
                ? rect.w
                : min(size.w, rect.w)
            // VStack 只负责水平方向的对齐。max(0, ...) 可避免子节点比容器宽
            // 时产生负偏移；实际分配宽度也会被 rect.w 限制。
            let x = switch alignment {
            case .leading: rect.x
            case .center: rect.x + max(0, rect.w - assignedWidth) / 2
            case .trailing: rect.x + max(0, rect.w - assignedWidth)
            }
            children[i].layout(in: Rect(x: x, y: y, w: assignedWidth, h: size.h))
            y += size.h
        }
    }

    /// 测量各个子节点用于空间分配的最小尺寸。
    ///
    /// 可伸缩节点在它声明可扩展的轴上收到 `nil` proposal，只报告固有最小
    /// 尺寸；普通节点则收到父节点的可用尺寸。真正的剩余空间随后由 VStack
    /// 统一分配，避免多个 Spacer 各自按照完整容器尺寸进行测量。
    private func minimumSizes(proposed: ProposedSize) -> [Size] {
        children.map { child in
            let flexible = child as? _FlexibleLayoutNode
            return child.measure(proposed: ProposedSize(
                width: flexible?.expandsHorizontally == true ? nil : proposed.width ?? Int.max,
                height: flexible?.expandsVertically == true ? nil : proposed.height ?? Int.max
            ))
        }
    }

    /// 将正的剩余高度平均分配给所有纵向可伸缩子节点。
    ///
    /// 整数除法产生的余数逐个补给末尾的可伸缩节点，确保最终分配高度之和
    /// 精确等于容器高度，而不会因为取整留下未使用的行。
    private func distributeExtraHeight(_ extra: Int, into sizes: inout [Size]) {
        let flexibleIndices = children.indices.filter {
            (children[$0] as? _FlexibleLayoutNode)?.expandsVertically == true
        }
        guard extra > 0, !flexibleIndices.isEmpty else { return }

        let base = extra / flexibleIndices.count
        let remainder = extra % flexibleIndices.count
        for (offset, index) in flexibleIndices.enumerated() {
            sizes[index] = Size(
                w: sizes[index].w,
                h: sizes[index].h + base + (offset >= flexibleIndices.count - remainder ? 1 : 0)
            )
        }
    }

    /// 处理子节点理想高度之和超过容器高度的情况。
    ///
    /// 压缩顺序刻意分成两级：
    ///
    /// 1. 先压缩纵向可伸缩节点，因为 Spacer 的职责就是吸收空间变化；
    /// 2. 仍有溢出时，从前向后压缩普通节点，为尾部固定内容保留空间。
    ///
    /// 第二条使常见的“主内容 + 底部状态栏”结构在终端高度不足时仍能显示
    /// 状态栏。节点允许被压缩到 0，但永远不会出现负高度。
    private func shrinkOverflow(_ overflow: Int, in sizes: inout [Size]) {
        var remaining = overflow
        let flexibleIndices = children.indices.filter {
            (children[$0] as? _FlexibleLayoutNode)?.expandsVertically == true
        }

        shrink(indices: flexibleIndices, remaining: &remaining, sizes: &sizes)
        guard remaining > 0 else { return }

        let fixedIndices = children.indices.filter { !flexibleIndices.contains($0) }
        shrink(indices: fixedIndices, remaining: &remaining, sizes: &sizes)
    }

    /// 按指定下标顺序消耗需要压缩的高度。
    ///
    /// 每个节点最多减少到 0；`remaining` 以 `inout` 传递，使调用者可以先
    /// 压缩一组节点，再把尚未消除的溢出继续交给下一组节点处理。
    private func shrink(
        indices: [Int],
        remaining: inout Int,
        sizes: inout [Size]
    ) {
        for index in indices where remaining > 0 {
            let amount = min(remaining, sizes[index].h)
            sizes[index] = Size(w: sizes[index].w, h: sizes[index].h - amount)
            remaining -= amount
        }
    }
}
