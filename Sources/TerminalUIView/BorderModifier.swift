package struct _BorderModifier: ViewModifier {
    package let color: Color
    package let style: BorderStyle

    package func body(content: Content) -> some View {
        _BorderContent(content: content, color: color, style: style)
    }
}

package struct _BorderContent<Content: View>: View, _NeverView {
    public typealias Body = Never

    package let content: Content
    package let color: Color
    package let style: BorderStyle
}
