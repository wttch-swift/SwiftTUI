#if os(Windows)
import Dispatch
import WinSDK

private let windowsEventQueue = DispatchQueue(label: "TerminalUI.windows.events")

private typealias ConsoleCtrlHandlerRoutine = @convention(c) (_ dwCtrlType: DWORD) -> WindowsBool

private enum WindowsConsoleDispatcher {
    nonisolated(unsafe) static var currentHandler: ((DWORD) -> Bool)?

    static let callback: ConsoleCtrlHandlerRoutine = { ctrlType in
        let response = currentHandler?(ctrlType) ?? true
        return WindowsBool(response)
    }
}

/// Windows 控制台平台后端:一个类同时承载输入、信号、尺寸读取与输出准备。
///
/// 输入侧用 `GetConsoleMode` / `SetConsoleMode` 切换原始模式,`ReadConsoleInputW`
/// 读取 KEY_EVENT;信号侧把 `CTRL_C_EVENT` 等控制台事件映射为统一 `TerminalSignal`;
/// 尺寸用 `GetConsoleScreenBufferInfo` 读取;输出侧对标准输出句柄显式开启
/// `ENABLE_VIRTUAL_TERMINAL_PROCESSING`,否则 conhost 不会渲染 ANSI 颜色序列。
final class _TerminalPlatformWindows: _TerminalPlatformBackend {
    // MARK: - 尺寸读取(静态)

    static func currentSize(fileDescriptor: Int32?) -> TerminalSize? {
        let handle = GetStdHandle(STD_OUTPUT_HANDLE)
        guard handle != INVALID_HANDLE_VALUE else { return nil }

        var consoleInfo = CONSOLE_SCREEN_BUFFER_INFO()
        guard GetConsoleScreenBufferInfo(handle, &consoleInfo) else { return nil }

        let width = Int(consoleInfo.srWindow.Right - consoleInfo.srWindow.Left + 1)
        let height = Int(consoleInfo.srWindow.Bottom - consoleInfo.srWindow.Top + 1)

        guard width > 0, height > 0 else { return nil }
        return TerminalSize(columns: width, rows: height)
    }

    // MARK: - 输入(console events)

    private let inputHandle: HANDLE
    private var originalInputMode: DWORD = 0
    private var isRaw = false

    // MARK: - 输出(VT 启用)

    private let outputHandle: HANDLE
    private var originalOutputMode: DWORD = 0
    private var didEnableVT = false

    // MARK: - 信号

    private var isSignalsRunning = false
    /// 由 `startSignals` 注入;`readKey` 发现 WINDOW_BUFFER_SIZE_EVENT 时用它同步转成
    /// `.windowSizeChanged`,让主循环走与 Unix SIGWINCH 相同的 resize 处理。
    private var signalHandler: ((TerminalSignal) -> Void)?

    init() {
        self.inputHandle = GetStdHandle(STD_INPUT_HANDLE)
        self.outputHandle = GetStdHandle(STD_OUTPUT_HANDLE)
    }

    func startInput() throws {
        guard inputHandle != INVALID_HANDLE_VALUE else {
            throw TerminalInputError.notTerminal
        }

        guard GetConsoleMode(inputHandle, &originalInputMode) else {
            throw _terminalInputSystemError("GetConsoleMode")
        }

        var mode = originalInputMode
        let disabledFlags: DWORD = DWORD(ENABLE_LINE_INPUT) | DWORD(ENABLE_ECHO_INPUT) | DWORD(ENABLE_PROCESSED_INPUT)
        mode &= ~disabledFlags
        mode |= DWORD(ENABLE_EXTENDED_FLAGS)
        // 报告窗口/缓冲尺寸变化事件(WINDOW_BUFFER_SIZE_EVENT),让 resize 走与
        // Unix SIGWINCH 相同的重布局/重绘路径,否则 `readKey` 永远收不到尺寸变化。
        mode |= DWORD(ENABLE_WINDOW_INPUT)
        // 该实现使用 ReadConsoleInputW 的 KEY_EVENT + wVirtualKeyCode 进行解码。
        // 开启 VT 输入会把方向键转换为 ESC 序列字符流,导致箭头键无法落到
        // decodeWindowsKey 的虚拟键分支,因此这里显式保持关闭。
        mode &= ~DWORD(ENABLE_VIRTUAL_TERMINAL_INPUT)

        guard SetConsoleMode(inputHandle, mode) else {
            throw _terminalInputSystemError("SetConsoleMode")
        }
        isRaw = true
    }

