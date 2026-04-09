

struct _ForegroundModifier: ViewModifier {
    let color: Color

    func body(content: Content) -> some View {
        content
            .environment(\.foregroundColor, color)
    }
}
