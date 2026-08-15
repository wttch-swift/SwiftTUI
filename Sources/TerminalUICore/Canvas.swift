import TerminalUIFoundation

/// 固定尺寸的离屏终端画布。
///
/// 画布以二维 `_Cell` 网格保存字符和样式。视图绘制期间只修改网格，最终由
/// `output(colorSupport:)` 一次性编码为带 ANSI SGR 序列的字符串。
package final class Canvas {
    /// 画布宽度，单位为终端 cell。
    package let width: Int
    /// 画布高度，单位为终端行。
    package let height: Int
    /// 内部单元格存储；宽字符的后续位置使用 continuation cell 占位。
    package var grid: [[_Cell]]
    /// Render 遍历中当前生效的嵌套裁剪区域。
    private var clipStack: [Rect] = []

    /// 创建空画布。负尺寸会钳制为零。
    package init(width: Int, height: Int) {
        self.width = max(0, width)
        self.height = max(0, height)
        grid = Array(repeating: Array(repeating: .Blank, count: max(0, width)), count: max(0, height))
    }

    /// 清除所有已绘制内容，同时保留画布尺寸。
    package func clean() {
        clipStack.removeAll(keepingCapacity: true)
        for y in grid.indices {
            for x in grid[y].indices {
                grid[y][x] = .Blank
            }
        }
    }

    /// 把网格逐行编码为终端可打印字符串。
    /// - Parameter colorSupport: 目标终端支持的颜色深度。
    /// - Returns: 行之间由换行符连接的完整画面。
    package func output(colorSupport: TerminalColorSupport = .current) -> String {
        grid.map { encode(row: $0, colorSupport: colorSupport) }
            .joined(separator: "\n")
    }

    /// 生成适合全屏重绘的绝对定位输出。
    ///
    /// 每一行前使用 CUP (`ESC[row;1H`) 把光标直接移动到目标位置，不输出
    /// 换行符。这样绘制最后一行后不会触发终端滚屏，状态栏也不会在下一帧
    /// 被卷到画面顶部。
    package func positionedOutput(colorSupport: TerminalColorSupport = .current) -> String {
        grid.enumerated().map { index, row in
            "\u{001B}[\(index + 1);1H" + encode(row: row, colorSupport: colorSupport)
        }.joined()
    }

    /// 只编码与上一帧不同的行，减少交互式界面的终端写入量。
    ///
    /// 行内仍按完整宽度输出，因此不需要处理宽字符右半格和旧内容清除等复杂
    /// 情况；尺寸变化或没有上一帧时自动退回完整画面。
    package func positionedOutput(
        comparedTo previous: Canvas?,
        colorSupport: TerminalColorSupport = .current
    ) -> String {
        guard let previous,
              previous.width == width,
              previous.height == height else {
            return positionedOutput(colorSupport: colorSupport)
        }

        return grid.enumerated().compactMap { index, row in
            guard row != previous.grid[index] else { return nil }
            return "\u{001B}[\(index + 1);1H" + encode(row: row, colorSupport: colorSupport)
        }.joined()
    }

    /// 复制指定矩形内的 cell 快照。超出画布的部分会被裁掉。
    ///
    /// RenderCache 在可复用节点重画后调用它，把节点绘制结果保存下来。这里复制
    /// 的是最终 cell，而不是 View 或 LayoutNode，因此下一帧命中时可以完全跳过
    /// 节点自己的 draw 逻辑。
    package func snapshot(in rect: Rect) -> [[_Cell]] {
        let canvasBounds = Rect(x: 0, y: 0, w: width, h: height)
        let target = rect.intersection(canvasBounds)
        guard target.w > 0, target.h > 0 else { return [] }

        return (target.y..<target.maxY).map { y in
            Array(grid[y][target.x..<target.maxX])
        }
    }

    /// 把 cell 快照贴回指定矩形左上角。快照尺寸和目标矩形不一致时取交集。
    ///
    /// 这是缓存命中后的快速路径。按行 `replaceSubrange` 写回，比逐 cell 赋值少
    /// 很多 Swift 循环开销；benchmark 里的 `paste reused cells` 就是在量这里。
    package func paste(_ cells: [[_Cell]], in rect: Rect) {
        let canvasBounds = Rect(x: 0, y: 0, w: width, h: height)
        let target = rect.intersection(canvasBounds)
        guard target.w > 0, target.h > 0 else { return }

        for (dy, y) in (target.y..<target.maxY).enumerated() where cells.indices.contains(dy) {
            let count = min(target.w, cells[dy].count)
            guard count > 0 else { continue }
            grid[y].replaceSubrange(target.x..<(target.x + count), with: cells[dy][0..<count])
        }
    }

    /// 把一行中连续且样式相同的 cell 合并后再编码 ANSI 序列。
    ///
    /// 旧实现为每个字符分别输出 `SGR + 字符 + ESC[0m`，一帧会产生大量
    /// 控制序列。在频繁重绘和终端边界附近，序列一旦被拆开就可能把 `[0m`
    /// 当作普通文字显示。按样式分段后，每段只需要一对控制序列。
    private func encode(row: [_Cell], colorSupport: TerminalColorSupport) -> String {
        var result = ""
        var run = ""
        var runStyle: _CellStyle?

        func appendRun() {
            guard let style = runStyle, !run.isEmpty else { return }
            result += run.colored(
                fg: style.inverse ? style.backgroundColor : style.foregroundColor,
                bg: style.inverse ? style.foregroundColor : style.backgroundColor,
                support: colorSupport,
                bold: style.bold,
                italic: style.italic,
                underline: style.underline,
                strikethrough: style.strikethrough
            )
        }

        for cell in row where !cell.isSpace {
            if runStyle != cell.style {
                appendRun()
                run = ""
                runStyle = cell.style
            }
            run.append(cell.char)
        }
        appendRun()
        return result
    }

    /// 将当前画面输出到标准输出。
    ///
    /// - Parameter terminatingLine: 是否在画面末尾追加换行。普通一次性输出默认
    ///   追加换行；全屏应用应传入 `false`，否则画面占满终端高度时，最后一个
    ///   换行会触发滚屏，使整个界面看起来向上偏移一行。
    package func flush(terminatingLine: Bool = true) {
        print(output(), terminator: terminatingLine ? "\n" : "")
    }

    /// Compatibility entry used by the TUIDemo scene package.
    package func render() { flush() }

    package func withClip<Result>(_ rect: Rect, _ body: () throws -> Result) rethrows -> Result {
        let canvasBounds = Rect(x: 0, y: 0, w: width, h: height)
        let inherited = clipStack.last ?? canvasBounds
        // 每层裁剪都与父裁剪及画布边界求交，子节点无法画到祖先视口之外。
        clipStack.append(inherited.intersection(rect).intersection(canvasBounds))
        // 即使绘制闭包抛错，也必须恢复上一层裁剪上下文。
        defer { clipStack.removeLast() }
        return try body()
    }

    /// Returns whether a renderable rectangle can affect any currently visible cell.
    /// Render uses this before invoking a leaf's draw path, which is especially
    /// important for long ScrollView contents: off-screen text and borders should
    /// not pay Unicode layout, fingerprint, snapshot, or paste costs.
    package func intersectsCurrentClip(_ rect: Rect) -> Bool {
        let canvasBounds = Rect(x: 0, y: 0, w: width, h: height)
        let clip = clipStack.last ?? canvasBounds
        let visible = rect.intersection(clip).intersection(canvasBounds)
        return visible.w > 0 && visible.h > 0
    }

    /// 使用统一样式直接填充矩形区域。
    ///
    /// 背景铺底不需要文本分段、Unicode 宽度计算或逐字形清理，直接写 cell
    /// 可避免整屏背景在每次按键重绘时产生大量重复工作。
    package func fill(
        _ rect: Rect,
        foreground: Color = .white,
        background: Color
    ) {
        let canvasBounds = Rect(x: 0, y: 0, w: width, h: height)
        let clip = clipStack.last ?? canvasBounds
        let target = rect.intersection(clip).intersection(canvasBounds)
        guard target.w > 0, target.h > 0 else { return }

        let cell = _Cell(
            char: " ",
            style: _CellStyle(
                foregroundColor: foreground,
                backgroundColor: background
            )
        )
        for y in target.y..<target.maxY {
            // `fill` is used by sheets and toasts to cover content already on
            // the canvas. If either horizontal edge cuts through a wide glyph,
            // clear the complete old glyph first. In particular, covering its
            // continuation cell must also blank the base cell immediately to
            // the left of the overlay.
            clearGlyph(atX: target.x, y: y)
            if target.w > 1 {
                clearGlyph(atX: target.maxX - 1, y: y)
            }
            for x in target.x..<target.maxX {
                grid[y][x] = cell
            }
        }
    }

    /// 写入一个字符及其样式，并维护宽字符占用的后续 cell。
    ///
    /// 传入 `nil` 不表示可见空格，而表示宽字形的延续位置，因此输出时会跳过。
    fileprivate func setCharacter(
        x: Int,
        y: Int,
        char: Character?,
        foreground: Color = .white,
        background: Color? = nil,
        bold: Bool = false,
        italic: Bool = false,
        underline: Bool = false,
        strikethrough: Bool = false
    ) {
        guard grid.indices.contains(y), grid[y].indices.contains(x) else { return }
        guard let char else {
            grid[y][x] = .Space
            return
        }

        // 覆盖任意一个宽字符 cell 前，先清除完整旧字形，避免留下半个字符。
        let cellWidth = max(1, Segment.cellLength(of: String(char)))
        if let clip = clipStack.last {
            // 要求整个字形落入裁剪区，宽字符不能只显示左半边。
            guard y >= clip.y, y < clip.maxY, x >= clip.x, x + cellWidth <= clip.maxX else {
                return
            }
        }
        for offset in 0..<cellWidth where grid[y].indices.contains(x + offset) {
            clearGlyph(atX: x + offset, y: y)
        }

        grid[y][x] = _Cell(
            char: char,
            style: _CellStyle(
                foregroundColor: foreground,
                backgroundColor: background ?? .black,
                italic: italic,
                bold: bold,
                underline: underline,
                strikethrough: strikethrough
            )
        )
        if cellWidth > 1 {
            for offset in 1..<cellWidth where grid[y].indices.contains(x + offset) {
                grid[y][x + offset] = .Space
            }
        }
    }

    /// 清除与指定 cell 相交的完整字形。
    ///
    /// 当 ZStack 的后层内容覆盖宽字符的第二格时，需要向左找到真实字符起点，
    /// 否则输出中会残留无法配对的 continuation cell。
    private func clearGlyph(atX x: Int, y: Int) {
        guard grid.indices.contains(y), grid[y].indices.contains(x) else { return }

        if grid[y][x].isSpace {
            var baseX = x - 1
            while grid[y].indices.contains(baseX) {
                let candidate = grid[y][baseX]
                if !candidate.isSpace {
                    let width = max(1, Segment.cellLength(of: String(candidate.char)))
                    if baseX + width > x {
                        for offset in 0..<width where grid[y].indices.contains(baseX + offset) {
                            grid[y][baseX + offset] = .Blank
                        }
                        return
                    }
                    break
                }
                baseX -= 1
            }
        }

        let width = max(1, Segment.cellLength(of: String(grid[y][x].char)))
        for offset in 0..<width where grid[y].indices.contains(x + offset) {
            grid[y][x + offset] = .Blank
        }
    }

    /// 在一行中绘制文本，并按照每个字素簇的终端宽度移动光标。
    ///
    /// 控制片段和零宽片段不会直接写入画布；超出边界的字符由
    /// `setCharacter` 安全忽略。
    package func drawText(
        x: Int,
        y: Int,
        text: String,
        foreground: Color,
        background: Color? = nil,
        bold: Bool = false,
        italic: Bool = false,
        underline: Bool = false,
        strikethrough: Bool = false
    ) {
        // cursor 使用终端 cell 坐标推进，而不是 Character 数量。
        var cursor = x
        for segment in Segment.segment(text) where segment.kind == .text && segment.cellLength > 0 {
            guard let char = segment.text.first else { continue }
            // 终端不能安全显示被画布右边界切掉一半的宽字符。
            if cursor >= 0, cursor + segment.cellLength <= width {
                setCharacter(
                    x: cursor,
                    y: y,
                    char: char,
                    foreground: foreground,
                    background: background,
                    bold: bold,
                    italic: italic,
                    underline: underline,
                    strikethrough: strikethrough
                )
            }
            cursor += segment.cellLength
        }
    }

    /// 使用选定字符集沿矩形边缘绘制边框。
    package func drawBox(in rect: Rect, style: BorderStyle, foreground: Color, background: Color?) {
        let x = rect.x, y = rect.y, w = rect.w, h = rect.h
        guard w > 1, h > 1 else { return }
        for dx in 1..<(w - 1) {
            setBorder(x: x + dx, y: y, connections: [.left, .right], style: style, foreground: foreground, background: background)
            setBorder(x: x + dx, y: y + h - 1, connections: [.left, .right], style: style, foreground: foreground, background: background)
        }
        for dy in 1..<(h - 1) {
            setBorder(x: x, y: y + dy, connections: [.up, .down], style: style, foreground: foreground, background: background)
            setBorder(x: x + w - 1, y: y + dy, connections: [.up, .down], style: style, foreground: foreground, background: background)
        }
        setBorder(x: x, y: y, connections: [.right, .down], style: style, foreground: foreground, background: background)
        setBorder(x: x + w - 1, y: y, connections: [.left, .down], style: style, foreground: foreground, background: background)
        setBorder(x: x, y: y + h - 1, connections: [.right, .up], style: style, foreground: foreground, background: background)
        setBorder(x: x + w - 1, y: y + h - 1, connections: [.left, .up], style: style, foreground: foreground, background: background)
    }

    private func setBorder(
        x: Int,
        y: Int,
        connections: _BorderConnections,
        style: BorderStyle,
        foreground: Color,
        background: Color?
    ) {
        guard grid.indices.contains(y), grid[y].indices.contains(x) else { return }
        if let clip = clipStack.last {
            guard x >= clip.x, x < clip.maxX, y >= clip.y, y < clip.maxY else { return }
        }

        // 边框连接信息直接由当前字形恢复，无需为 Canvas 维护第二份二维网格。
        let existing = _BorderCell(glyph: grid[y][x].char)
        let cell = existing?.merging(connections: connections, style: style)
            ?? _BorderCell(connections: connections, style: style)

        clearGlyph(atX: x, y: y)
        grid[y][x] = _Cell(
            char: cell.glyph,
            style: _CellStyle(
                foregroundColor: foreground,
                backgroundColor: background ?? .black
            )
        )
    }
}

