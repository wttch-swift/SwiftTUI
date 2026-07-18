import Foundation
import TerminalUIFoundation
import TerminalUILayout
import TerminalUIRender

/// A one-way View → LayoutNode → Render → Canvas host.
public final class TerminalApp {
    private var width: Int
    private var height: Int
    private let root: any View
    private var signalHandler: ((TerminalSignal) -> Void)?
    private var renderedRoot: (any _LayoutNode)?
    private var focusedNodeIndex: Int?
    /// 区分“尚未选择过焦点”和“用户按 Esc 主动清空焦点”。
    private var didInitializeFocus = false
    private var isModalFocusScopeActive = false

    public init<Content: View>(width: Int, height: Int, @ViewBuilder content: () -> Content) {
        self.width = width
        self.height = height
        self.root = ZStack(content)
    }

    /// Observes terminal lifecycle signals on TerminalApp's main event loop.
    ///
    /// The callback runs after the POSIX signal has been converted to a regular
    /// runtime event, so it may update `@State` or post TerminalStateRuntime
    /// actions. TerminalApp still performs mandatory terminal cleanup, suspend,
    /// resume and resize behavior after notifying the callback.
    @discardableResult
    public func onSignal(_ handler: @escaping (TerminalSignal) -> Void) -> TerminalApp {
        signalHandler = handler
        return self
    }

    /// 构建并渲染一帧。该入口只供包内 demo 与测试使用；外部客户端通过
    /// `run()` 启动应用，不直接接触 Canvas 和布局树。
    package func render() -> Canvas {
        let canvas = Canvas(width: width, height: height)
        render(to: canvas, cache: nil)
        return canvas
    }

    private func render(to canvas: Canvas, cache: RenderCache?) {
        let bounds = Rect(x: 0, y: 0, w: width, h: height)
        let node = root._makeLayoutNode()
        // GeometryReader 这类节点会在 layout 阶段才按最终尺寸展开子树。焦点与
        // 滚动状态都必须在这之后迁移，否则聊天页这类 GeometryReader 内的
        // ScrollView 会在焦点遍历时不可见，表现成 Tab 怎么也进不去。
        restoreTabSelection(from: renderedRoot, to: node)
        node.layout(in: bounds)
        restoreInteractionState(from: renderedRoot, to: node)
        synchronizeFocus(in: node)
        node.layout(in: bounds)
        Render.drawLaidOut(node, to: canvas, cache: cache)
        renderedRoot = node
    }

    /// 向当前布局树注入按键。子节点优先，未处理时向外层冒泡。
    /// 该入口供包内终端循环与交互测试调用。
    @discardableResult
    package func send(_ event: KeyPress) -> KeyPress.Result {
        switch dispatchKeyEvent(event) {
        case .handled, .requestRender: return .handled
        case .ignored: return .ignored
        }
    }

    private func dispatchKeyEvent(_ event: KeyPress) -> TerminalEventResult {
        let node = renderedRoot ?? root._makeLayoutNode()
        synchronizeFocus(in: node)

        if event.key == .tab {
            // Tab 属于宿主级焦点导航，不交给当前输入框写入或外层快捷键处理。
            return moveFocus(in: node, backwards: event.modifiers.contains(.shift)).terminalEventResult
        }

        // TabView 的左右切换属于容器级导航，优先于 TextField 的光标移动。
        // 模态 presentation 会通过 focus scope 隔离底层 TabView，因此弹窗
        // 打开时不会意外切换页面。
        if event.key == .leftArrow || event.key == .rightArrow,
           let tab = tabNavigationNodes(in: node).last {
            return tab.handleTabNavigation(event).terminalEventResult
        }

        let focusable = focusableNodes(in: node)
        if event.key == .escape,
           let index = focusedNodeIndex,
           focusable.indices.contains(index) {
            // Esc 只退出当前输入状态，不向外层快捷键继续冒泡。
            focusable[index].setFocused(false)
            focusedNodeIndex = nil
            didInitializeFocus = true
            return .handled
        }

        // 编辑事件优先发送给焦点节点；未消费的事件仍允许沿普通节点树冒泡。
        if let index = focusedNodeIndex, focusable.indices.contains(index),
           case .handled = focusable[index].handleFocusedKey(event) {
            return .handled
        }
        return dispatch(.key(event), to: node)
    }

