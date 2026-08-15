import TerminalUIFoundation

/// 公共入口:所有业务代码只调用 `TerminalSizeReader.current(...)`,而不直接触碰
/// POSIX / Win32 的具体实现细节。平台实现统一收敛在 `_TerminalPlatform`,这里只做
/// 纯转发,因此不持有任何状态、不依赖任何 host/platform 实例。
public enum TerminalSizeReader {
    /// 从文件描述符关联的终端读取当前行列数。
    ///
    /// 默认读取标准输出,因为 `TerminalApp` 的画面输出到 stdout。输出被重定向、
    /// 描述符不是 TTY 或系统调用失败时返回 `nil`。
    ///
    /// 在 Windows 分支中 `fileDescriptor` 参数会被忽略(Win32 API 走标准输出句柄),
    /// 但保留该参数可以让调用方维持统一签名。
    public static func current(fileDescriptor: Int32? = nil) -> TerminalSize? {
        _TerminalPlatform.currentSize(fileDescriptor: fileDescriptor)
    }

    /// 读取终端尺寸;读取失败时返回调用方提供的默认尺寸。
    public static func current(or fallback: TerminalSize, fileDescriptor: Int32? = nil) -> TerminalSize {
        current(fileDescriptor: fileDescriptor) ?? fallback
    }
}
