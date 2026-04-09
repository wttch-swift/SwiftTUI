
import Foundation

/// Color depth available in the current terminal.
public enum TerminalColorSupport: Int, Comparable, Sendable, CustomStringConvertible {
    case none = 0
    case ansi8 = 1
    case ansi256 = 2
    case trueColor = 3

    public static func < (lhs: TerminalColorSupport, rhs: TerminalColorSupport) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var description: String {
        switch self {
        case .none: return "No Color"
        case .ansi8: return "ANSI 8 Color"
        case .ansi256: return "8-bit / 256 Color"
        case .trueColor: return "24-bit True Color"
        }
    }

    /// Detects color depth from common terminal environment conventions.
    public static func detect(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        isTerminal: Bool = true
    ) -> TerminalColorSupport {
        guard isTerminal else { return .none }
        if environment["NO_COLOR"] != nil { return .none }

        let term = environment["TERM", default: ""].lowercased()
        let colorTerm = environment["COLORTERM", default: ""].lowercased()
        if term == "dumb" { return .none }

        if colorTerm.contains("truecolor") || colorTerm.contains("24bit") ||
            term.contains("truecolor") || term.contains("24bit") || term.contains("direct") ||
            environment["WT_SESSION"] != nil || environment["KITTY_WINDOW_ID"] != nil {
            return .trueColor
        }
        if term.contains("256color") { return .ansi256 }
        return .ansi8
    }

    public static var current: TerminalColorSupport {
        detect(isTerminal: isatty(STDOUT_FILENO) == 1)
    }

    public func supportsNatively(_ color: Color) -> Bool {
        self >= color.requiredSupport
    }
}

/// A terminal color that can be ANSI, indexed 8-bit, or 24-bit RGB.
public struct Color: RawRepresentable, Hashable, Sendable {
    enum Storage: Hashable, Sendable {
        case ansi(UInt8)
        case indexed(UInt8)
        case rgb(UInt8, UInt8, UInt8)
    }

    let storage: Storage

    /// 颜色身份由原始存储表示决定，不通过 `rawValue` 做近似色转换。
    ///
    /// `RawRepresentable` 的默认比较会读取 `rawValue`；RGB 的 rawValue 需要
    /// 搜索最近的 xterm 色。如果逐 cell 比较样式时走该路径，会重复执行
    /// 数千次调色板搜索，直接拖慢每次终端刷新。
    public static func == (lhs: Color, rhs: Color) -> Bool {
        lhs.storage == rhs.storage
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(storage)
    }

    public init?(rawValue: Int) {
        guard (0...15).contains(rawValue) else { return nil }
        storage = .ansi(UInt8(rawValue))
    }

    /// Preserves the original ANSI raw values for the standard named colors.
    public var rawValue: Int {
        switch storage {
        case .ansi(let index): return Int(index)
        case .indexed(let index): return Int(index)
        case .rgb(let red, let green, let blue):
            return Int(_nearestXtermIndex(red: red, green: green, blue: blue))
        }
    }

    public static func ansi(_ index: UInt8) -> Color {
        Color(storage: .ansi(min(index, 15)))
    }

    public static func indexed(_ index: UInt8) -> Color {
        Color(storage: .indexed(index))
    }

    public init(red: Int, green: Int, blue: Int) {
        storage = .rgb(
            UInt8(clamping: red),
            UInt8(clamping: green),
            UInt8(clamping: blue)
        )
    }

    public static func rgb(_ red: Int, _ green: Int, _ blue: Int) -> Color {
        Color(red: red, green: green, blue: blue)
    }

    public var requiredSupport: TerminalColorSupport {
        switch storage {
        case .ansi: return .ansi8
        case .indexed: return .ansi256
        case .rgb: return .trueColor
        }
    }

    public func foregroundCode(for support: TerminalColorSupport) -> String? {
        _sgrCode(background: false, support: support)
    }

    public func backgroundCode(for support: TerminalColorSupport) -> String? {
        _sgrCode(background: true, support: support)
    }

    private init(storage: Storage) {
        self.storage = storage
    }

    private func _sgrCode(background: Bool, support: TerminalColorSupport) -> String? {
        guard support != .none else { return nil }

        switch (storage, support) {
        case (.ansi(let index), .ansi8):
            return String((background ? 40 : 30) + Int(index % 8))
        case (.ansi(let index), _):
            if index < 8 {
                return String((background ? 40 : 30) + Int(index))
            }
            return String((background ? 100 : 90) + Int(index - 8))
        case (.indexed(let index), .ansi8):
            let rgb = _xtermRGB(index)
            let ansi = _nearestANSIIndex(red: rgb.0, green: rgb.1, blue: rgb.2)
            return String((background ? 40 : 30) + Int(ansi))
        case (.indexed(let index), .ansi256), (.indexed(let index), .trueColor):
            return "\(background ? 48 : 38);5;\(index)"
        case (.rgb(let red, let green, let blue), .trueColor):
            return "\(background ? 48 : 38);2;\(red);\(green);\(blue)"
        case (.rgb(let red, let green, let blue), .ansi256):
            return "\(background ? 48 : 38);5;\(_nearestXtermIndex(red: red, green: green, blue: blue))"
        case (.rgb(let red, let green, let blue), .ansi8):
            let ansi = _nearestANSIIndex(red: red, green: green, blue: blue)
            return String((background ? 40 : 30) + Int(ansi))
        case (_, .none):
            return nil
        }
    }
}

// MARK: - ANSI colors

