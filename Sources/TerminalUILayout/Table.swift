/// 表格列的声明，用于定义标题和每行的单元格内容。
/// 构建一组同行类型的 `TableColumn`。
/// 每个表达式先转换为单元素数组，后续 block/if/for 统一执行扁平化，
/// 因而无需为异构列引入 `AnyView`。
/// 以 SwiftUI 风格的列声明显示数据集。
///
/// ```swift
/// Table(players) {
///     TableColumn("姓名", value: \.name)
///     TableColumn("分数") { player in Text("\(player.score)") }
/// }
/// ```
extension Table: _LayoutNodeProducing {
    package func _makeLayoutNode() -> any _Layoutable {
        _TableLayoutNode(rows: rows, columns: columns, style: style)
    }
}

/// Table 的二维布局节点。它一方面是容器，负责定位每个单元格子节点；
/// 另一方面是可渲染节点，在子节点之前画所有共享边框。
private final class _TableLayoutNode<RowValue>: _ContainerLayoutNode, _RenderableLayoutNode {
    private let columns: [TableColumn<RowValue>]
    /// 二维数组的第 0 行始终是表头，后续行与输入数据一一对应。
    private let cellRows: [[any _Layoutable]]
    private let style: BorderStyle
    private(set) var frame: Rect = .zero
    /// “距离”是相邻共享边框坐标之差，不是整个 cell rect 的宽/高。
    /// 因此表格总宽为 `1 + sum(columnDistances)`，cell 的绘制宽度为 `distance + 1`。
    private var columnDistances: [Int] = []
    private var rowDistances: [Int] = []

    init(rows: [RowValue], columns: [TableColumn<RowValue>], style: BorderStyle) {
        self.columns = columns
        self.style = style

        let header = columns.map { Text($0.title)._makeLayoutNode() }
        let body = rows.map { row in columns.map { $0.makeCell(row)._makeLayoutNode() } }
        self.cellRows = columns.isEmpty ? [] : [header] + body
        super.init(children: cellRows.flatMap { $0 })
    }

    /// 测量分为两阶段：先根据表头和全部单元格求列天然宽度，
    /// 再在已拟合的列宽下重新测量换行后的行高。
    package override func measure(proposed: ProposedSize) -> Size {
        guard !columns.isEmpty else { return .zero }

        let naturalColumns = naturalColumnDistances()
        let width = min(naturalColumns.reduce(1, +), proposed.width ?? Int.max)
        let fittedColumns = fit(naturalColumns, total: max(0, width - 1), minimum: 1)
        let naturalRows = naturalRowDistances(columnDistances: fittedColumns)
        let height = min(naturalRows.reduce(1, +), proposed.height ?? Int.max)
        return Size(w: max(0, width), h: max(0, height))
    }

    /// 用最终 rect 重新拟合列与行，然后把单元格内容放在共享边框之间。
    /// 水平 padding 仅在轨道足够宽时保留；窄终端中优先留出实际内容空间。
    package override func layout(in rect: Rect) {
        frame = rect
        guard !columns.isEmpty, rect.w > 1, rect.h > 1 else {
            children.forEach { $0.layout(in: .zero) }
            columnDistances = []
            rowDistances = []
            return
        }

        columnDistances = fit(
            naturalColumnDistances(),
            total: max(0, rect.w - 1),
            minimum: 1,
            expands: true
        )
        let naturalRows = naturalRowDistances(columnDistances: columnDistances)
        let usedHeight = min(naturalRows.reduce(1, +), rect.h)
        rowDistances = fit(naturalRows, total: max(0, usedHeight - 1), minimum: 1)
        frame = Rect(x: rect.x, y: rect.y, w: rect.w, h: usedHeight)

        var y = frame.y
        for rowIndex in cellRows.indices {
            var x = frame.x
            let rowDistance = rowDistances[rowIndex]
            for columnIndex in columns.indices {
                let columnDistance = columnDistances[columnIndex]
                let padding = horizontalPadding(for: columnDistance)
                let contentWidth = max(0, columnDistance - 1 - padding * 2)
                let child = cellRows[rowIndex][columnIndex]
                let measured = child.measure(
                    proposed: ProposedSize(width: contentWidth, height: max(0, rowDistance - 1))
                )
                // 长内容需要获得完整 contentWidth，Text 才能在正确的列边界换行；
                // 短内容则保持固有宽度，为 center/trailing 对齐留出可移动空间。
                let idealWidth = child.measure(proposed: ProposedSize()).w
                let childWidth = idealWidth > contentWidth ? contentWidth : min(measured.w, contentWidth)
                let childX = switch columns[columnIndex].alignment {
                case .leading: x + 1 + padding
                case .center: x + 1 + padding + max(0, contentWidth - childWidth) / 2
                case .trailing: x + 1 + padding + max(0, contentWidth - childWidth)
                }
                child.layout(
                    in: Rect(
                        x: childX,
                        y: y + 1,
                        w: childWidth,
                        h: min(measured.h, max(0, rowDistance - 1))
                    )
                )
                x += columnDistance
            }
            y += rowDistance
        }
    }

