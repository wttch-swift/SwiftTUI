public extension View {
    func sheet<SheetContent: View>(
        isPresented: Binding<Bool>,
        alignment: AlignmentEdge = .center,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: () -> SheetContent
    ) -> some View {
        _PresentationView(
            base: self,
            presented: content(),
            isPresented: isPresented,
            alignment: alignment,
            style: .sheet,
            onDismiss: onDismiss
        )
    }

    func toast<ToastContent: View>(
        isPresented: Binding<Bool>,
        alignment: AlignmentEdge = .top,
        @ViewBuilder content: () -> ToastContent
    ) -> some View {
        _PresentationView(
            base: self,
            presented: content(),
            isPresented: isPresented,
            alignment: alignment,
            style: .toast,
            onDismiss: nil
        )
    }
}

package struct _PresentationView<Base: View, Presented: View>: View, _NeverView {
    package let base: Base
    package let presented: Presented
    package let isPresented: Binding<Bool>
    package let alignment: AlignmentEdge
    package let style: _PresentationStyle
    package let onDismiss: (() -> Void)?
}

package enum _PresentationStyle: Equatable {
    case sheet
    case toast
}
