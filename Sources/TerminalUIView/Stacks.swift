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

/// 在同一矩形区域内按声明顺序叠放子视图。
public struct ZStack<Content: View>: View, _NeverView {
    package let content: Content
    package let alignment: AlignmentEdge

    public init(alignment: AlignmentEdge = .topLeading, @ViewBuilder _ content: () -> Content) {
        self.content = content()
        self.alignment = alignment
    }
}
