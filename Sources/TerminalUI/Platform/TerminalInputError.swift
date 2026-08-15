#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif os(Windows)
import WinSDK
#endif

/// 终端平台错误,供 `_TerminalPlatform.startInput` / `readKey` 等抛给调用方。
public enum TerminalInputError: Error, CustomStringConvertible {
    case notTerminal
    case systemCall(String)

    public var description: String {
        switch self {
        case .notTerminal:
            "standard input is not a terminal"
        case .systemCall(let message):
            message
        }
    }
}

/// 共享的平台错误转码:各平台文件只负责实现真正的 I/O 调用,错误描述统一通过这里
/// 封装,避免重复手写 `errno` / `GetLastError` 逻辑。
///
/// 注意:这里返回的是“可读错误文本”,不是结构化错误码;
/// 诊断时若需要原始码,请从 message 中读取 `(error ...)` 或 `(errno ...)`。
func _terminalInputSystemError(_ operation: String) -> TerminalInputError {
    #if os(Windows)
    let error = GetLastError()
    return TerminalInputError.systemCall("\(operation) failed (error \(error))")
    #else
    return TerminalInputError.systemCall("\(operation) failed (errno \(errno))")
    #endif
}