    /// 进入终端事件循环，监听按键并在状态变化后重绘。
    ///
    /// 使用 POSIX termios，不依赖 Combine；支持 macOS 与 Linux 终端。
    public func run(clearScreen: Bool = true) throws {
        let input = _TerminalInput()
        try input.start()
        // 终端颜色能力在一次运行期间保持不变。ProcessInfo.environment 的构造
        // 成本很高，不能在每次按键重绘时通过 `.current` 重复检测。
        let colorSupport = TerminalColorSupport.current

        let events = _TerminalAppEventQueue()
        let signals = _TerminalSignalCoordinator()
        TerminalStateRuntime.setEventHandler { events.push(.state($0)) }
        signals.start { events.push(.terminal(.signal($0))) }

        defer {
            TerminalStateRuntime.setEventHandler(nil)
            input.stop()
            leaveTerminalScreen(clearScreen: clearScreen)
            // Restore the embedding process's original signal dispositions only
            // after the terminal is safe for the shell again.
            signals.stop()
        }

        enterTerminalScreen(clearScreen: clearScreen)

        var isRunning = true
        var needsRender = true
        // 双缓冲负责复用两张 Canvas，并用上一帧 presented 生成按行 diff 输出。
        // RenderCache 负责复用 View 叶子节点绘制快照。两者分工独立：前者减少
        // 画布分配和终端输出，后者减少重复 draw。
        var canvasBuffer = CanvasDoubleBuffer(width: width, height: height)
        let renderCache = RenderCache()

        while isRunning {
            if needsRender {
                if clearScreen {
                    // 使用绝对行坐标重绘，不依赖 \n 推进光标。终端底部的换行
                    // 可能触发滚屏，导致最后一行状态栏被卷到画面顶部。
                    // 这里的闭包只负责把当前帧画到 drawing buffer；renderOutput
                    // 会在闭包结束后和上一帧比较，并交换 presented/drawing。
                    let output = canvasBuffer.renderOutput(colorSupport: colorSupport) { canvas in
                        render(to: canvas, cache: renderCache)
                    }
                    if !output.isEmpty {
                        writeTerminal(output)
                    }
                } else {
                    let canvas = render()
                    canvas.flush(terminatingLine: false)
                }
                needsRender = false
            }

            // 较短轮询周期使后台动画请求能及时进入主循环，同时 poll 在无输入时
            // 仍会休眠，不会产生忙等待。
            if let key = try input.readKey(timeoutMilliseconds: 16) {
                events.push(.terminal(.key(key)))
            }

            while let event = events.pop() {
                switch event {
                case .state(let stateEvent):
                    switch stateEvent {
                    case .renderRequested:
                        needsRender = true
                    case .action(let action):
                        action()
                        needsRender = true
                    case .stopRequested:
                        isRunning = false
                    }
                case .terminal(let terminalEvent):
                    switch terminalEvent {
                    case .key(let key):
                        if dispatchKeyEvent(key).consumesEvent {
                            needsRender = true
                        }
                    case .signal(let signal):
                        if dispatch(terminalEvent).requestsRender {
                            needsRender = true
                        }
                        signalHandler?(signal)
                        switch signal {
                        case .interrupt, .terminate, .hangup, .quit:
                            // Leave the loop normally so defer always restores termios
                            // and screen modes before control returns to the caller.
                            isRunning = false
                        case .suspend:
                            // Shell must regain a cooked, visible terminal while this
                            // process is stopped. raise(SIGTSTP) returns after `fg`.
                            input.stop()
                            leaveTerminalScreen(clearScreen: clearScreen)
                            signals.suspendCurrentProcess()
                            try input.start()
                            enterTerminalScreen(clearScreen: clearScreen)
                            if let size = updateTerminalSize(),
                               dispatch(.resize(size)).requestsRender {
                                needsRender = true
                            }
                            // 终端恢复后尺寸和内容都可能和暂停前不同，直接丢弃双缓冲
                            // 与渲染缓存，让下一帧走完整重建。
                            canvasBuffer = CanvasDoubleBuffer(width: width, height: height)
                            renderCache.reset()
                            needsRender = true
                        case .resume:
                            // A SIGCONT may also arrive independently of our suspend
                            // path. A full redraw is harmless and repairs stale output.
                            if let size = updateTerminalSize(),
                               dispatch(.resize(size)).requestsRender {
                                needsRender = true
                            }
                            // 恢复信号可能不是从本进程 suspend 流程回来，保守地清掉
                            // 上一帧画布和节点快照。
                            canvasBuffer = CanvasDoubleBuffer(width: width, height: height)
                            renderCache.reset()
                            needsRender = true
                        case .windowSizeChanged:
                            if let size = updateTerminalSize(),
                               dispatch(.resize(size)).requestsRender {
                                needsRender = true
                            }
                            if clearScreen {
                                writeTerminal("\u{001B}[2J\u{001B}[H")
                            }
                            // 尺寸变化会让 frame、行数和列数全部失效；旧 Canvas diff
                            // 和旧节点 snapshot 都不能继续复用。
                            canvasBuffer = CanvasDoubleBuffer(width: width, height: height)
                            renderCache.reset()
                            needsRender = true
                        }
                    case .resize, .message:
                        if dispatch(terminalEvent).requestsRender {
                            needsRender = true
                        }
                    }
                }
            }
        }
    }

