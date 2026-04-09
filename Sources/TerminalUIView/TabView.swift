public struct TabView<SelectionValue, Content>: View, _NeverView
where SelectionValue: Hashable, Content: View {
    package let selection: Binding<SelectionValue>?
    package let content: Content

    public init(selection: Binding<SelectionValue>?, @ViewBuilder content: () -> Content) {
        self.selection = selection
        self.content = content()
    }
}

public extension TabView where SelectionValue == Int {
    init(@ViewBuilder content: () -> Content) {
        self.init(selection: nil, content: content)
    }
}

public extension View {
    func tag<V: Hashable>(_ tag: V) -> some View {
        modifier(_TagModifier(value: AnyHashable(tag)))
    }

    func tabItem<Label: View>(@ViewBuilder _ label: () -> Label) -> some View {
        modifier(_TabItemModifier(label: label()))
    }
}

package struct _TagModifier: ViewModifier {
    package let value: AnyHashable

    package func body(content: Content) -> some View {
        _TabMetadataContent(content: content, tag: value, label: nil)
    }
}

package struct _TabItemModifier<Label: View>: ViewModifier {
    package let label: Label

    package func body(content: Content) -> some View {
        _TabMetadataContent(content: content, tag: nil, label: AnyView(label))
    }
}

package struct _TabMetadataContent<Content: View>: View, _NeverView {
    package let content: Content
    package let tag: AnyHashable?
    package let label: AnyView?
}
