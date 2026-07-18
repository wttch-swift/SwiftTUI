/// A modal presentation positioned at any of the nine `AlignmentEdge` points.
///
/// The declaration follows SwiftUI's binding-driven sheet API, with an
/// additional terminal-specific `alignment` argument. While visible, keys that
/// the sheet does not handle are blocked from reaching the underlying content;
/// Escape dismisses the sheet.
extension _PresentationView: _LayoutNodeProducing {
    package func _makeLayoutNode() -> any _Layoutable {
        let contentNode: (any _Layoutable)?
        if isPresented.wrappedValue {
            let node = presented._makeLayoutNode()
            contentNode = switch style {
            case .sheet: _SheetSurfaceNode(child: node)
            case .toast: _ToastSurfaceNode(child: node)
            }
        } else {
            contentNode = nil
        }
        return _PresentationLayoutNode(
            base: base._makeLayoutNode(),
            presented: contentNode,
            alignment: alignment,
            isModal: style == .sheet,
            dismiss: {
                guard isPresented.wrappedValue else { return }
                isPresented.wrappedValue = false
                onDismiss?()
            }
        )
    }
}

/// Sheet chrome owns its space explicitly: one border cell and one padding cell
/// on every side. This avoids relying on `.bordered`, whose contract is to use
/// an already allocated area rather than enlarge the view.
private final class _SheetSurfaceNode: _LayoutContainerStorage, _UnaryLayoutable, _RenderableLayoutNode {
    private(set) var frame: Rect = .zero

    init(child: any _Layoutable) {
        super.init(children: [child])
    }

    package func measure(proposed: ProposedSize) -> Size {
        let content = child.measure(
            proposed: ProposedSize(
                width: proposed.width.map { max(0, $0 - 4) },
                height: proposed.height.map { max(0, $0 - 4) }
            )
        )
        return Size(w: content.w + 4, h: content.h + 4)
    }

    package func layout(in rect: Rect) {
        frame = rect
        child.layout(
            in: Rect(
                x: rect.x + 2,
                y: rect.y + 2,
                w: max(0, rect.w - 4),
                h: max(0, rect.h - 4)
            )
        )
    }

    func draw(to canvas: Canvas, environment: EnvironmentValues) {
        canvas.fill(frame, background: .rgb(15, 23, 42))
        canvas.drawBox(
            in: frame,
            style: .rounded,
            foreground: .brightCyan,
            background: .rgb(15, 23, 42)
        )
    }
}

private final class _ToastSurfaceNode: _LayoutContainerStorage, _UnaryLayoutable, _RenderableLayoutNode {
    private(set) var frame: Rect = .zero

    init(child: any _Layoutable) {
        let styled = _EnvironmentNode(child: child) { environment in
            environment.foregroundColor = .black
            environment.backgroundColor = .brightCyan
            environment._isBold = true
        }
        super.init(children: [styled])
    }

    package func measure(proposed: ProposedSize) -> Size {
        let content = child.measure(
            proposed: ProposedSize(
                width: proposed.width.map { max(0, $0 - 2) },
                height: proposed.height
            )
        )
        return Size(w: content.w + 2, h: content.h)
    }

    package func layout(in rect: Rect) {
        frame = rect
        child.layout(
            in: Rect(x: rect.x + 1, y: rect.y, w: max(0, rect.w - 2), h: rect.h)
        )
    }

    func draw(to canvas: Canvas, environment: EnvironmentValues) {
        canvas.fill(frame, background: .brightCyan)
    }
}

private final class _PresentationLayoutNode: _ContainerLayoutNode, _FocusScopeLayoutNode,
    _ModalFocusScopeLayoutNode {
    private let base: any _Layoutable
    private let presented: (any _Layoutable)?
    private let blocker: _KeyPressNode?
    private let alignment: AlignmentEdge
    private let isModal: Bool

    var focusScopeChildren: [any _Layoutable] {
        if isModal, let presented { return [presented] }
        return children
    }

    var isModalFocusScopeActive: Bool {
        isModal && presented != nil
    }

    init(
        base: any _Layoutable,
        presented: (any _Layoutable)?,
        alignment: AlignmentEdge,
        isModal: Bool,
        dismiss: @escaping () -> Void
    ) {
        self.base = base
        self.presented = presented
        self.alignment = alignment
        self.isModal = isModal

        if presented != nil, isModal {
            blocker = _KeyPressNode(child: _ContainerLayoutNode(children: []), keys: nil) { event in
                if event.key == .escape { dismiss() }
                return .handled
            }
        } else {
            blocker = nil
        }

        var children: [any _Layoutable] = [base]
        if let blocker { children.append(blocker) }
        if let presented { children.append(presented) }
        super.init(children: children)
    }

    package override func measure(proposed: ProposedSize) -> Size {
        base.measure(proposed: proposed)
    }

    package override func layout(in rect: Rect) {
        base.layout(in: rect)
        blocker?.layout(in: rect)

        guard let presented else { return }
        let proposal = ProposedSize(width: max(0, rect.w - 2), height: max(0, rect.h - 2))
        let measured = presented.measure(proposed: proposal)
        let size = Size(w: min(rect.w, measured.w), h: min(rect.h, measured.h))
        let origin = alignedOrigin(parent: rect, child: size, alignment: alignment)
        presented.layout(in: Rect(x: origin.x, y: origin.y, w: size.w, h: size.h))
    }
}
