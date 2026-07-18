/// 滚动视图使用的坐标轴。
extension ScrollView: _LayoutNodeProducing {
    package func _makeLayoutNode() -> any _Layoutable {
        let scrollNode = _ScrollViewLayoutNode(
            child: content._makeLayoutNode(),
            axes: axes,
            showsIndicators: showsIndicators,
            state: state
        )
        // 滚动键处理放在内容节点外层：内层可交互控件先处理按键，
        // 它们返回 ignored 时事件才冒泡给 ScrollView。
        return _KeyPressNode(
            child: scrollNode,
            keys: [.upArrow, .downArrow, .leftArrow, .rightArrow, .home, .end, .pageUp, .pageDown]
        ) { event in
            guard !state.isFocusManaged || state.isFocused else { return .ignored }
            return state.handle(event, axes: axes)
        }
    }
}

/// 滚动交互状态。偏移与尺寸放在同一对象中，使按键处理可以在
/// 不依赖具体布局节点实例的情况下读取最新可滚动范围。
extension _ScrollViewState {
    /// 布局完成后刷新滚动边界，并在终端缩放或内容变短后
    /// 把旧偏移钳制回新范围，避免视口停留在空白区域。
    func update(viewport: Size, content: Size) {
        viewportWidth = viewport.w
        viewportHeight = viewport.h
        contentWidth = content.w
        contentHeight = content.h
        maximumX = max(0, content.w - viewport.w)
        maximumY = max(0, content.h - viewport.h)
        offsetX = min(maximumX, max(0, offsetX))
        offsetY = min(maximumY, max(0, offsetY))
    }

    /// 将按键转换为偏移。到达边界后返回 `.ignored`，
    /// 使嵌套 ScrollView 可以继续向外层冒泡同一方向的滚动键。
    func handle(_ event: KeyPress, axes: Axis.Set) -> KeyPress.Result {
        let previousX = offsetX
        let previousY = offsetY

        switch event.key {
        case .upArrow where axes.contains(.vertical):
            offsetY -= 1
        case .downArrow where axes.contains(.vertical):
            offsetY += 1
        case .leftArrow where axes.contains(.horizontal):
            offsetX -= 1
        case .rightArrow where axes.contains(.horizontal):
            offsetX += 1
        case .pageUp where axes.contains(.vertical):
            offsetY -= max(1, viewportHeight - 1)
        case .pageDown where axes.contains(.vertical):
            offsetY += max(1, viewportHeight - 1)
        case .home:
            if axes.contains(.vertical) { offsetY = 0 }
            if axes.contains(.horizontal) { offsetX = 0 }
        case .end:
            if axes.contains(.vertical) { offsetY = maximumY }
            if axes.contains(.horizontal) { offsetX = maximumX }
        default:
            return .ignored
        }

        offsetX = min(maximumX, max(0, offsetX))
        offsetY = min(maximumY, max(0, offsetY))
        return offsetX == previousX && offsetY == previousY ? .ignored : .handled
    }
}