/// 复用两张离屏画布轮流绘制和展示。
///
/// `drawing` 接收当前帧绘制，`presented` 保存上一帧已经输出到终端的内容。
/// 每次生成输出后交换两者，下一帧直接清理并复用旧的 presented 画布，避免
/// 交互循环为每一帧重新分配完整 cell 网格。
///
/// 这个类只负责“画布生命周期”和“按行 diff 输出”，不关心 View 是否变化。
/// View 级别的复用由 RenderCache 决定；双缓冲只保证每帧都有一张干净的 drawing
/// buffer，并能用上一帧 presented buffer 生成更短的终端输出。
package final class CanvasDoubleBuffer {
    private var presented: Canvas
    private var drawing: Canvas
    private var hasPresented = false

    package init(width: Int, height: Int) {
        presented = Canvas(width: width, height: height)
        drawing = Canvas(width: width, height: height)
    }

    /// 清空双缓冲状态。下一次输出会退回全量定位绘制。
    package func reset() {
        presented.clean()
        drawing.clean()
        hasPresented = false
    }

    /// 在 drawing buffer 上绘制一帧，并返回相对于上一帧的定位输出。
    ///
    /// 首帧没有 `presented` 可比对，所以输出完整画面；从第二帧开始只输出发生
    /// 变化的行。生成输出后交换两张画布，旧 drawing 就成为下一帧的 presented。
    package func renderOutput(
        colorSupport: TerminalColorSupport = .current,
        draw: (Canvas) -> Void
    ) -> String {
        drawing.clean()
        draw(drawing)
        let output = drawing.positionedOutput(
            comparedTo: hasPresented ? presented : nil,
            colorSupport: colorSupport
        )
        swap(&presented, &drawing)
        hasPresented = true
        return output
    }
}
private extension BorderStyle {
    var family: _BorderFamily {
        switch self {
        case .ascii: .ascii
        case .single, .rounded: .single
        case .double: .double
        }
    }
}

