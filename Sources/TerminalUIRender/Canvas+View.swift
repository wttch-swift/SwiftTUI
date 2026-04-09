import TerminalUICore

/// View 到 Core Canvas 的桥接属于声明式 UI 层，避免 Core 反向依赖 View。
package extension TerminalUICore.Canvas {
    func draw(_ view: any View, in rect: Rect) {
        Render.render(view._makeLayoutNode(), in: rect, to: self)
    }
}
