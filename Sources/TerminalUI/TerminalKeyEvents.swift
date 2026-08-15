import WttchCombine

/// 全局按键流。
///
/// `_TerminalAppHost.run()` 每次读到按键都会 `send`;宿主内部订阅它驱动原有的
/// onKeyPress 分发,因此视图层的 `.onKeyPress` 底层数据来源就是这条 Combine 流。
/// 客户端也可直接订阅:
///
/// ```swift
/// let token = TerminalKeyEvents.stream.sink { key in
///     print("按下了 \(key.key)")
/// }
/// ```
public enum TerminalKeyEvents {
    public static let stream = PassthroughSubject<KeyPress, Never>()
}
