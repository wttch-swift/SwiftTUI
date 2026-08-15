import Foundation

/// 在终端画布上显示纯文本的基础视图。
///
/// `Text` 本身不保存颜色等外观属性；这些属性由环境值在渲染时注入。
/// 文本会按可用的终端单元格宽度自动换行。中文和 emoji 等宽字符
/// 不会被拆分；可用行数不足时，最后一个可见行会以省略号结尾。
extension Text: _LayoutNodeProducing {

    /// 将声明式文本转换为能根据 proposal 重新排版的文本节点。
    package func _makeLayoutNode() -> any _Layoutable {
        _TextLayoutNode(text: text)
    }
}

private final class _TextLayoutNode: _RenderReusableLayoutNode {
    let text: String
    /// Unicode grapheme segmentation and terminal-width calculation are much more
    /// expensive than arranging already measured glyphs. A text node is measured
    /// several times by nested stacks before it is drawn, so do this work once.
    private let segments: [Segment]
    private let naturalWidth: Int
    private var cachedLayouts: [_TextLayout.Key: _TextLayout] = [:]
    private(set) var frame: Rect = .zero

    init(text: String) {
        self.text = text
        let analysis = _TextLayoutCache.shared.analysis(for: text)
        self.segments = analysis.segments
        self.naturalWidth = analysis.naturalWidth
    }

    func measure(proposed: ProposedSize) -> Size {
        // 有宽度 proposal 时必须按该宽度实际换行后再测高；无约束时才使用最长
        // 显式行作为固有宽度，否则父容器无法获知文本压缩后的真实行数。
        let width = proposed.width.map { max(0, $0) } ?? naturalWidth
        let layout = layout(width: width)
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

        let layout = layout(width: frame.w, maximumLines: availableLines)
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

    func renderFingerprint(environment: EnvironmentValues) -> Int {
        var hasher = Hasher()
        hasher.combine(text)
        hasher.combine(environment.renderFingerprint)
        return hasher.finalize()
    }

    private func layout(width: Int, maximumLines: Int? = nil) -> _TextLayout {
        let key = _TextLayout.Key(width: width, maximumLines: maximumLines)
        if let cached = cachedLayouts[key] { return cached }
        let result = _TextLayoutCache.shared.layout(
            text: text,
            segments: segments,
            width: width,
            maximumLines: maximumLines
        )
        cachedLayouts[key] = result
        return result
    }
}

/// Layout nodes are rebuilt for each terminal frame. Keeping only a node-local
/// cache would therefore repeat all text work on the next key press. This bounded,
/// thread-safe cache lets stable ScrollView rows reuse their analysis and wrapping
/// across frames without retaining an unlimited chat history.
private final class _TextLayoutCache: @unchecked Sendable {
    struct Analysis {
        let segments: [Segment]
        let naturalWidth: Int
    }

    struct LayoutKey: Hashable {
        let text: String
        let width: Int
        let maximumLines: Int?
    }

    static let shared = _TextLayoutCache()

    private let lock = NSLock()
    private var analyses: [String: Analysis] = [:]
    private var layouts: [LayoutKey: _TextLayout] = [:]
    private let maximumEntryCount = 2_048

    func analysis(for text: String) -> Analysis {
        lock.lock()
        if let cached = analyses[text] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let segments = Segment.segment(text)
        let result = Analysis(segments: segments, naturalWidth: _TextLayout.naturalWidth(of: segments))

        lock.lock()
        if analyses.count >= maximumEntryCount { analyses.removeAll(keepingCapacity: true) }
        analyses[text] = result
        lock.unlock()
        return result
    }

    func layout(text: String, segments: [Segment], width: Int, maximumLines: Int?) -> _TextLayout {
        let key = LayoutKey(text: text, width: width, maximumLines: maximumLines)
        lock.lock()
        if let cached = layouts[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let result = _TextLayout(segments: segments, width: width, maximumLines: maximumLines)

        lock.lock()
        if layouts.count >= maximumEntryCount { layouts.removeAll(keepingCapacity: true) }
        layouts[key] = result
        lock.unlock()
        return result
    }
}

/// Text 测量和绘制共用的终端 cell 排版结果。
private struct _TextLayout {
    struct Key: Hashable {
        let width: Int
        let maximumLines: Int?
    }

    static let ellipsis = "…"

    let lines: [String]

    init(segments: [Segment], width: Int, maximumLines: Int? = nil) {
        guard width > 0 else {
            // 零宽度时无法绘制，但测量仍保留显式换行带来的行高。
            lines = Array(repeating: "", count: Self.explicitLineCount(in: segments))
            return
        }

        // 先生成完整换行结果，再应用最大行数，才能判断最后一行是否需要省略号。
        let wrapped = Self.wrap(segments, width: width)
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

    static func naturalWidth(of segments: [Segment]) -> Int {
        // 自然宽度只尊重显式换行，不在无约束测量阶段主动折行。
        var maximum = 0
        var current = 0
        for segment in segments {
            if segment.kind == .control, segment.text == "\n" || segment.text == "\r" || segment.text == "\r\n" {
                maximum = max(maximum, current)
                current = 0
            } else if segment.kind == .text {
                current += segment.cellLength
            }
        }
        return max(maximum, current)
    }

    private static func wrap(_ segments: [Segment], width: Int) -> (lines: [String], wasTruncated: Bool) {
        var lines = [""]
        var currentWidth = 0

        for segment in segments {
            if segment.kind == .control, segment.text == "\n" || segment.text == "\r" || segment.text == "\r\n" {
                lines.append("")
                currentWidth = 0
                continue
            }
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
            lines[lines.count - 1] += segment.text
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

    private static func explicitLineCount(in segments: [Segment]) -> Int {
        var count = 1
        for segment in segments where segment.kind == .control {
            if segment.text == "\n" || segment.text == "\r" || segment.text == "\r\n" {
                count += 1
            }
        }
        return count
    }
}
