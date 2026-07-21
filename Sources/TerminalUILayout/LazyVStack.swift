import TerminalUIFoundation
import TerminalUIView

/// Private handshake between ScrollView and lazy vertical content. A regular
/// layout node receives the complete, offset content rectangle; lazy content
/// additionally needs the viewport so it can decide which rows to materialize.
package protocol _VirtualizedVerticalContent: _ContainerLayoutable, AnyObject {
    func layout(viewport: Rect, offsetY: Int) -> Size
    func restoreVirtualState(from previous: any _VirtualizedVerticalContent)
}

extension LazyVStack: _LayoutNodeProducing {
    package func _makeLayoutNode() -> any _Layoutable {
        _LazyVStackLayoutNode(
            elements: Array(data),
            id: id,
            alignment: alignment,
            spacing: spacing,
            estimatedRowHeight: estimatedRowHeight,
            content: content
        )
    }
}

private final class _LazyVStackLayoutNode<Element, ID: Hashable, Row: View>:
    _LayoutContainerStorage, _VirtualizedVerticalContent {
    private let elements: [Element]
    private let id: KeyPath<Element, ID>
    private let alignment: HorizontalAlignment
    private let spacing: Int
    private let estimatedRowHeight: Int
    private let content: (Element) -> Row
    private var cachedWidth: Int?
    private var rowHeights: [ID: Int] = [:]

    init(
        elements: [Element],
        id: KeyPath<Element, ID>,
        alignment: HorizontalAlignment,
        spacing: Int,
        estimatedRowHeight: Int,
        content: @escaping (Element) -> Row
    ) {
        self.elements = elements
        self.id = id
        self.alignment = alignment
        self.spacing = spacing
        self.estimatedRowHeight = estimatedRowHeight
        self.content = content
        super.init(children: [])
    }

    package func measure(proposed: ProposedSize) -> Size {
        let width = max(0, proposed.width ?? 0)
        return Size(w: width, h: totalHeight)
    }

    package func layout(in rect: Rect) {
        // Outside a ScrollView there is no separate viewport. Materialize rows
        // intersecting the assigned rectangle, which preserves useful fallback
        // behavior without expanding an unbounded collection.
        _ = layout(viewport: rect, offsetY: 0)
    }

    package func layout(viewport: Rect, offsetY: Int) -> Size {
        if cachedWidth != viewport.w {
            cachedWidth = viewport.w
            rowHeights.removeAll(keepingCapacity: true)
        }
        guard !elements.isEmpty, viewport.w > 0, viewport.h > 0 else {
            children = []
            return Size(w: max(0, viewport.w), h: totalHeight)
        }

        let visibleStart = max(0, offsetY)
        let visibleEnd = visibleStart + viewport.h
        let overscan = max(estimatedRowHeight * 2, viewport.h / 2)
        let materialStart = max(0, visibleStart - overscan)
        let materialEnd = visibleEnd + overscan

        var y = 0
        var materialized: [any _Layoutable] = []
        for element in elements {
            let key = element[keyPath: id]
            var height = rowHeights[key] ?? estimatedRowHeight
            let rowEnd = y + height
            if rowEnd >= materialStart, y <= materialEnd {
                let node = content(element)._makeLayoutNode()
                let measured = node.measure(
                    proposed: ProposedSize(width: viewport.w, height: nil)
                )
                height = max(0, measured.h)
                rowHeights[key] = height
                let width = min(viewport.w, max(0, measured.w))
                let x = switch alignment {
                case .leading: viewport.x
                case .center: viewport.x + max(0, viewport.w - width) / 2
                case .trailing: viewport.maxX - width
                }
                node.layout(
                    in: Rect(
                        x: x,
                        y: viewport.y + y - offsetY,
                        w: width,
                        h: height
                    )
                )
                materialized.append(node)
            }
            y += height + spacing
        }
        children = materialized
        return Size(w: viewport.w, h: totalHeight)
    }

    package func restoreVirtualState(from previous: any _VirtualizedVerticalContent) {
        guard let previous = previous as? _LazyVStackLayoutNode<Element, ID, Row> else { return }
        cachedWidth = previous.cachedWidth
        rowHeights = previous.rowHeights
    }

    private var totalHeight: Int {
        guard !elements.isEmpty else { return 0 }
        let rows = elements.reduce(0) { partial, element in
            partial + (rowHeights[element[keyPath: id]] ?? estimatedRowHeight)
        }
        return rows + spacing * (elements.count - 1)
    }
}
