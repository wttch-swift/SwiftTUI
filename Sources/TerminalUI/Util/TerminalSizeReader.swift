#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import TerminalUIFoundation

/// 读取当前 POSIX 终端窗口尺寸的无状态工具。
public enum TerminalSizeReader {
    /// 从文件描述符关联的终端读取当前行列数。
    ///
    /// 默认读取标准输出，因为 `TerminalApp` 的画面输出到 stdout。输出被
    /// 重定向、描述符不是 TTY 或系统调用失败时返回 `nil`。
    public static func current(fileDescriptor: Int32 = STDOUT_FILENO) -> TerminalSize? {
        guard isatty(fileDescriptor) == 1 else { return nil }

        var value = winsize()
#if canImport(Darwin)
        let result = Darwin.ioctl(fileDescriptor, TIOCGWINSZ, &value)
#elseif canImport(Glibc)
        let result = Glibc.ioctl(fileDescriptor, UInt(TIOCGWINSZ), &value)
#else
        return nil
#endif

        guard result == 0, value.ws_col > 0, value.ws_row > 0 else { return nil }
        return TerminalSize(columns: Int(value.ws_col), rows: Int(value.ws_row))
    }

    /// 读取终端尺寸，读取失败时返回调用方提供的默认尺寸。
    public static func current(
        or fallback: TerminalSize,
        fileDescriptor: Int32 = STDOUT_FILENO
    ) -> TerminalSize {
        current(fileDescriptor: fileDescriptor) ?? fallback
    }
}