/// 滚动布局节点。`children[0]` 是可移动内容，`children[1]` 是固定在视口
/// 之上的滚动指示器。整棵子树通过 `_ClippingLayoutNode` 被裁剪到 `frame`。
private final class _ScrollViewLayoutNode: _ContainerLayoutNode, _ClippingLayoutNode,
    _FocusTargetLayoutNode {
    let child: any _Layoutable
    let axes: Axis.Set
    let state: _ScrollViewState
    private(set) var frame: Rect = .zero
    var clipRect: Rect { frame }
    var isFocused: Bool { state.isFocused }

    init(
        child: any _Layoutable,
        axes: Axis.Set,
        showsIndicators: Bool,
        state: _ScrollViewState
    ) {
        self.child = child
        self.axes = axes
        self.state = state
        let indicator = _ScrollIndicatorNode(state: state, axes: axes, isVisible: showsIndicators)
        super.init(children: [child, indicator])
    }

    /// 测量内容时，可滚动轴收到 `nil` proposal，从而报告完整内容尺寸；
    /// 非滚动轴仍受视口约束。ScrollView 本身优先接受父容器建议的视口尺寸。
    package override func measure(proposed: ProposedSize) -> Size {
        let contentSize = child.measure(
            proposed: ProposedSize(
                width: axes.contains(.horizontal) ? nil : proposed.width,
                height: axes.contains(.vertical) ? nil : proposed.height
            )
        )
        return Size(
            w: proposed.width ?? contentSize.w,
            h: proposed.height ?? contentSize.h
        )
    }

    /// 把内容以“完整内容尺寸”布局，再用负偏移移到视口后方。
    /// 指示器始终使用未偏移的 `rect`，因此看起来固定在视口边缘。
    package override func layout(in rect: Rect) {
        frame = rect
        let measured = child.measure(
            proposed: ProposedSize(
                width: axes.contains(.horizontal) ? nil : rect.w,
                height: axes.contains(.vertical) ? nil : rect.h
            )
        )
        let contentSize = Size(
            w: axes.contains(.horizontal) ? max(rect.w, measured.w) : rect.w,
            h: axes.contains(.vertical) ? max(rect.h, measured.h) : rect.h
        )
        state.update(viewport: Size(w: rect.w, h: rect.h), content: contentSize)
        child.layout(
            in: Rect(
                x: rect.x - state.offsetX,
                y: rect.y - state.offsetY,
                w: contentSize.w,
                h: contentSize.h
            )
        )
        children[1].layout(in: rect)
    }

    func focusBindingDidAttach() {
        state.isFocusManaged = true
    }

    func setFocused(_ focused: Bool) {
        state.isFocused = focused
    }

    func handleFocusedKey(_ event: KeyPress) -> KeyPress.Result {
        state.handle(event, axes: axes)
    }

    func restoreInteractionState(from node: any _FocusTargetLayoutNode) {
        guard let previous = node as? _ScrollViewLayoutNode else { return }
        state.offsetX = previous.state.offsetX
        state.offsetY = previous.state.offsetY
        state.isFocused = previous.state.isFocused
        state.isFocusManaged = previous.state.isFocusManaged
    }
}

/// 不参与尺寸分配的覆盖层，在内容之后绘制以保证指示器可见。
private final class _ScrollIndicatorNode: _RenderableLayoutNode {
    let state: _ScrollViewState
    let axes: Axis.Set
    let isVisible: Bool
    private(set) var frame: Rect = .zero

    init(state: _ScrollViewState, axes: Axis.Set, isVisible: Bool) {
        self.state = state
        self.axes = axes
        self.isVisible = isVisible
    }

    func measure(proposed: ProposedSize) -> Size { .zero }
    func layout(in rect: Rect) { frame = rect }

    func draw(to canvas: Canvas, environment: EnvironmentValues) {
        guard isVisible else { return }
        let foreground = state.isFocused
            ? environment._focusBorderColor
            : environment.foregroundColor ?? .gray

        if axes.contains(.vertical), state.maximumY > 0, frame.w > 0, frame.h > 0 {
            // thumb/view = viewport/content，因此 thumb = viewport²/content。
            // thumbStart 再把内容偏移线性映射到指示器可移动的 travel 范围。
            let thumbLength = max(1, frame.h * frame.h / max(1, state.contentHeight))
            let travel = max(0, frame.h - thumbLength)
            let thumbStart = state.maximumY > 0 ? state.offsetY * travel / state.maximumY : 0
            for offset in 0..<frame.h {
                canvas.drawText(
                    x: frame.maxX - 1,
                    y: frame.y + offset,
                    text: offset >= thumbStart && offset < thumbStart + thumbLength ? "█" : "│",
                    foreground: foreground,
                    background: environment.backgroundColor
                )
            }
        }

        if axes.contains(.horizontal), state.maximumX > 0, frame.w > 0, frame.h > 0 {
            // 水平指示器使用与纵向相同的比例与偏移映射。
            let thumbLength = max(1, frame.w * frame.w / max(1, state.contentWidth))
            let travel = max(0, frame.w - thumbLength)
            let thumbStart = state.maximumX > 0 ? state.offsetX * travel / state.maximumX : 0
            for offset in 0..<frame.w {
                canvas.drawText(
                    x: frame.x + offset,
                    y: frame.maxY - 1,
                    text: offset >= thumbStart && offset < thumbStart + thumbLength ? "█" : "─",
                    foreground: foreground,
                    background: environment.backgroundColor
                )
            }
        }
    }
}
