/// 在终端画布上显示纯文本的基础视图。
///
/// `Text` 本身不保存颜色等外观属性；这些属性由环境值在渲染时注入。
/// 文本会按可用的终端单元格宽度自动换行。中文和 emoji 等宽字符
/// 不会被拆分；可用行数不足时，最后一个可见行会以省略号结尾。
extension Text: _LayoutNodeProducing {

    /// 将声明式文本转换为能根据 proposal 重新排版的文本节点。
    package func _makeLayoutNode() -> any _LayoutNode {
        _TextLayoutNode(text: text)
    }
}

private final class _TextLayoutNode: _RenderableLayoutNode {
    let text: String
    private(set) var frame: Rect = .zero

    init(text: String) {
        self.text = text
    }

    func measure(proposed: ProposedSize) -> Size {
        // 有宽度 proposal 时必须按该宽度实际换行后再测高；无约束时才使用最长
        // 显式行作为固有宽度，否则父容器无法获知文本压缩后的真实行数。
        let width = proposed.width.map { max(0, $0) } ?? _TextLayout.naturalWidth(of: text)
        let layout = _TextLayout(text: text, width: width)
        let measuredHeight = min(layout.lines.count, proposed.height ?? layout.lines.count)
        return Size(
            w: min(layout.lines.map(\.displayWidth).max() ?? 0, width),
            h: max(0, measuredHeight)
        )
    }

    func layout(in rect: Rect) {
        frame = rect
    }

    func draw(to canvas: Canvas, environment: EnvironmentValues) {
        // frame 高度与 lineLimit 共同决定可见行数，较小者负责最终截断。
        let availableLines = min(frame.h, environment.lineLimit ?? frame.h)
        guard frame.w > 0, availableLines > 0 else { return }

        let layout = _TextLayout(text: text, width: frame.w, maximumLines: availableLines)
        for (offset, line) in layout.lines.enumerated() {
            canvas.drawText(
                x: frame.x,
                y: frame.y + offset,
                text: line,
                foreground: environment.foregroundColor ?? .white,
                background: environment.backgroundColor,
                bold: environment._isBold,
                italic: environment._isItalic,
                underline: environment._isUnderline,
                strikethrough: environment._isStrikethrough
            )
        }
    }
}

/// Text 测量和绘制共用的终端 cell 排版结果。
private struct _TextLayout {
    static let ellipsis = "…"

    let lines: [String]

    init(text: String, width: Int, maximumLines: Int? = nil) {
        guard width > 0 else {
            // 零宽度时无法绘制，但测量仍保留显式换行带来的行高。
            lines = Array(repeating: "", count: Self.explicitLines(in: text).count)
            return
        }

        // 先生成完整换行结果，再应用最大行数，才能判断最后一行是否需要省略号。
        let wrapped = Self.wrap(text, width: width)
        let visibleCount = min(wrapped.lines.count, max(0, maximumLines ?? wrapped.lines.count))
        guard visibleCount > 0 else {
            lines = []
            return
        }

        var visible = Array(wrapped.lines.prefix(visibleCount))
        if wrapped.wasTruncated || visibleCount < wrapped.lines.count {
            visible[visible.count - 1] = Self.addEllipsis(to: visible[visible.count - 1], width: width)
        }
        lines = visible
    }

    static func naturalWidth(of text: String) -> Int {
        // 自然宽度只尊重显式换行，不在无约束测量阶段主动折行。
        explicitLines(in: text).map(\.displayWidth).max() ?? 0
    }

    private static func wrap(_ text: String, width: Int) -> (lines: [String], wasTruncated: Bool) {
        var lines = [""]
        var currentWidth = 0

        for character in text {
            let value = String(character)
            if value == "\n" || value == "\r" || value == "\r\n" {
                lines.append("")
                currentWidth = 0
                continue
            }

            // Segment 同时提供可绘制类型和终端 cell 宽度，不能用 String.count
            // 代替，否则中文、emoji 和组合字符会得到错误的换行位置。
            guard let segment = Segment.segment(value).first else { continue }
            guard segment.kind == .text, segment.cellLength > 0 else { continue }

            // 宽字符比整行还宽时无法完整绘制，以省略号结束排版。
            guard segment.cellLength <= width else {
                if currentWidth > 0 {
                    lines.append("")
                }
                return (lines, true)
            }

            if currentWidth + segment.cellLength > width {
                lines.append("")
                currentWidth = 0
            }
            lines[lines.count - 1] += value
            currentWidth += segment.cellLength
        }

        return (lines, false)
    }

    private static func addEllipsis(to line: String, width: Int) -> String {
        // 先为省略号预留 cell，再按显示宽度截断，保证最终结果不会越过 frame。
        let ellipsisWidth = ellipsis.displayWidth
        guard width >= ellipsisWidth else { return "" }
        return line.truncated(toWidth: width - ellipsisWidth) + ellipsis
    }

    private static func explicitLines(in text: String) -> [String] {
        // 该路径用于固有尺寸测量：过滤控制片段，但保留用户输入的空行。
        var lines = [""]
        for character in text {
            let value = String(character)
            if value == "\n" || value == "\r" || value == "\r\n" {
                lines.append("")
            } else if Segment.segment(value).first?.kind == .text {
                lines[lines.count - 1] += value
            }
        }
        return lines
    }
}

