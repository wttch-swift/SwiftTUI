
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
        // POSIX 的 isatty 按规范返回 1，但 Windows MSVCRT 返回的是非零的模式值
        //（实际观察到 64），因此用 `!= 0` 判断，避免 Windows 下被误判为非 TTY
        // 而整体禁用颜色。
        detect(isTerminal: isatty(STDOUT_FILENO) != 0)
    }

    public func supportsNatively(_ color: Color) -> Bool {
        self >= color.requiredSupport
    }
}