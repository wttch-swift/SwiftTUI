/// A container that switches between child views using a tab bar.
///
/// The public declaration mirrors SwiftUI's `TabView`: use `selection` together
/// with `.tag(_:)` for controlled selection, and `.tabItem {}` to supply each
/// tab's label. In a terminal, the left and right arrow keys change tabs.
extension TabView: _LayoutNodeProducing {
    package func _makeLayoutNode() -> any _Layoutable {
        let pages = content._makeLayoutNodes().enumerated().map { index, node in
            let metadata = _tabMetadata(in: node)
            return _TabPage(
                content: node,
                label: metadata.label ?? Text("\(index + 1)")._makeLayoutNode(),
                tag: metadata.tag
            )
        }
        let selectedTag = selection.map { AnyHashable($0.wrappedValue) }
        let selectedIndex = selectedTag.flatMap { tag in pages.firstIndex { $0.tag == tag } } ?? 0
        let tabNode = _TabViewLayoutNode(
            pages: pages,
            selectedIndex: selectedIndex,
            usesExternalSelection: selection != nil,
            select: { tag in
                guard let value = tag?.base as? SelectionValue else { return }
                selection?.wrappedValue = value
            }
        )

        return tabNode
    }
}

extension _TabMetadataContent: _LayoutNodeProducing {
    package func _makeLayoutNode() -> any _Layoutable {
        _TabMetadataNode(
            child: content._makeLayoutNode(),
            tag: tag,
            label: label?.content()._makeLayoutNode()
        )
    }
}

private final class _TabMetadataNode: _LayoutContainerStorage, _PassthroughUnaryLayoutable {
    let tag: AnyHashable?
    let label: (any _Layoutable)?

    init(child: any _Layoutable, tag: AnyHashable?, label: (any _Layoutable)?) {
        self.tag = tag
        self.label = label
        super.init(children: [child])
    }
}

private struct _TabMetadata {
    var tag: AnyHashable?
    var label: (any _Layoutable)?
}

/// Metadata modifiers can be separated by ordinary unary modifiers, so inspect
/// the complete wrapper chain instead of requiring `.tag` and `.tabItem` to be
/// written in a particular order.
private func _tabMetadata(in root: any _Layoutable) -> _TabMetadata {
    var metadata = _TabMetadata()
    var node: any _Layoutable = root
    while true {
        if let value = node as? _TabMetadataNode {
            if metadata.tag == nil { metadata.tag = value.tag }
            if metadata.label == nil { metadata.label = value.label }
        }
        guard let unary: any _UnaryLayoutable = node as? _UnaryLayoutable else { break }
        node = unary.child
    }
    return metadata
}

private struct _TabPage {
    let content: any _Layoutable
    let label: any _Layoutable
    let tag: AnyHashable?
}

/// Marker used by `TerminalApp` to transfer an uncontrolled tab selection to
/// the freshly rebuilt layout tree on the next frame.
package protocol _TabSelectionNode: AnyObject {
    var selectedIndex: Int { get }
    func restoreSelection(from index: Int)
}

/// Tab navigation is handled by `TerminalApp` before focused controls so a
/// TextField inside the selected page cannot consume the left/right shortcuts.
package protocol _TabNavigationNode: AnyObject {
    func handleTabNavigation(_ event: KeyPress) -> KeyPress.Result
}

