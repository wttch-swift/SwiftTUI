import TerminalUIFoundation

/// 用户视图可观察的终端事件。
///
/// 这是公开给 View modifier 的事件层；`TerminalApp` 内部还会有 action、
/// renderRequested、stopRequested 等运行时事件，它们不会直接暴露给普通 View。
public enum TerminalEvent {
    case key(KeyPress)
    case resize(TerminalSize)
    case signal(TerminalSignal)
    case message(any TerminalMessage)
}

/// 自定义终端消息的标记协议。
///
/// 后续可以把 worker 完成、组件通知、业务事件等包装为 `TerminalMessage`，
/// 再通过统一事件队列投递给视图树。
public protocol TerminalMessage {}

/// 视图事件处理结果。
public enum TerminalEventResult: Equatable, Sendable {
    /// 当前节点不处理，事件继续向外层传播。
    case ignored
    /// 当前节点已消费事件，停止继续传播。
    case handled
    /// 当前节点已消费事件，并请求事件循环在本批事件后重绘。
    case requestRender

    package var consumesEvent: Bool {
        self != .ignored
    }
}
