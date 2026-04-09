public extension View {
    /// 在视图现有布局区域内绘制边框，并把子视图向内压缩一格。
    /// - Parameters:
    ///   - color: 边框前景色。
    ///   - style: 边角和线段使用的字符集。
    func bordered(_ color: Color = .white, style: BorderStyle = .single) -> some View {
        modifier(_BorderModifier(color: color, style: style))
    }

    func background<Background: View>(
        _ background: Background,
        alignment: AlignmentEdge = .center
    ) -> some View {
        _Background(content: self, background: background, alignment: alignment)
    }

    func padding(_ length: Int = 1) -> some View {
        modifier(_PaddingModifier(top: length, right: length, bottom: length, left: length))
    }

    func padding(horizontal: Int = 0, vertical: Int = 0) -> some View {
        modifier(_PaddingModifier(top: vertical, right: horizontal, bottom: vertical, left: horizontal))
    }

    func frame(width: Int? = nil, height: Int? = nil, alignment: AlignmentEdge = .topLeading) -> some View {
        modifier(_FrameModifier(width: width, height: height, alignment: alignment))
    }
}

package struct _Background<Content: View, Background: View>: View, _NeverView {
    package typealias Body = Never

    public var body: Never {
        fatalError("Never 类型的 body 永远不应该被调用")
    }

    package let content: Content
    package let background: Background
    package let alignment: AlignmentEdge
}