    func stopInput() {
        guard isRaw else { return }
        _ = SetConsoleMode(inputHandle, originalInputMode)
        isRaw = false
    }

    func readKey(timeoutMilliseconds: Int32) throws -> KeyPress? {
        // 循环消费输入记录,直到取到按键或超时。窗口尺寸变化不会作为按键返回,
        // 而是同步转成 `.windowSizeChanged` 信号;鼠标/焦点/菜单等事件直接丢弃。
        while try waitForInput(timeoutMilliseconds: timeoutMilliseconds) {
            var inputRecord = INPUT_RECORD()
            var eventsRead: DWORD = 0

            guard ReadConsoleInputW(inputHandle, &inputRecord, 1, &eventsRead),
                  eventsRead > 0 else {
                return nil
            }

            // WinSDK 的事件类型常量是 Int32,而 `EventType` 是 WORD,先做无损转换。
            switch Int32(inputRecord.EventType) {
            case WINDOW_BUFFER_SIZE_EVENT:
                // 用户拖拽窗口边缘或程序改缓冲/窗口大小时,控制台会排入该事件。
                signalHandler?(.windowSizeChanged)
                continue
            case KEY_EVENT:
                let keyEvent = inputRecord.Event.KeyEvent
                guard keyEvent.bKeyDown != WindowsBool(false) else { continue }

                if keyEvent.uChar.UnicodeChar != 0,
                   let key = Self.decodeWindowsCharacter(keyEvent.uChar.UnicodeChar, controlState: keyEvent.dwControlKeyState) {
                    return key
                }

                if let key = decodeWindowsKey(keyEvent.wVirtualKeyCode, controlState: keyEvent.dwControlKeyState) {
                    return key
                }

                return KeyPress(key: .unknown)
            default:
                // MOUSE_EVENT / FOCUS_EVENT / MENU_EVENT 等非按键事件直接丢弃。
                continue
            }
        }
        return nil
    }

    private func waitForInput(timeoutMilliseconds: Int32) throws -> Bool {
        let handle = GetStdHandle(STD_INPUT_HANDLE)
        let result = WaitForSingleObject(handle, DWORD(timeoutMilliseconds))

        let WAIT_OBJECT_0: DWORD = 0x00000000
        let WAIT_TIMEOUT: DWORD = 0x00000102
        let WAIT_FAILED: DWORD = 0xFFFFFFFF

        switch result {
        case WAIT_OBJECT_0:
            return true
        case WAIT_TIMEOUT:
            return false
        case WAIT_FAILED:
            throw _terminalInputSystemError("WaitForSingleObject")
        default:
            return false
        }
    }

    private func decodeWindowsKey(_ virtualKey: WORD, controlState: DWORD) -> KeyPress? {
        let modifiers = Self.modifiers(from: controlState)

        switch virtualKey {
        case 0x20:
            return KeyPress(key: .character(" "), characters: " ", modifiers: modifiers)
        case 0x08:
            return KeyPress(key: .backspace, modifiers: modifiers)
        case 0x09:
            return KeyPress(key: .tab, characters: "\t", modifiers: modifiers)
        case 0x0D:
            return KeyPress(key: .returnKey, characters: "\n", modifiers: modifiers)
        case 0x1B:
            return KeyPress(key: .escape, characters: "\u{1B}", modifiers: modifiers)
        case 0x2E:
            return KeyPress(key: .delete, modifiers: modifiers)
        case 0x26:
            return KeyPress(key: .upArrow, modifiers: modifiers)
        case 0x28:
            return KeyPress(key: .downArrow, modifiers: modifiers)
        case 0x25:
            return KeyPress(key: .leftArrow, modifiers: modifiers)
        case 0x27:
            return KeyPress(key: .rightArrow, modifiers: modifiers)
        case 0x24:
            return KeyPress(key: .home, modifiers: modifiers)
        case 0x23:
            return KeyPress(key: .end, modifiers: modifiers)
        case 0x21:
            return KeyPress(key: .pageUp, modifiers: modifiers)
        case 0x22:
            return KeyPress(key: .pageDown, modifiers: modifiers)
        case 0x2D:
            return KeyPress(key: .unknown, modifiers: modifiers)
        default:
            return nil
        }
    }

