// struct _EnvironmentValues {
//     public var foregroundColor: Color?
//     public var backgroundColor: Color?

//     public init(foregroundColor: Color? = nil, backgroundColor: Color? = nil) {
//         self.foregroundColor = foregroundColor
//         self.backgroundColor = backgroundColor
//     }

//     func applying(foregroundColor: Color? = nil, backgroundColor: Color? = nil) -> _EnvironmentValues {
//         _EnvironmentValues(
//             foregroundColor: foregroundColor ?? self.foregroundColor,
//             backgroundColor: backgroundColor ?? self.backgroundColor
//         )
//     }
// }

/// 渲染上下文。当前只承载 Canvas 和基础环境值，后续可继续加入主题、焦点、裁剪区等。
struct _RenderContext {
    let canvas: Canvas
    let rect: Rect
    let environment: EnvironmentValues

    init(canvas: Canvas, rect: Rect = .zero, environment: EnvironmentValues = EnvironmentValues()) {
        self.canvas = canvas
        self.rect = rect
        self.environment = environment
    }
}
