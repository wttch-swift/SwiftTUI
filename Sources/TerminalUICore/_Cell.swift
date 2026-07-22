
import TerminalUIFoundation

/// 终端格子，表示终端屏幕上的一个字符单元格，包括字符、前景色、背景色以及文本样式等属性。
package struct _Cell: Equatable {
    /// 要显示的字符
    package let char: Character
    /// 格子样式，包含前景色、背景色以及文本样式等属性
    package let style: _CellStyle
    /// 如果是宽字符的延续格子，则为 true。延续格子占用存储，但不输出任何文本。
    package let isSpace: Bool

    
    /// 构造函数，创建一个新的终端格子实例。
    /// - Parameters:
    ///   - char: 要显示的字符
    ///   - style: 格子样式，包含前景色、背景色以及文本样式等属性
    ///   - isSpace: 如果是宽字符的延续格子，则为 true。
    package init(char: Character, style: _CellStyle, isSpace: Bool = false) {
        self.char = char
        self.style = style
        self.isSpace = isSpace
    }
}


extension _Cell {
    
    /// 一个空格格子，用于表示宽字符的延续格子。
    package static let Space = _Cell(
        char: " ",
        style: _CellStyle(foregroundColor: .white, backgroundColor: .black),
        isSpace: true
    )

    /// 一个真实的、可见的空白格子，用于表示未被触及的画布空间。
    package static let Blank = _Cell(
        char: " ",
        style: _CellStyle(foregroundColor: .white, backgroundColor: .black)
    )

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