private struct _BorderConnections: OptionSet, Equatable {
    let rawValue: UInt8
    static let up = Self(rawValue: 1 << 0)
    static let down = Self(rawValue: 1 << 1)
    static let left = Self(rawValue: 1 << 2)
    static let right = Self(rawValue: 1 << 3)
}

private enum _BorderFamily {
    case ascii
    case single
    case double
}

private struct _BorderCell {
    var connections: _BorderConnections
    var style: BorderStyle

    init(connections: _BorderConnections, style: BorderStyle) {
        self.connections = connections
        self.style = style
    }

    init?(glyph: Character) {
        switch glyph {
        case "-": self.init(connections: [.left, .right], style: .ascii)
        case "|": self.init(connections: [.up, .down], style: .ascii)
        case "+": self.init(connections: [.up, .down, .left, .right], style: .ascii)
        case "─": self.init(connections: [.left, .right], style: .single)
        case "│": self.init(connections: [.up, .down], style: .single)
        case "┌": self.init(connections: [.right, .down], style: .single)
        case "┐": self.init(connections: [.left, .down], style: .single)
        case "└": self.init(connections: [.right, .up], style: .single)
        case "┘": self.init(connections: [.left, .up], style: .single)
        case "╭": self.init(connections: [.right, .down], style: .rounded)
        case "╮": self.init(connections: [.left, .down], style: .rounded)
        case "╰": self.init(connections: [.right, .up], style: .rounded)
        case "╯": self.init(connections: [.left, .up], style: .rounded)
        case "├": self.init(connections: [.up, .down, .right], style: .single)
        case "┤": self.init(connections: [.up, .down, .left], style: .single)
        case "┬": self.init(connections: [.left, .right, .down], style: .single)
        case "┴": self.init(connections: [.left, .right, .up], style: .single)
        case "┼": self.init(connections: [.up, .down, .left, .right], style: .single)
        case "═": self.init(connections: [.left, .right], style: .double)
        case "║": self.init(connections: [.up, .down], style: .double)
        case "╔": self.init(connections: [.right, .down], style: .double)
        case "╗": self.init(connections: [.left, .down], style: .double)
        case "╚": self.init(connections: [.right, .up], style: .double)
        case "╝": self.init(connections: [.left, .up], style: .double)
        case "╠": self.init(connections: [.up, .down, .right], style: .double)
        case "╣": self.init(connections: [.up, .down, .left], style: .double)
        case "╦": self.init(connections: [.left, .right, .down], style: .double)
        case "╩": self.init(connections: [.left, .right, .up], style: .double)
        case "╬": self.init(connections: [.up, .down, .left, .right], style: .double)
        default: return nil
        }
    }