public extension Color {
    static let black = ansi(0)
    static let red = ansi(1)
    static let green = ansi(2)
    static let yellow = ansi(3)
    static let blue = ansi(4)
    static let magenta = ansi(5)
    static let cyan = ansi(6)
    static let white = ansi(7)

    static let brightBlack = ansi(8)
    static let brightRed = ansi(9)
    static let brightGreen = ansi(10)
    static let brightYellow = ansi(11)
    static let brightBlue = ansi(12)
    static let brightMagenta = ansi(13)
    static let brightCyan = ansi(14)
    static let brightWhite = ansi(15)
}

// MARK: - Named true colors

public extension Color {
    static let gray = rgb(128, 128, 128)
    static let grey = gray
    static let darkGray = rgb(64, 64, 64)
    static let lightGray = rgb(211, 211, 211)
    static let silver = rgb(192, 192, 192)

    static let orange = rgb(255, 165, 0)
    static let amber = rgb(255, 191, 0)
    static let gold = rgb(255, 215, 0)
    static let coral = rgb(255, 127, 80)
    static let salmon = rgb(250, 128, 114)
    static let tomato = rgb(255, 99, 71)
    static let crimson = rgb(220, 20, 60)
    static let pink = rgb(255, 105, 180)

    static let maroon = rgb(128, 0, 0)
    static let brown = rgb(165, 42, 42)
    static let olive = rgb(128, 128, 0)
    static let lime = rgb(0, 255, 0)
    static let emerald = rgb(80, 200, 120)
    static let mint = rgb(62, 180, 137)
    static let teal = rgb(0, 128, 128)
    static let turquoise = rgb(64, 224, 208)
    static let aqua = rgb(0, 255, 255)

    static let navy = rgb(0, 0, 128)
    static let royalBlue = rgb(65, 105, 225)
    static let steelBlue = rgb(70, 130, 180)
    static let skyBlue = rgb(135, 206, 235)
    static let indigo = rgb(75, 0, 130)
    static let purple = rgb(128, 0, 128)
    static let violet = rgb(238, 130, 238)
    static let orchid = rgb(218, 112, 214)
    static let plum = rgb(221, 160, 221)
    static let fuchsia = rgb(255, 0, 255)

    static let khaki = rgb(240, 230, 140)
    static let beige = rgb(245, 245, 220)
    static let ivory = rgb(255, 255, 240)
}

public extension String {
    /// Applies the best available encoding and automatically downgrades colors.
    func colored(
        fg: Color,
        bg: Color?,
        support: TerminalColorSupport = .current,
        bold: Bool = false,
        italic: Bool = false,
        underline: Bool = false,
        strikethrough: Bool = false
    ) -> String {
        // 不支持 ANSI 时连文字装饰也不能输出，否则重定向到文件会混入转义码。
        guard support != .none else { return self }
        var codes: [String] = []
        // SGR 可在同一序列中组合装饰和前后景色，末尾统一 reset 所有属性。
        if bold { codes.append("1") }
        if italic { codes.append("3") }
        if underline { codes.append("4") }
        if strikethrough { codes.append("9") }
        if let foreground = fg.foregroundCode(for: support) { codes.append(foreground) }
        if let background = bg?.backgroundCode(for: support) { codes.append(background) }
        guard !codes.isEmpty else { return self }
        return "\u{1B}[\(codes.joined(separator: ";"))m\(self)\u{1B}[0m"
    }
}

private let _ansiPalette: [(UInt8, UInt8, UInt8)] = [
    (0, 0, 0), (128, 0, 0), (0, 128, 0), (128, 128, 0),
    (0, 0, 128), (128, 0, 128), (0, 128, 128), (192, 192, 192),
    (128, 128, 128), (255, 0, 0), (0, 255, 0), (255, 255, 0),
    (0, 0, 255), (255, 0, 255), (0, 255, 255), (255, 255, 255)
]

private func _nearestANSIIndex(red: UInt8, green: UInt8, blue: UInt8) -> UInt8 {
    UInt8(_nearestColorIndex(red: red, green: green, blue: blue, palette: Array(_ansiPalette.prefix(8))))
}

private func _nearestXtermIndex(red: UInt8, green: UInt8, blue: UInt8) -> UInt8 {
    UInt8(_nearestColorIndex(red: red, green: green, blue: blue, palette: _xtermPalette))
}

/// xterm 调色板固定不变，只构造一次，供显式 rawValue 转换复用。
private let _xtermPalette = (0..<256).map { _xtermRGB(UInt8($0)) }

private func _nearestColorIndex(
    red: UInt8,
    green: UInt8,
    blue: UInt8,
    palette: [(UInt8, UInt8, UInt8)]
) -> Int {
    var bestIndex = 0
    var bestDistance = Int.max
    for (index, candidate) in palette.enumerated() {
        let dr = Int(red) - Int(candidate.0)
        let dg = Int(green) - Int(candidate.1)
        let db = Int(blue) - Int(candidate.2)
        let distance = dr * dr + dg * dg + db * db
        if distance < bestDistance {
            bestIndex = index
            bestDistance = distance
        }
    }
    return bestIndex
}

private func _xtermRGB(_ index: UInt8) -> (UInt8, UInt8, UInt8) {
    let value = Int(index)
    if value < 16 { return _ansiPalette[value] }
    if value >= 232 {
        let gray = UInt8(8 + (value - 232) * 10)
        return (gray, gray, gray)
    }

    let cube = value - 16
    let levels: [UInt8] = [0, 95, 135, 175, 215, 255]
    return (
        levels[cube / 36],
        levels[(cube % 36) / 6],
        levels[cube % 6]
    )
}
