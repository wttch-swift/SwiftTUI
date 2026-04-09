/// 文本片段类型。
///
/// `Segment` 会把输入字符串拆成多个“终端可绘制片段”。普通文本和控制字符
/// 需要分开处理：普通文本会占用终端格子，控制字符例如换行、退格等不应该直接
/// 画到 `Canvas` 的某个单元格中。
public enum SegmentKind: Equatable {
    /// 可显示文本，会根据 Unicode 字符属性计算终端 cell 宽度。
    case text

    /// 控制字符或格式字符，终端显示宽度固定为 0。
    case control
}

/// 一个类似 Rich `Segment` 的终端文本片段。
///
/// Swift 的 `Character` 表示的是扩展字素簇，而不是单个 Unicode scalar。
/// 这点对终端渲染很重要：例如 `e + 重音符`、国旗 emoji、家庭 emoji
/// 都可能由多个 scalar 组成，但用户看到的是一个“字符”。本类型以字素簇
/// 为基本单位记录原始文本、片段类型和终端 cell 宽度，避免绘制、对齐和截断时
/// 把一个可见字符拆坏。
public struct Segment: Equatable {
    /// 片段原文，通常只包含一个 Swift `Character`。
    public let text: String

    /// 片段类型，用于区分可显示文本和控制字符。
    public let kind: SegmentKind

    /// 片段在等宽终端中占用的 cell 数量。
    ///
    /// 常见规则：
    /// - ASCII 字符占 1 格。
    /// - 中文、全角字符和大多数 emoji 占 2 格。
    /// - 组合音标、变体选择符、零宽连接符和控制字符占 0 格。
    public let cellLength: Int

    /// 创建一个片段，并立即计算它的终端显示宽度。
    ///
    /// - Parameters:
    ///   - text: 片段原文。
    ///   - kind: 片段类型。控制字符宽度固定为 0。
    public init(_ text: String, kind: SegmentKind = .text) {
        self.text = text
        self.kind = kind
        self.cellLength = kind == .control ? 0 : Segment.width(of: text)
    }

    /// 将字符串拆成一组终端文本片段。
    ///
    /// 这里按 Swift `Character` 遍历，因此不会把组合字符或 emoji 序列拆散。
    /// 例如 `👨‍👩‍👧‍👦` 会被看作一个片段，而不是多个独立 emoji 和零宽连接符。
    public static func segment(_ text: String) -> [Segment] {
        text.map { character in
            let kind: SegmentKind = character.isTerminalControl ? .control : .text
            return Segment(String(character), kind: kind)
        }
    }

    /// 计算整段字符串在终端中占用的 cell 宽度。
    ///
    /// 这比直接使用 `String.count` 更适合终端布局，因为中文、emoji 等字符
    /// 通常占 2 个 cell，而组合音标等字符占 0 个 cell。
    public static func cellLength(of text: String) -> Int {
        segment(text).reduce(0) { $0 + $1.cellLength }
    }

    /// 按终端 cell 宽度截断字符串。
    ///
    /// 截断时以 `Segment` 为单位，不会返回半个宽字符或拆坏 emoji 序列。
    /// 如果下一个片段放不进 `maxCellLength`，会在该片段之前停止。
    public static func truncate(_ text: String, to maxCellLength: Int) -> String {
        guard maxCellLength > 0 else { return "" }

        var currentLength = 0
        var output = ""

        for segment in segment(text) {
            let nextLength = currentLength + segment.cellLength
            if nextLength > maxCellLength {
                break
            }
            output += segment.text
            currentLength = nextLength
        }

        return output
    }

    /// 计算一段文本的终端宽度。
    ///
    /// 该方法假设输入已经是普通文本，控制字符的宽度处理由 `init` 负责。
    private static func width(of text: String) -> Int {
        text.reduce(0) { $0 + $1.terminalCellWidth }
    }
}

