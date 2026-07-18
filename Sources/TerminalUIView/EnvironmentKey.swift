
// MARK: 定义
package protocol EnvironmentKey {

    associatedtype Value

    static var defaultValue: Value { get }
}


// MARK: Keys定义
struct ForegroundColorKey: EnvironmentKey {
    static let defaultValue: Color? = nil
}

struct BackgroundColorKey: EnvironmentKey {
    static let defaultValue: Color? = nil
}

/// 文本装饰使用独立 EnvironmentKey，使样式能向后代传播，也允许内层视图
/// 通过写入 `false` 明确覆盖外层装饰。
struct BoldTextKey: EnvironmentKey {
    static let defaultValue = false
}

struct ItalicTextKey: EnvironmentKey {
    static let defaultValue = false
}

struct UnderlineTextKey: EnvironmentKey {
    static let defaultValue = false
}

struct StrikethroughTextKey: EnvironmentKey {
    static let defaultValue = false
}

/// 所有交互控件共享的强调色。
///
/// 有边框的容器会在后代获得焦点时把边框切到该颜色；没有边框的控件可以用
/// 它绘制光标、滚动条、选中标记等自己的焦点反馈。
struct FocusBorderColorKey: EnvironmentKey {
    static let defaultValue = Color.brightCyan
}

/// 控制通用边框是否根据其后代的焦点状态自动切换颜色。
struct FocusEffectEnabledKey: EnvironmentKey {
    static let defaultValue = true
}


// MARK: - EnvironmentValues扩展
extension EnvironmentValues {
    package var foregroundColor: Color? {
        get { self[ForegroundColorKey.self] }
        set { self[ForegroundColorKey.self] = newValue }
    }

    package var backgroundColor: Color? {
        get { self[BackgroundColorKey.self] }
        set { self[BackgroundColorKey.self] = newValue }
    }

    package var _focusBorderColor: Color {
        get { self[FocusBorderColorKey.self] }
        set { self[FocusBorderColorKey.self] = newValue }
    }

    package var _isFocusEffectEnabled: Bool {
        get { self[FocusEffectEnabledKey.self] }
        set { self[FocusEffectEnabledKey.self] = newValue }
    }
}


// MARK: - View扩展
public extension View {
    func foregroundColor(_ color: Color) -> _EnvironmentWritingContent<Self> {
        self.environment(
            \.foregroundColor,
            color
        )
    }

    /// 为视图完整布局区域铺设背景色，并将同一颜色写入后代环境。
    ///
    /// 单纯写入环境只能影响实际绘制字符的节点，padding 等空白 cell 会继续
    /// 保持 Canvas 默认色。独立背景层会先填满 frame，再由内容覆盖其上。
    func backgroundColor(_ color: Color) -> some View {
        self.environment(\.backgroundColor, color)
            .background(_BackgroundColorFill(color: color))
    }

    /// 设置当前视图层级统一使用的强调色。
    ///
    /// 这个 API 语义更接近 SwiftUI 的 `accentColor`：它不是强制给所有控件画
    /// 边框，而是提供一个统一的交互强调色。有边框的容器会用它变色，没有边框
    /// 的控件仍由自身决定如何表现焦点。
    func accentColor(_ color: Color) -> some View {
        environment(\._focusBorderColor, color)
    }

    /// 设置当前视图层级统一使用的焦点边框强调色。
    ///
    /// 保留这个名字作为更直接的终端语义；实现上等价于 `accentColor(_:)`。
    func focusBorderColor(_ color: Color) -> some View {
        accentColor(color)
    }

    /// 禁用当前视图层级中边框的默认焦点变色效果。
    ///
    /// 控件仍会获得焦点并处理按键，只是不再由通用边框绘制焦点反馈。
    func focusEffectDisabled(_ disabled: Bool = true) -> some View {
        environment(\._isFocusEffectEnabled, !disabled)
    }
}

/// 不参与内容测量，只把父布局分配的矩形填充为指定终端背景色。
package struct _BackgroundColorFill: View, _NeverView {
    public typealias Body = Never

    package let color: Color
}
