
import TerminalUIFoundation

/// 终端格子，表示终端屏幕上的一个字符单元格，包括字符、前景色、背景色以及文本样式等属性。
package struct _Cell: Equatable {
    package let char: Character

    package let style: _CellStyle

    /// `true` means this cell is only the continuation slot of a wide glyph.
    package let isSpace: Bool

    package init(char: Character, style: _CellStyle, isSpace: Bool = false) {
        self.char = char
        self.style = style
        self.isSpace = isSpace
    }

    /// A wide-character continuation cell. It occupies storage but emits no text.
    package static let Space = _Cell(
        char: " ",
        style: _CellStyle(foregroundColor: .white, backgroundColor: .black),
        isSpace: true
    )

    /// A real, visible blank cell used for untouched canvas space.
    package static let Blank = _Cell(
        char: " ",
        style: _CellStyle(foregroundColor: .white, backgroundColor: .black)
    )
}


extension _Cell {
    package func render(colorSupport: TerminalColorSupport = .current) -> String? {
        guard !isSpace else { return nil }

        var rendered = String(char)
        if style.inverse {
            rendered = rendered.colored(
                fg: style.backgroundColor,
                bg: style.foregroundColor,
                support: colorSupport,
                bold: style.bold,
                italic: style.italic,
                underline: style.underline,
                strikethrough: style.strikethrough
            )
        } else {
            rendered = rendered.colored(
                fg: style.foregroundColor,
                bg: style.backgroundColor,
                support: colorSupport,
                bold: style.bold,
                italic: style.italic,
                underline: style.underline,
                strikethrough: style.strikethrough
            )
        }
        
        return rendered
    }
}

/// 终端格子样式，表示终端屏幕上一个字符单元格的前景色、背景色以及文本样式等属性。
package struct _CellStyle: Equatable {
    // 样式随 cell 保存，使 Canvas 能按相邻 cell 的完整样式差异生成 ANSI 序列；
    // 这也避免粗体、下划线等状态意外泄漏到后续无样式字符。
    package let foregroundColor: Color
    package let backgroundColor: Color

    package let italic: Bool
    package let bold: Bool
    package let underline: Bool
    package let strikethrough: Bool
    package let inverse: Bool

    package init(
        foregroundColor: Color,
        backgroundColor: Color,
        italic: Bool = false,
        bold: Bool = false,
        underline: Bool = false,
        strikethrough: Bool = false,
        inverse: Bool = false
    ) {
        self.foregroundColor = foregroundColor
        self.backgroundColor = backgroundColor
        self.italic = italic
        self.bold = bold
        self.underline = underline
        self.strikethrough = strikethrough
        self.inverse = inverse
    }
}
