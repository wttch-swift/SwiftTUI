/// 在终端画布上显示纯文本的基础视图。
public struct Text: View, _NeverView {

    /// 文本内容。
    public let text: String

    public init(_ text: String) { self.text = text }
}


public extension View {
    func bold(_ isActive: Bool = true) -> some View {
        environment(\._isBold, isActive)
    }

    func italic(_ isActive: Bool = true) -> some View {
        environment(\._isItalic, isActive)
    }

    func underline(_ isActive: Bool = true) -> some View {
        environment(\._isUnderline, isActive)
    }

    func strikethrough(_ isActive: Bool = true) -> some View {
        environment(\._isStrikethrough, isActive)
    }

    func lineLimit(_ limit: Int, reservesSpace: Bool = false) -> some View {
        modifier(_LineLimitModifier(limit: limit, reservesSpace: reservesSpace))
    }
}

package struct _LineLimitModifier: ViewModifier {
    package let limit: Int
    package let reservesSpace: Bool

    package func body(content: Content) -> some View {
        if !reservesSpace {
            return content.environment(\.lineLimit, limit).eraseToAnyView()
        }
        return VStack {
            content.environment(\.lineLimit, limit)
            Spacer()
        }
        .frame(height: limit)
        .eraseToAnyView()
    }
}