    private func dispatch(_ event: TerminalEvent) -> TerminalEventResult {
        let node = renderedRoot ?? root._makeLayoutNode()
        synchronizeFocus(in: node)
        return dispatch(event, to: node)
    }

    private func dispatch(_ event: TerminalEvent, to node: any _LayoutNode) -> TerminalEventResult {
        if let container = node as? _ContainerLayoutNode {
            for child in container.children.reversed() {
                let result = dispatch(event, to: child)
                if result.consumesEvent {
                    return result
                }
            }
        }

        if let handler = node as? any _TerminalEventHandlingNode {
            return handler.handle(event)
        }
        return .ignored
    }

    private func synchronizeFocus(in root: any _LayoutNode) {
        let modalFocusScopeActive = containsActiveModalFocusScope(in: root)
        if modalFocusScopeActive != isModalFocusScopeActive {
            focusedNodeIndex = nil
            didInitializeFocus = false
            isModalFocusScopeActive = modalFocusScopeActive
        }

        let nodes = focusableNodes(in: root)
        guard !nodes.isEmpty else {
            focusedNodeIndex = nil
            return
        }

        let boundIndices = nodes.indices.filter {
            nodes[$0] is any _FocusBindingLayoutNode
        }
        if let requested = boundIndices.first(where: {
            (nodes[$0] as? any _FocusBindingLayoutNode)?.requestsFocus == true
        }) {
            // FocusState 是权威来源，程序化赋值会在下一帧选择对应节点。
            focusedNodeIndex = requested
            didInitializeFocus = true
        } else if !boundIndices.isEmpty {
            // 普通页面里，FocusState 全为空表示显式无焦点；但 modal sheet 是新的
            // 焦点范围，打开时应自动进入第一个字段，否则第一次 Tab 看起来像被吞。
            focusedNodeIndex = modalFocusScopeActive && !didInitializeFocus
                ? boundIndices.first
                : nil
            didInitializeFocus = true
        } else if !didInitializeFocus {
            // 首次出现焦点节点时默认选择第一个，保持现有 TextField 使用体验。
            focusedNodeIndex = 0
            didInitializeFocus = true
        } else if let index = focusedNodeIndex {
            // 节点减少时把已有索引夹到新范围内；nil 则表示用户主动取消焦点。
            focusedNodeIndex = min(nodes.count - 1, max(0, index))
        }
        for (index, node) in nodes.enumerated() {
            node.setFocused(index == focusedNodeIndex)
        }
    }

    private func containsActiveModalFocusScope(in node: any _LayoutNode) -> Bool {
        if (node as? any _ModalFocusScopeLayoutNode)?.isModalFocusScopeActive == true {
            return true
        }
        guard let container = node as? _ContainerLayoutNode else { return false }
        return container.children.contains(where: containsActiveModalFocusScope)
    }

    private func moveFocus(in root: any _LayoutNode, backwards: Bool) -> KeyPress.Result {
        let nodes = focusableNodes(in: root)
        guard !nodes.isEmpty else { return .ignored }
        let next: Int
        if let focusedNodeIndex {
            let current = min(nodes.count - 1, max(0, focusedNodeIndex))
            // 首尾相接，与 SwiftUI 表单中常见的 Tab / Shift-Tab 导航保持一致。
            next = backwards
                ? (current - 1 + nodes.count) % nodes.count
                : (current + 1) % nodes.count
        } else {
            // 无焦点时，Tab 从开头进入，Shift-Tab 从末尾反向进入。
            next = backwards ? nodes.count - 1 : 0
        }
        focusedNodeIndex = next
        didInitializeFocus = true
        for (index, node) in nodes.enumerated() {
            node.setFocused(index == next)
        }
        return .handled
    }

    private func restoreInteractionState(
        from previousRoot: (any _LayoutNode)?,
        to currentRoot: any _LayoutNode
    ) {
        guard let previousRoot else { return }
        let previous = focusTargetNodes(in: previousRoot)
        let current = focusTargetNodes(in: currentRoot)
        // 当前没有稳定 View identity，暂以深度优先遍历顺序配对。插入或删除焦点
        // 节点时，同步焦点会再校正索引；未来引入 identity 后可替换此配对策略。
        for (old, new) in zip(previous, current) {
            new.restoreInteractionState(from: old)
        }
    }

