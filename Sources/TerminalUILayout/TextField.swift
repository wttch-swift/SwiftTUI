/// 可编辑单行文本的输入控件。
///
/// 使用 Tab 和 Shift-Tab 在多个输入控件之间切换焦点。光标移动和删除
/// 以 Swift `Character` 为单位，不会拆分中文、emoji 或组合字符。
extension TextField: _LayoutNodeProducing {
    package func _makeLayoutNode() -> any _LayoutNode {
        _TextFieldLayoutNode(
            title: title,
            text: text,
            state: state,
            onEditingChanged: onEditingChanged,
            onCommit: onCommit
        )
    }
}

/// 可以被 FocusState 包装的内部交互目标；目标本身不一定自动加入 Tab 顺序。
package protocol _FocusTargetLayoutNode: _LayoutNode {
    /// 当前节点是否接收由 `TerminalApp` 定向派发的键盘事件。
    var isFocused: Bool { get }

    /// 更新焦点并触发控件自身的焦点变化回调。
    func setFocused(_ focused: Bool)

    /// 处理仅应发送给焦点控件的编辑按键。
    ///
    /// 焦点事件先于普通的 `_KeyPressNode` 冒泡链执行，以防输入字符同时
    /// 触发外层快捷键。返回 `.ignored` 后，事件仍可继续走普通派发流程。
    func handleFocusedKey(_ event: KeyPress) -> KeyPress.Result

    /// 从上一帧中结构位置相同的节点恢复临时交互状态。
    ///
    /// View 树每次重绘都会产生新的 LayoutNode，因此光标和滚动位置不能只
    /// 存在节点本身。这个接口让宿主在新旧节点之间迁移这些非 Binding 状态。
    func restoreInteractionState(from node: any _FocusTargetLayoutNode)

    /// FocusState 修饰符附着时通知目标，使其可关闭未聚焦时的普通按键处理。
    func focusBindingDidAttach()
}

extension _FocusTargetLayoutNode {
    func focusBindingDidAttach() {}
}

/// 无需 FocusState 修饰也会自动参与 Tab 顺序的交互目标。
package protocol _FocusableLayoutNode: _FocusTargetLayoutNode {}