    static func decodeWindowsCharacter(_ character: WCHAR, controlState: DWORD) -> KeyPress? {
        let modifiers = modifiers(from: controlState)

        switch UInt16(character) {
        case 0x08:
            return KeyPress(key: .backspace, modifiers: modifiers)
        case 0x09:
            return KeyPress(key: .tab, characters: "\t", modifiers: modifiers)
        case 0x0A, 0x0D:
            return KeyPress(key: .returnKey, characters: "\n", modifiers: modifiers)
        case 0x1B:
            return KeyPress(key: .escape, characters: "\u{1B}", modifiers: modifiers)
        case 0x7F:
            return KeyPress(key: .delete, modifiers: modifiers)
        case 0x20:
            return KeyPress(key: .character(" "), characters: " ", modifiers: modifiers)
        default:
            if let scalar = UnicodeScalar(UInt16(character)) {
                let text = String(Character(scalar))
                let value = Character(scalar)
                let isControlKey = (controlState & (0x0008 | 0x0004)) != 0
                var entryModifiers = modifiers
                if isControlKey && scalar.value < 0x20 {
                    entryModifiers.insert(.control)
                }
                return KeyPress(key: .character(value), characters: text, modifiers: entryModifiers)
            }
            return nil
        }
    }

    private static func modifiers(from controlState: DWORD) -> KeyPress.Modifiers {
        var modifiers: KeyPress.Modifiers = []

        if controlState & 0x0010 != 0 {
            modifiers.insert(.shift)
        }
        if controlState & (0x0008 | 0x0004) != 0 {
            modifiers.insert(.control)
        }
        if controlState & (0x0002 | 0x0001) != 0 {
            modifiers.insert(.option)
        }

        return modifiers
    }

    // MARK: - 信号(控制台 Ctrl 事件)

    func startSignals(handler: @escaping @Sendable (TerminalSignal) -> Void) {
        guard !isSignalsRunning else { return }
        isSignalsRunning = true
        signalHandler = handler

        WindowsConsoleDispatcher.currentHandler = { ctrlType in
            windowsEventQueue.async {
                let signal: TerminalSignal?
                switch ctrlType {
                case DWORD(CTRL_C_EVENT):
                    signal = .interrupt
                case DWORD(CTRL_BREAK_EVENT):
                    signal = .terminate
                case DWORD(CTRL_CLOSE_EVENT):
                    signal = .terminate
                case DWORD(CTRL_LOGOFF_EVENT):
                    signal = .hangup
                case DWORD(CTRL_SHUTDOWN_EVENT):
                    signal = .terminate
                default:
                    signal = nil
                }

                if let signal = signal {
                    handler(signal)
                }
            }
            return true
        }

        _ = SetConsoleCtrlHandler(WindowsConsoleDispatcher.callback, true)
    }

    func stopSignals() {
        guard isSignalsRunning else { return }
        isSignalsRunning = false

        _ = SetConsoleCtrlHandler(WindowsConsoleDispatcher.callback, false)
        WindowsConsoleDispatcher.currentHandler = nil
        signalHandler = nil
    }

    func suspendCurrentProcess() {
        // Windows 没有对应的 POSIX `SIGTSTP` 语义,保守地保持无操作。
    }

    // MARK: - 输出(VT 处理)

    func prepareOutput() {
        guard !didEnableVT else { return }
        guard outputHandle != INVALID_HANDLE_VALUE,
              GetConsoleMode(outputHandle, &originalOutputMode) else { return }
        // stdout 被重定向(管道/文件)时 SetConsoleMode 会失败,静默保留原始模式。
        guard SetConsoleMode(outputHandle, originalOutputMode | DWORD(ENABLE_VIRTUAL_TERMINAL_PROCESSING)) else {
            return
        }
        didEnableVT = true
    }

    func restoreOutput() {
        guard didEnableVT else { return }
        _ = SetConsoleMode(outputHandle, originalOutputMode)
        didEnableVT = false
    }
}
#endif
