/// 将子视图从左到右排列的水平容器。
public struct HStack<Content: View>: View, _NeverView {
    package let content: Content
    package let alignment: VerticalAlignment

    public init(alignment: VerticalAlignment = .top, @ViewBuilder _ content: () -> Content) {
        self.content = content()
        self.alignment = alignment
    }
}

/// 将子视图从上到下排列的垂直容器。
public struct VStack<Content: View>: View, _NeverView {
    package let content: Content
    package let alignment: HorizontalAlignment

    public init(alignment: HorizontalAlignment = .leading, @ViewBuilder _ content: () -> Content) {
        self.content = content()
        self.alignment = alignment
    }
}

/// A vertically scrolling collection that creates layout nodes only for rows
/// near the current viewport. Use it as the direct content of a vertical
/// `ScrollView` when the collection can grow large.
public struct LazyVStack<Data, ID, Content>: View, _NeverView
where Data: RandomAccessCollection, ID: Hashable, Content: View {
    package let data: Data
    package let id: KeyPath<Data.Element, ID>
    package let alignment: HorizontalAlignment
    package let spacing: Int
    package let estimatedRowHeight: Int
    package let content: (Data.Element) -> Content

    public init(
        _ data: Data,
        id: KeyPath<Data.Element, ID>,
        alignment: HorizontalAlignment = .leading,
        spacing: Int = 0,
        estimatedRowHeight: Int = 1,
        @ViewBuilder content: @escaping (Data.Element) -> Content
    ) {
        self.data = data
        self.id = id
        self.alignment = alignment
        self.spacing = max(0, spacing)
        self.estimatedRowHeight = max(1, estimatedRowHeight)
        self.content = content
    }
}

public extension LazyVStack where Data.Element: Identifiable, ID == Data.Element.ID {
    init(
        _ data: Data,
        alignment: HorizontalAlignment = .leading,
        spacing: Int = 0,
        estimatedRowHeight: Int = 1,
        @ViewBuilder content: @escaping (Data.Element) -> Content
    ) {
        self.init(
            data,
            id: \.id,
            alignment: alignment,
            spacing: spacing,
            estimatedRowHeight: estimatedRowHeight,
            content: content
        )
    }
}

public extension LazyVStack where Data == Range<Int>, ID == Int {
    init(
        _ data: Range<Int>,
        alignment: HorizontalAlignment = .leading,
        spacing: Int = 0,
        estimatedRowHeight: Int = 1,
        @ViewBuilder content: @escaping (Int) -> Content
    ) {
        self.init(
            data,
            id: \.self,
            alignment: alignment,
            spacing: spacing,
            estimatedRowHeight: estimatedRowHeight,
            content: content
        )
    }
}

/// 在同一矩形区域内按声明顺序叠放子视图。
public struct ZStack<Content: View>: View, _NeverView {
    package let content: Content
    package let alignment: AlignmentEdge

    public init(alignment: AlignmentEdge = .topLeading, @ViewBuilder _ content: () -> Content) {
        self.content = content()
        self.alignment = alignment
    }
}
