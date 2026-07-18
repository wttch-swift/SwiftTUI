import TerminalUIFoundation

package struct _EventModifier: ViewModifier {
    package let action: (TerminalEvent) -> TerminalEventResult

    package func body(content: Content) -> some View {
        _EventContent(content: content, action: action)
    }
}

package struct _EventContent<Content: View>: View, _NeverView {
    package let content: Content
    package let action: (TerminalEvent) -> TerminalEventResult
}

public extension View {
    /// 监听当前视图子树冒泡上来的终端事件。
    ///
    /// 返回 `.handled` 或 `.requestRender` 会消费事件，外层 `onEvent` 不再收到它；
    /// 返回 `.ignored` 时事件继续向外层传播。
    func onEvent(_ action: @escaping (TerminalEvent) -> TerminalEventResult) -> some View {
        modifier(_EventModifier(action: action))
    }

    func onResize(_ action: @escaping (TerminalSize) -> TerminalEventResult) -> some View {
        onEvent { event in
            guard case .resize(let size) = event else { return .ignored }
            return action(size)
        }
    }

    func onSignal(_ action: @escaping (TerminalSignal) -> TerminalEventResult) -> some View {
        onEvent { event in
            guard case .signal(let signal) = event else { return .ignored }
            return action(signal)
        }
    }

    func onMessage<Message: TerminalMessage>(
        _ type: Message.Type = Message.self,
        action: @escaping (Message) -> TerminalEventResult
    ) -> some View {
        onEvent { event in
            guard case .message(let message) = event,
                  let typed = message as? Message else { return .ignored }
            return action(typed)
        }
    }
}
