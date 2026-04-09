/// 可编辑单行文本输入控件。
public struct TextField: View, _NeverView {
    package let title: String
    package let text: Binding<String>
    package let onEditingChanged: (Bool) -> Void
    package let onCommit: () -> Void
    package let state = _TextFieldState()

    public init(
        _ title: String,
        text: Binding<String>,
        onEditingChanged: @escaping (Bool) -> Void = { _ in },
        onCommit: @escaping () -> Void = {}
    ) {
        self.title = title
        self.text = text
        self.onEditingChanged = onEditingChanged
        self.onCommit = onCommit
    }
}

/// 输入框随声明值跨布局节点重建保留的交互状态。
package final class _TextFieldState {
    package var cursor: Int?
    package var scrollIndex = 0
    package var isFocused = false

    package func clamp(to characterCount: Int) -> Int {
        let resolved = min(characterCount, max(0, cursor ?? characterCount))
        cursor = resolved
        scrollIndex = min(resolved, max(0, scrollIndex))
        return resolved
    }
}
