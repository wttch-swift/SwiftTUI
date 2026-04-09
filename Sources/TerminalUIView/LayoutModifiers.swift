package struct _PaddingModifier: ViewModifier {
    package let top: Int
    package let right: Int
    package let bottom: Int
    package let left: Int

    package init(top: Int, right: Int, bottom: Int, left: Int) {
        self.top = max(0, top)
        self.right = max(0, right)
        self.bottom = max(0, bottom)
        self.left = max(0, left)
    }

    package func body(content: Content) -> some View {
        _PaddingLayoutView(
            content: content,
            top: top,
            right: right,
            bottom: bottom,
            left: left
        )
    }
}

package struct _FrameModifier: ViewModifier {
    package let width: Int?
    package let height: Int?
    package let alignment: AlignmentEdge

    package init(width: Int?, height: Int?, alignment: AlignmentEdge) {
        self.width = width
        self.height = height
        self.alignment = alignment
    }

    package func body(content: Content) -> some View {
        _FrameLayoutView(
            content: content,
            width: width,
            height: height,
            alignment: alignment
        )
    }
}

package struct _PaddingLayoutView<Content: View>: View, _NeverView {
    public typealias Body = Never

    package let content: Content
    package let top: Int
    package let right: Int
    package let bottom: Int
    package let left: Int
}

package struct _FrameLayoutView<Content: View>: View, _NeverView {
    public typealias Body = Never

    package let content: Content
    package let width: Int?
    package let height: Int?
    package let alignment: AlignmentEdge
}
