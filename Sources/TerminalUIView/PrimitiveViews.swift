/// 在终端画布上显示纯文本的基础视图。
public struct Text: View, _NeverView {
    public let text: String

    public init(_ text: String) { self.text = text }
}

/// 只参与布局、不直接产生可见内容的弹性空白。
public struct Spacer: View, _NeverView {
    public let width: Int?
    public let height: Int?

    public init(width: Int? = nil, height: Int? = nil) {
        self.width = width
        self.height = height
    }
}

/// 使用终端字符绘制的单行进度条声明。
public struct ProgressBar: View, _NeverView {
    package let value: Double
    package let width: Int
    package var fillColor: Color = .green
    package var track: Color = .black

    public init(value: Double, width: Int = 24, showsValue: Bool = true) {
        self.value = min(1, max(0, value))
        self.width = max(1, width)
    }

    public func tint(_ color: Color) -> ProgressBar {
        var copy = self
        copy.fillColor = color
        return copy
    }

    public func trackColor(_ color: Color) -> ProgressBar {
        var copy = self
        copy.track = color
        return copy
    }
}

/// 绑定布尔值的开关声明。
public final class Toggle: View, _NeverView {
    package let title: String
    package let isOn: Binding<Bool>

    public init(_ title: String, isOn: Binding<Bool>) {
        self.title = title
        self.isOn = isOn
    }
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
