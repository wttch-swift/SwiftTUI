import Foundation
import TerminalUILayout
import TerminalUIRender

/// A one-way View → LayoutNode → Render → Canvas host.
public final class TerminalApp {
    private let width: Int
    private let height: Int
    private let root: any View
    private var renderedRoot: (any _LayoutNode)?
    private var focusedNodeIndex: Int?
    /// 区分“尚未选择过焦点”和“用户按 Esc 主动清空焦点”。
    private var didInitializeFocus = false

    public init<Content: View>(width: Int, height: Int, @ViewBuilder content: () -> Content) {
        self.width = width
        self.height = height
        self.root = ZStack(content)
    }

    /// 构建并渲染一帧。该入口只供包内 demo 与测试使用；外部客户端通过
    /// `run()` 启动应用，不直接接触 Canvas 和布局树。
    package func render() -> Canvas {
        let canvas = Canvas(width: width, height: height)
        let bounds = Rect(x: 0, y: 0, w: width, h: height)
        let node = root._makeLayoutNode()
        // 声明式 View 每帧都会生成新节点，先迁移交互状态，再统一校正焦点。
        restoreFocusableState(from: renderedRoot, to: node)
        restoreTabSelection(from: renderedRoot, to: node)
        synchronizeFocus(in: node)
        Render.render(node, in: bounds, to: canvas)
        renderedRoot = node
        return canvas
    }

    /// 向当前布局树注入按键。子节点优先，未处理时向外层冒泡。
    /// 该入口供包内终端循环与交互测试调用。
    @discardableResult
    package func send(_ event: KeyPress) -> KeyPress.Result {
        let node = renderedRoot ?? root._makeLayoutNode()
        synchronizeFocus(in: node)

        if event.key == .tab {
            // Tab 属于宿主级焦点导航，不交给当前输入框写入或外层快捷键处理。
            return moveFocus(in: node, backwards: event.modifiers.contains(.shift))
        }

        // TabView 的左右切换属于容器级导航，优先于 TextField 的光标移动。
        // 模态 presentation 会通过 focus scope 隔离底层 TabView，因此弹窗
        // 打开时不会意外切换页面。
        if event.key == .leftArrow || event.key == .rightArrow,
           let tab = tabNavigationNodes(in: node).last {
            return tab.handleTabNavigation(event)
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
        return dispatch(event, to: node)
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
        TerminalStateRuntime.setEventHandler { events.push($0) }

        defer {
            TerminalStateRuntime.setEventHandler(nil)
            input.stop()
            if clearScreen {
                // 恢复自动换行和光标显示，避免影响应用退出后的 shell。
                writeTerminal("\u{001B}[?7h\u{001B}[?25h")
            }
        }

        if clearScreen {
            // DECAWM (?7) 控制终端的自动换行。全屏画布会写到右下角，若保持
            // 自动换行，终端可能进入 pending-wrap 状态，并在下一帧开始时先
            // 滚屏一行，造成状态栏末尾跑到左上角以及前几行错位。
            writeTerminal("\u{001B}[?7l\u{001B}[2J\u{001B}[H\u{001B}[?25l")
        }

        var isRunning = true
        var needsRender = true
        var presentedCanvas: Canvas?

        while isRunning {
            if needsRender {
                let canvas = render()
                if clearScreen {
                    // 使用绝对行坐标重绘，不依赖 \n 推进光标。终端底部的换行
                    // 可能触发滚屏，导致最后一行状态栏被卷到画面顶部。
                    let output = canvas.positionedOutput(
                        comparedTo: presentedCanvas,
                        colorSupport: colorSupport
                    )
                    if !output.isEmpty {
                        writeTerminal(output)
                    }
                    presentedCanvas = canvas
                } else {
                    canvas.flush(terminatingLine: false)
                }
                needsRender = false
            }

            // 较短轮询周期使后台动画请求能及时进入主循环，同时 poll 在无输入时
            // 仍会休眠，不会产生忙等待。
            if let key = try input.readKey(timeoutMilliseconds: 16) {
                if case .handled = send(key) {
                    needsRender = true
                }
            }

            while let event = events.pop() {
                switch event {
                case .renderRequested:
                    needsRender = true
                case .action(let action):
                    action()
                    needsRender = true
                case .stopRequested:
                    isRunning = false
                }
            }
        }
    }

    private func dispatch(_ event: KeyPress, to node: any _LayoutNode) -> KeyPress.Result {
        if let container = node as? _ContainerLayoutNode {
            for child in container.children.reversed() {
                if case .handled = dispatch(event, to: child) {
                    return .handled
                }
            }
        }

        if let handler = node as? any _KeyPressHandlingNode {
            return handler.handle(event)
        }
        return .ignored
    }

    private func synchronizeFocus(in root: any _LayoutNode) {
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
            // 存在 FocusState 修饰但没有值请求焦点时，保持全局失焦。
            focusedNodeIndex = nil
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

    private func restoreFocusableState(
        from previousRoot: (any _LayoutNode)?,
        to currentRoot: any _LayoutNode
    ) {
        guard let previousRoot else { return }
        let previous = focusableNodes(in: previousRoot)
        let current = focusableNodes(in: currentRoot)
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

    private func writeTerminal(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        FileHandle.standardOutput.write(data)
    }
}

private final class _TerminalAppEventQueue: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [TerminalAppEvent] = []

    func push(_ event: TerminalAppEvent) {
        lock.lock()
        events.append(event)
        lock.unlock()
    }

    func pop() -> TerminalAppEvent? {
        lock.lock()
        defer { lock.unlock() }
        guard !events.isEmpty else { return nil }
        return events.removeFirst()
    }
}