    func merging(connections: _BorderConnections, style: BorderStyle) -> Self {
        guard self.style.family == style.family else {
            return Self(connections: connections, style: style)
        }
        return Self(
            connections: self.connections.union(connections),
            style: self.style == .rounded && style == .rounded ? .rounded : style
        )
    }

    var glyph: Character {
        switch style.family {
        case .ascii:
            if connections == [.left, .right] { return "-" }
            if connections == [.up, .down] { return "|" }
            return "+"
        case .single:
            switch connections {
            case [.left, .right]: return "─"
            case [.up, .down]: return "│"
            case [.right, .down]: return style == .rounded ? "╭" : "┌"
            case [.left, .down]: return style == .rounded ? "╮" : "┐"
            case [.right, .up]: return style == .rounded ? "╰" : "└"
            case [.left, .up]: return style == .rounded ? "╯" : "┘"
            case [.up, .down, .right]: return "├"
            case [.up, .down, .left]: return "┤"
            case [.left, .right, .down]: return "┬"
            case [.left, .right, .up]: return "┴"
            case [.up, .down, .left, .right]: return "┼"
            default: return "┼"
            }
        case .double:
            switch connections {
            case [.left, .right]: return "═"
            case [.up, .down]: return "║"
            case [.right, .down]: return "╔"
            case [.left, .down]: return "╗"
            case [.right, .up]: return "╚"
            case [.left, .up]: return "╝"
            case [.up, .down, .right]: return "╠"
            case [.up, .down, .left]: return "╣"
            case [.left, .right, .down]: return "╦"
            case [.left, .right, .up]: return "╩"
            case [.up, .down, .left, .right]: return "╬"
            default: return "╬"
            }
        }
    }
}
