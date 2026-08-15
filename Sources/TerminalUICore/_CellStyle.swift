import TerminalUIFoundation


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