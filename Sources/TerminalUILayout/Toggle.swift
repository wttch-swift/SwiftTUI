extension Toggle: _LayoutNodeProducing {
    package func _makeLayoutNode() -> any _LayoutNode {
        _ToggleNode(title: title, isOn: isOn)
    }
}

private final class _ToggleNode: _ContainerLayoutNode, _RenderReusableLayoutNode {
    let title: String
    let isOn: Binding<Bool>

    init(title: String, isOn: Binding<Bool>) {
        self.title = title
        self.isOn = isOn
        super.init(children: [])
    }

    package override func measure(proposed: ProposedSize) -> Size {
        Size(w: min(proposed.width ?? Int.max, title.displayWidth + 4), h: 1)
    }

    func draw(to canvas: Canvas, environment: EnvironmentValues) {
        let mark = isOn.wrappedValue ? "x" : " "
        canvas.drawText(
            x: frame.x,
            y: frame.y,
            text: "[\(mark)] \(title)",
            foreground: environment.foregroundColor ?? .white,
            background: environment.backgroundColor,
            bold: environment._isBold,
            italic: environment._isItalic,
            underline: environment._isUnderline,
            strikethrough: environment._isStrikethrough
        )
    }

    func renderFingerprint(environment: EnvironmentValues) -> Int {
        var hasher = Hasher()
        hasher.combine(title)
        hasher.combine(isOn.wrappedValue)
        hasher.combine(isOn.dependencies)
        hasher.combine(environment.renderFingerprint)
        return hasher.finalize()
    }
}