private extension Character {
    /// 当前字素簇在终端中占用的 cell 数量。
    ///
    /// 一个 `Character` 可能由多个 Unicode scalar 组成。这里先处理整体上
    /// 必然为宽字符的 emoji 组合，再回退到各 scalar 宽度的最大值。
    var terminalCellWidth: Int {
        if isTerminalControl {
            return 0
        }

        // ZWJ emoji、带 emoji 变体选择符的字符、keycap emoji 都应作为
        // 一个宽字符显示，而不是把内部的零宽符号单独计入宽度。
        if unicodeScalars.contains(where: { $0.properties.isJoinControl || $0.isEmojiPresentationSelector || $0.isKeycapCombiningMark }) {
            return 2
        }

        // 对普通字素簇取 scalar 宽度最大值：
        // - `e\u{301}` 中 `e` 为 1，组合音标为 0，整体应为 1。
        // - CJK 字符包含一个宽 scalar，整体应为 2。
        var width = 0
        for scalar in unicodeScalars {
            width = max(width, scalar.terminalCellWidth)
        }
        return width
    }

    /// 是否是单个终端控制字符。
    ///
    /// 只有整个 `Character` 都是一个控制 scalar 时才视为控制片段；
    /// 混在普通字素簇里的格式 scalar 会由宽度计算逻辑单独处理。
    var isTerminalControl: Bool {
        unicodeScalars.count == 1 && unicodeScalars.first?.isTerminalControl == true
    }
}

private extension Unicode.Scalar {
    /// 当前 Unicode scalar 的终端 cell 宽度。
    ///
    /// 这是对常见 `wcwidth` 行为的轻量实现，覆盖 TerminalUI 当前需要的
    /// 中文、全角字符、emoji、组合字符和控制字符场景。
    var terminalCellWidth: Int {
        // 控制字符、格式字符、组合音标、变体选择符和零宽连接符不单独占格。
        if isTerminalControl || properties.generalCategory == .nonspacingMark || properties.isVariationSelector || properties.isJoinControl {
            return 0
        }

        // East Asian Wide/Fullwidth 字符和 emoji 通常在终端中占 2 格。
        if isWideEastAsianScalar || isEmojiScalar {
            return 2
        }

        // 其他可见字符默认按窄字符处理，占 1 格。
        return 1
    }

    /// 是否是控制字符或格式字符。
    ///
    /// `.format` 中包含一些零宽格式控制符，例如 ZWJ；它们不应单独占用 cell。
    var isTerminalControl: Bool {
        properties.generalCategory == .control || properties.generalCategory == .format
    }

    /// Emoji 变体选择符 U+FE0F。
    ///
    /// 它会让某些字符以 emoji 风格显示，例如 `❤` + U+FE0F 变成 `❤️`。
    var isEmojiPresentationSelector: Bool {
        value == 0xFE0F
    }

    /// Keycap 组合符 U+20E3。
    ///
    /// 例如 `1` + U+FE0F + U+20E3 会组成 `1️⃣`。
    var isKeycapCombiningMark: Bool {
        value == 0x20E3
    }

    /// 是否处在常见 emoji Unicode 区段。
    ///
    /// 这里采用覆盖终端 UI 常见 emoji 的区间判断，不追求完整 Unicode Emoji
    /// 数据库级别的精确性。
    var isEmojiScalar: Bool {
        switch value {
        case 0x1F000...0x1FAFF,
             0x2600...0x27BF:
            return true
        default:
            return false
        }
    }

    /// 是否处在常见 East Asian Wide / Fullwidth 区段。
    ///
    /// 这些字符在等宽终端里通常占 2 个 cell，包括中文、日文、韩文、
    /// 全角标点以及 CJK 扩展区字符。
    var isWideEastAsianScalar: Bool {
        switch value {
        case 0x1100...0x115F,
             0x231A...0x231B,
             0x2329...0x232A,
             0x2E80...0xA4CF,
             0xAC00...0xD7A3,
             0xF900...0xFAFF,
             0xFE10...0xFE19,
             0xFE30...0xFE6F,
             0xFF00...0xFF60,
             0xFFE0...0xFFE6,
             0x20000...0x3FFFD:
            return true
        default:
            return false
        }
    }
}
