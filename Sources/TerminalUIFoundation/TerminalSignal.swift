/// TerminalApp 能够观察和处理的 POSIX 终端信号。
///
/// 框架先把异步 POSIX 信号转换成主事件循环事件，再调用应用注册的回调。因此
/// `TerminalApp.onSignal` 或视图 `.onSignal` 中可以安全地修改普通 UI 状态，
/// 不需要遵守原始 signal handler 只能调用 async-signal-safe 函数的限制。
public enum TerminalSignal: Equatable, Sendable {
    /// Ctrl-C 或 `kill -INT` 请求中断应用。
    case interrupt
    /// `kill -TERM` 请求应用正常终止。
    case terminate
    /// 控制终端关闭或 SSH 会话断开。
    case hangup
    /// Ctrl-\ 或 `kill -QUIT` 请求退出。
    case quit
    /// Ctrl-Z 或 `kill -TSTP` 请求挂起应用。
    case suspend
    /// `fg` 或 `kill -CONT` 恢复已挂起的应用。
    case resume
    /// 终端窗口的行列数发生变化。
    case windowSizeChanged
}