    /// 每个单元格单独画矩形边框；Canvas 会读取已有边框字形并合并连接，
    /// 将相邻的角自动转换为 ┬、┼、┴ 等表格连接字形。
    func draw(to canvas: Canvas, environment: EnvironmentValues) {
        guard !columnDistances.isEmpty, !rowDistances.isEmpty else { return }

        var y = frame.y
        for rowDistance in rowDistances {
            var x = frame.x
            for columnDistance in columnDistances {
                canvas.drawBox(
                    in: Rect(x: x, y: y, w: columnDistance + 1, h: rowDistance + 1),
                    style: style,
                    foreground: environment.foregroundColor ?? .white,
                    background: environment.backgroundColor
                )
                x += columnDistance
            }
            y += rowDistance
        }
    }

    /// 列的天然轨道距离 = 最宽内容 + 左右各一格 padding + 一格边界距离。
    /// `max(3, ...)` 使普通宽度下至少存在可见的单元格内部。
    private func naturalColumnDistances() -> [Int] {
        columns.indices.map { columnIndex in
            let contentWidth = cellRows.map {
                $0[columnIndex].measure(proposed: ProposedSize()).w
            }.max() ?? 0
            return max(3, contentWidth + 3)
        }
    }

    /// 行高必须在最终列宽下测量，因为 Text 可能换行。
    /// 返回值额外加 1，用于该行下方的共享水平边框。
    private func naturalRowDistances(columnDistances: [Int]) -> [Int] {
        cellRows.map { row in
            let contentHeight = row.indices.map { columnIndex in
                let distance = columnDistances[columnIndex]
                let padding = horizontalPadding(for: distance)
                return row[columnIndex].measure(
                    proposed: ProposedSize(
                        width: max(0, distance - 1 - padding * 2),
                        height: nil
                    )
                ).h
            }.max() ?? 1
            return max(2, contentHeight + 1)
        }
    }

    /// 轨道过窄时移除装饰性 padding，否则可用宽度可能变为零。
    private func horizontalPadding(for distance: Int) -> Int {
        distance >= 3 ? 1 : 0
    }

    /// 让各轨道尺寸之和等于可用空间。约束时每次收缩当前最大轨道，
    /// 避免某一长列挤压所有短列；扩展时轮询分配剩余 cell，保证总和精确匹配。
    /// 当可用空间连 `minimum * count` 都放不下时，允许轨道继续降到 0，
    /// 以维持“测量结果不超过 proposal”的布局契约。
    private func fit(
        _ natural: [Int],
        total: Int,
        minimum: Int,
        expands: Bool = false
    ) -> [Int] {
        guard !natural.isEmpty else { return [] }
        var result = natural
        var current = result.reduce(0, +)

        while current > total, let index = result.indices
            .filter({ result[$0] > (total >= minimum * result.count ? minimum : 0) })
            .max(by: { result[$0] < result[$1] }) {
            result[index] -= 1
            current -= 1
        }

        if expands, current < total {
            var remainder = total - current
            var index = 0
            while remainder > 0 {
                result[index % result.count] += 1
                index += 1
                remainder -= 1
            }
        }
        return result
    }
}