    private func restoreTabSelection(
        from previousRoot: (any _LayoutNode)?,
        to currentRoot: any _LayoutNode
    ) {
        guard let previousRoot else { return }
        for (old, new) in zip(tabSelectionNodes(in: previousRoot), tabSelectionNodes(in: currentRoot)) {
            new.restoreSelection(from: old.selectedIndex)
        }
    }

    private func tabSelectionNodes(in node: any _LayoutNode) -> [any _TabSelectionNode] {
        var result: [any _TabSelectionNode] = []
        if let tab = node as? any _TabSelectionNode { result.append(tab) }
        if let container = node as? _ContainerLayoutNode {
            for child in container.children {
                result.append(contentsOf: tabSelectionNodes(in: child))
            }
        }
        return result
    }

    private func tabNavigationNodes(in node: any _LayoutNode) -> [any _TabNavigationNode] {
        var result: [any _TabNavigationNode] = []
        if let tab = node as? any _TabNavigationNode { result.append(tab) }
        if let container = node as? _ContainerLayoutNode {
            let children = (node as? any _FocusScopeLayoutNode)?.focusScopeChildren
                ?? container.children
            for child in children {
                result.append(contentsOf: tabNavigationNodes(in: child))
            }
        }
        return result
    }

    private func focusableNodes(in node: any _LayoutNode) -> [any _FocusableLayoutNode] {
        // 使用与布局树声明顺序一致的前序遍历，确保 Tab 顺序稳定且可预测。
        // FocusState 包装节点是焦点边界，其内部 TextField 不重复加入列表。
        if let binding = node as? any _FocusBindingLayoutNode {
            return [binding]
        }
        var result: [any _FocusableLayoutNode] = []
        if let focusable = node as? any _FocusableLayoutNode {
            result.append(focusable)
        }
        if let container = node as? _ContainerLayoutNode {
            let children = (node as? any _FocusScopeLayoutNode)?.focusScopeChildren
                ?? container.children
            for child in children {
                result.append(contentsOf: focusableNodes(in: child))
            }
        }
        return result
    }

    private func focusTargetNodes(in node: any _LayoutNode) -> [any _FocusTargetLayoutNode] {
        // FocusState 包装节点是交互状态边界；恢复它即可由包装节点转发给内部目标，
        // 不再继续递归，避免同一个 TextField 被恢复两次。
        if let binding = node as? any _FocusBindingLayoutNode {
            return [binding]
        }
        var result: [any _FocusTargetLayoutNode] = []
        if let focusTarget = node as? any _FocusTargetLayoutNode {
            result.append(focusTarget)
        }
        if let container = node as? _ContainerLayoutNode {
            let children = (node as? any _FocusScopeLayoutNode)?.focusScopeChildren
                ?? container.children
            for child in children {
                result.append(contentsOf: focusTargetNodes(in: child))
            }
        }
        return result
    }

    private func writeTerminal(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        FileHandle.standardOutput.write(data)
    }

    private func enterTerminalScreen(clearScreen: Bool) {
        guard clearScreen else { return }
        // DECAWM (?7) controls automatic wrapping. Writing the bottom-right cell
        // with wrapping enabled can scroll the terminal before the next frame.
        writeTerminal("\u{001B}[?7l\u{001B}[2J\u{001B}[H\u{001B}[?25l")
    }

    private func leaveTerminalScreen(clearScreen: Bool) {
        guard clearScreen else { return }
        // Restore automatic wrapping and cursor visibility for the shell.
        writeTerminal("\u{001B}[?7h\u{001B}[?25h")
    }

    private func updateTerminalSize() -> TerminalSize? {
        guard let size = TerminalSizeReader.current() else { return nil }
        width = size.width
        height = size.height
        return size
    }
}

private enum _TerminalAppRuntimeEvent {
    case state(TerminalAppEvent)
    case terminal(TerminalEvent)
}

private final class _TerminalAppEventQueue: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [_TerminalAppRuntimeEvent] = []

    func push(_ event: _TerminalAppRuntimeEvent) {
        lock.lock()
        events.append(event)
        lock.unlock()
    }

    func pop() -> _TerminalAppRuntimeEvent? {
        lock.lock()
        defer { lock.unlock() }
        guard !events.isEmpty else { return nil }
        return events.removeFirst()
    }
}

private extension KeyPress.Result {
    var terminalEventResult: TerminalEventResult {
        switch self {
        case .handled: .handled
        case .ignored: .ignored
        }
    }
}

private extension TerminalEventResult {
    var requestsRender: Bool {
        switch self {
        case .requestRender: true
        case .handled, .ignored: false
        }
    }
}
