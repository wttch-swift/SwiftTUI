@_exported import TerminalUIView
import TerminalUICore

// Canvas 只供本包的 View、TerminalApp、demo 和测试使用，不进入公开 API。
package typealias Canvas = TerminalUICore.Canvas

func alignedOrigin(parent: Rect, child: Size, alignment: AlignmentEdge) -> Offset {
    let x: Int
    let y: Int

    switch alignment {
    case .topLeading, .leading, .bottomLeading:
        x = parent.x
    case .top, .center, .bottom:
        x = parent.x + max(0, parent.w - child.w) / 2
    case .topTrailing, .trailing, .bottomTrailing:
        x = parent.x + max(0, parent.w - child.w)
    }

    switch alignment {
    case .topLeading, .top, .topTrailing:
        y = parent.y
    case .leading, .center, .trailing:
        y = parent.y + max(0, parent.h - child.h) / 2
    case .bottomLeading, .bottom, .bottomTrailing:
        y = parent.y + max(0, parent.h - child.h)
    }

    return Offset(x: x, y: y)
}