private final class _TabViewLayoutNode: _LayoutContainerStorage, _ContainerLayoutable, _FlexibleLayoutNode,
    _TabSelectionNode, _TabNavigationNode {
    private let pages: [_TabPage]
    private var tabBar: _TabBarLayoutNode
    private let usesExternalSelection: Bool
    private let select: (AnyHashable?) -> Void
    private(set) var selectedIndex: Int
    var expandsHorizontally: Bool { true }
    var expandsVertically: Bool { true }

    init(
        pages: [_TabPage],
        selectedIndex: Int,
        usesExternalSelection: Bool,
        select: @escaping (AnyHashable?) -> Void
    ) {
        self.pages = pages
        self.selectedIndex = pages.indices.contains(selectedIndex) ? selectedIndex : 0
        self.usesExternalSelection = usesExternalSelection
        self.select = select
        self.tabBar = _TabBarLayoutNode(labels: pages.map(\.label), selectedIndex: self.selectedIndex)
        let selectedContent = pages.indices.contains(self.selectedIndex) ? [pages[self.selectedIndex].content] : []
        super.init(children: [tabBar] + selectedContent)
    }

    package func measure(proposed: ProposedSize) -> Size {
        guard !pages.isEmpty else { return .zero }
        let barSize = tabBar.measure(proposed: ProposedSize(width: proposed.width, height: proposed.height))
        let remainingHeight = proposed.height.map { max(0, $0 - barSize.h) }
        let contentSize = pages[selectedIndex].content.measure(
            proposed: ProposedSize(width: proposed.width, height: remainingHeight)
        )
        let natural = Size(w: max(barSize.w, contentSize.w), h: barSize.h + contentSize.h)
        return Size(
            w: proposed.width ?? natural.w,
            h: proposed.height ?? natural.h
        )
    }

    package func layout(in rect: Rect) {
        guard !pages.isEmpty else { return }
        let barHeight = min(rect.h, tabBar.measure(proposed: ProposedSize(width: rect.w, height: rect.h)).h)
        tabBar.layout(in: Rect(x: rect.x, y: rect.y, w: rect.w, h: barHeight))
        pages[selectedIndex].content.layout(
            in: Rect(x: rect.x, y: rect.y + barHeight, w: rect.w, h: max(0, rect.h - barHeight))
        )
    }

    func moveSelection(by offset: Int) {
        guard !pages.isEmpty else { return }
        updateSelection(to: (selectedIndex + offset + pages.count) % pages.count)
        select(pages[selectedIndex].tag)
    }

    func handleTabNavigation(_ event: KeyPress) -> KeyPress.Result {
        switch event.key {
        case .leftArrow:
            moveSelection(by: -1)
        case .rightArrow:
            moveSelection(by: 1)
        default:
            return .ignored
        }
        return pages.isEmpty ? .ignored : .handled
    }

    func restoreSelection(from index: Int) {
        guard !usesExternalSelection, pages.indices.contains(index) else { return }
        updateSelection(to: index)
    }

    private func updateSelection(to index: Int) {
        guard pages.indices.contains(index) else { return }
        selectedIndex = index
        tabBar = _TabBarLayoutNode(labels: pages.map(\.label), selectedIndex: index)
        children = [tabBar, pages[index].content]
    }
}

private final class _TabBarLayoutNode: _LayoutContainerStorage, _ContainerLayoutable, _RenderableLayoutNode {
    private let labelCount: Int
    private(set) var frame: Rect = .zero

    init(labels: [any _Layoutable], selectedIndex: Int) {
        labelCount = labels.count
        var children: [any _Layoutable] = []
        for (index, label) in labels.enumerated() {
            if index > 0 { children.append(Text(" ")._makeLayoutNode()) }
            if index == selectedIndex {
                children.append(Self.selected(Text("[")._makeLayoutNode()))
                children.append(Self.selected(label))
                children.append(Self.selected(Text("]")._makeLayoutNode()))
            } else {
                children.append(Text(" ")._makeLayoutNode())
                children.append(label)
                children.append(Text(" ")._makeLayoutNode())
            }
        }
        super.init(children: children)
    }

    /// A selected tab remains recognizable through brackets without color, and
    /// becomes a contiguous high-contrast badge in color-capable terminals.
    private static func selected(_ node: any _Layoutable) -> any _Layoutable {
        _makeEnvironmentLayoutNode(child: node) { environment in
            environment.foregroundColor = .black
            environment.backgroundColor = .brightCyan
            environment._isBold = true
        }
    }

    package func measure(proposed: ProposedSize) -> Size {
        guard labelCount > 0 else { return .zero }
        let sizes = children.map { $0.measure(proposed: ProposedSize(width: nil, height: proposed.height)) }
        return Size(
            w: min(sizes.reduce(0) { $0 + $1.w }, proposed.width ?? Int.max),
            h: min(sizes.map(\.h).max() ?? 0, proposed.height ?? Int.max)
        )
    }

    package func layout(in rect: Rect) {
        frame = rect
        var x = rect.x
        for child in children {
            let size = child.measure(proposed: ProposedSize(width: nil, height: rect.h))
            let width = min(size.w, max(0, rect.maxX - x))
            child.layout(in: Rect(x: x, y: rect.y, w: width, h: min(size.h, rect.h)))
            x += width
        }
    }

    func draw(to canvas: Canvas, environment: EnvironmentValues) {
        guard frame.w > 0, frame.h > 0 else { return }
        let row = String(repeating: " ", count: frame.w)
        canvas.drawText(
            x: frame.x,
            y: frame.y,
            text: row,
            foreground: environment.foregroundColor ?? .white,
            background: environment.backgroundColor ?? .rgb(17, 25, 42)
        )
    }
}