/// `TextField` 跨 LayoutNode 重建周期保留的交互状态。
///
/// 状态使用引用语义，是因为同一个 `TextField` 值可能在一次渲染过程中被
/// 多层 View 包装；所有对应节点都必须观察到相同的光标和焦点变化。
private final class _TextFieldLayoutNode: _RenderReusableLayoutNode, _FocusableLayoutNode,
    _FlexibleLayoutNode {
    let title: String
    let text: Binding<String>
    let state: _TextFieldState
    let onEditingChanged: (Bool) -> Void
    let onCommit: () -> Void
    private(set) var frame: Rect = .zero

    var isFocused: Bool { state.isFocused }
    var expandsHorizontally: Bool { true }
    var expandsVertically: Bool { false }

    init(
        title: String,
        text: Binding<String>,
        state: _TextFieldState,
        onEditingChanged: @escaping (Bool) -> Void,
        onCommit: @escaping () -> Void
    ) {
        self.title = title
        self.text = text
        self.state = state
        self.onEditingChanged = onEditingChanged
        self.onCommit = onCommit
    }

    func measure(proposed: ProposedSize) -> Size {
        // 单行输入框会横向扩展，但固有宽度仍由占位文字和当前内容中较宽者决定。
        let idealWidth = max(1, max(title.displayWidth, text.wrappedValue.displayWidth))
        return Size(
            w: min(idealWidth, proposed.width ?? idealWidth),
            h: min(1, proposed.height ?? 1)
        )
    }

    func layout(in rect: Rect) {
        frame = rect
    }

    func setFocused(_ focused: Bool) {
        guard state.isFocused != focused else { return }
        state.isFocused = focused
        onEditingChanged(focused)
    }

    func restoreInteractionState(from node: any _FocusTargetLayoutNode) {
        // 只接受同类节点，避免不同焦点控件碰巧处于相同遍历位置时互相污染状态。
        guard let previous = node as? _TextFieldLayoutNode else { return }
        state.cursor = previous.state.cursor
        state.scrollIndex = previous.state.scrollIndex
        state.isFocused = previous.state.isFocused
    }

    func handleFocusedKey(_ event: KeyPress) -> KeyPress.Result {
        // 使用 Character 数组进行编辑，保证 emoji、中文和组合字形不会被拆开。
        var characters = Array(text.wrappedValue)
        var cursor = state.clamp(to: characters.count)

        switch event.key {
        case .leftArrow:
            if cursor > 0 { cursor -= 1 }
        case .rightArrow:
            if cursor < characters.count { cursor += 1 }
        case .home:
            cursor = 0
        case .end:
            cursor = characters.count
        case .backspace:
            if cursor > 0 {
                characters.remove(at: cursor - 1)
                cursor -= 1
                text.wrappedValue = String(characters)
            }
        case .delete:
            if cursor < characters.count {
                characters.remove(at: cursor)
                text.wrappedValue = String(characters)
            }
        case .returnKey:
            onCommit()
            return .handled
        case .character where !event.modifiers.contains(.control):
            // 终端解码器可能交付控制片段或零宽片段；只插入实际占用 cell 的文本。
            let inserted = Array(event.characters).filter { character in
                guard let segment = Segment.segment(String(character)).first else { return false }
                return segment.kind == .text && segment.cellLength > 0
            }
            guard !inserted.isEmpty else { return .ignored }
            characters.insert(contentsOf: inserted, at: cursor)
            cursor += inserted.count
            text.wrappedValue = String(characters)
        default:
            return .ignored
        }

        state.cursor = cursor
        return .handled
    }

    func draw(to canvas: Canvas, environment: EnvironmentValues) {
        guard frame.w > 0, frame.h > 0 else { return }
        canvas.withClip(frame) {
            drawClipped(to: canvas, environment: environment)
        }
    }

    private func drawClipped(to canvas: Canvas, environment: EnvironmentValues) {
        let characters = Array(text.wrappedValue)
        let cursor = state.clamp(to: characters.count)
        updateScrollIndex(characters: characters, cursor: cursor, width: frame.w)
        let normalForeground = environment.foregroundColor ?? .white

        if characters.isEmpty {
            // 聚焦时最左侧 cell 留给插入点光标，占位文字从其后开始显示。
            let placeholderX = frame.x + (isFocused ? 1 : 0)
            let placeholderWidth = max(0, frame.w - (isFocused ? 1 : 0))
            let placeholder = title.truncated(toWidth: placeholderWidth)
            canvas.drawText(
                x: placeholderX,
                y: frame.y,
                text: placeholder,
                foreground: .gray,
                background: environment.backgroundColor,
                bold: environment._isBold,
                italic: environment._isItalic,
                underline: environment._isUnderline,
                strikethrough: environment._isStrikethrough
            )
            if isFocused {
                drawCursor(at: frame.x, to: canvas, environment: environment)
            }
            return
        }

        let visible = visibleText(characters: characters, from: state.scrollIndex, width: frame.w)
        canvas.drawText(
            x: frame.x,
            y: frame.y,
            text: visible,
            foreground: normalForeground,
            background: environment.backgroundColor,
            bold: environment._isBold,
            italic: environment._isItalic,
            underline: environment._isUnderline,
            strikethrough: environment._isStrikethrough
        )

        guard isFocused else { return }
        // Character 索引不能直接作为终端 x 坐标，宽字符必须累计真实 cell 宽度。
        let cursorX = frame.x + displayWidth(characters[state.scrollIndex..<cursor])
        guard cursorX < frame.maxX else { return }
        drawCursor(at: cursorX, to: canvas, environment: environment)
    }

    func renderFingerprint(environment: EnvironmentValues) -> Int {
        var hasher = Hasher()
        hasher.combine(title)
        hasher.combine(text.wrappedValue)
        hasher.combine(text.dependencies)
        hasher.combine(state.cursor)
        hasher.combine(state.scrollIndex)
        hasher.combine(state.isFocused)
        hasher.combine(environment.renderFingerprint)
        return hasher.finalize()
    }

    private func updateScrollIndex(characters: [Character], cursor: Int, width: Int) {
        // 光标向左越过窗口时，直接将窗口起点拉回光标位置。
        if cursor < state.scrollIndex {
            state.scrollIndex = cursor
        }

        // 光标位于文本末尾时也需要为插入点保留一个 cell，因此使用 >=。
        while state.scrollIndex < cursor,
              displayWidth(characters[state.scrollIndex..<cursor]) >= width {
            state.scrollIndex += 1
        }

        if cursor < characters.count {
            // 光标覆盖当前字符；若它是宽字符，窗口必须为整个字形留出空间。
            let cursorGlyphWidth = characters[cursor].displayWidth
            while state.scrollIndex < cursor,
                  displayWidth(characters[state.scrollIndex..<cursor]) + cursorGlyphWidth > width {
                state.scrollIndex += 1
            }
        }
    }

    private func visibleText(characters: [Character], from start: Int, width: Int) -> String {
        // 只返回能完整落入视口的字符，避免 Canvas 在边界处画出半个宽字符。
        var result = ""
        var usedWidth = 0
        for character in characters.dropFirst(start) {
            let characterWidth = character.displayWidth
            guard usedWidth + characterWidth <= width else { break }
            result.append(character)
            usedWidth += characterWidth
        }
        return result
    }

    private func displayWidth(_ characters: ArraySlice<Character>) -> Int {
        characters.reduce(0) { $0 + $1.displayWidth }
    }

    private func drawCursor(
        at x: Int,
        to canvas: Canvas,
        environment: EnvironmentValues
    ) {
        // TextField 不绘制背景；使用细竖条模拟文本插入点，避免光标
        // 在带边框输入框里看起来像内容或底边的一部分。
        canvas.drawText(
            x: x,
            y: frame.y,
            text: "▏",
            foreground: environment._focusBorderColor,
            background: environment.backgroundColor,
            bold: environment._isBold,
            italic: environment._isItalic,
            underline: environment._isUnderline,
            strikethrough: environment._isStrikethrough
        )
    }
}
