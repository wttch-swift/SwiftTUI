package struct _KeyPressModifier: ViewModifier {
    package let keys: Set<KeyPress.Key>?
    package let action: (KeyPress) -> KeyPress.Result

    package func body(content: Content) -> some View {
        _KeyPressContent(content: content, keys: keys, action: action)
    }
}

package struct _KeyPressContent<Content: View>: View, _NeverView {
    package let content: Content
    package let keys: Set<KeyPress.Key>?
    package let action: (KeyPress) -> KeyPress.Result
}

public extension View {
    func onKeyPress(_ action: @escaping (KeyPress) -> KeyPress.Result) -> some View {
        modifier(_KeyPressModifier(keys: nil, action: action))
    }

    func onKeyPress(
        _ key: KeyPress.Key,
        action: @escaping (KeyPress) -> KeyPress.Result
    ) -> some View {
        modifier(_KeyPressModifier(keys: [key], action: action))
    }

    func onKeyPress(
        keys: Set<KeyPress.Key>,
        action: @escaping (KeyPress) -> KeyPress.Result
    ) -> some View {
        modifier(_KeyPressModifier(keys: keys, action: action))
    }
}
