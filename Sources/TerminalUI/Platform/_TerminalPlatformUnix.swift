#if canImport(Darwin) || canImport(Glibc)
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import Dispatch

#if canImport(Darwin)
private let _terminalEINTR: Int32 = Darwin.EINTR
#elseif canImport(Glibc)
private let _terminalEINTR: Int32 = Glibc.EINTR
#endif

#if canImport(Darwin) || canImport(Glibc)
private typealias _PlatformSignalHandler = sig_t?

private func _installSignalHandler(
    _ signalNumber: Int32,
    _ handler: _PlatformSignalHandler
) -> _PlatformSignalHandler {
    #if canImport(Darwin)
    return Darwin.signal(signalNumber, handler)
    #elseif canImport(Glibc)
    return Glibc.signal(signalNumber, handler)
    #endif
}

private func _raiseSignal(_ signalNumber: Int32) {
    #if canImport(Darwin)
    _ = Darwin.raise(signalNumber)
    #elseif canImport(Glibc)
    _ = Glibc.raise(signalNumber)
    #endif
}

private struct _PreviousSignalHandler {
    let value: _PlatformSignalHandler
}
#endif

/// Unix/macOS 平台后端:一个类同时承载输入、信号、尺寸读取与输出准备。
///
/// 输入侧保留 POSIX 语义,使用 `tcgetattr` / `tcsetattr` 切换原始模式,`poll` 监听
/// 标准输入;信号侧用 `DispatchSourceSignal` 把底层信号转成统一 `TerminalSignal`;
/// 尺寸用 `ioctl` 与 `winsize` 读取;Unix 终端原生支持 ANSI,输出侧为空操作。
final class _TerminalPlatformUnix: _TerminalPlatformBackend {
    // MARK: - 尺寸读取(静态)

    static func currentSize(fileDescriptor: Int32?) -> TerminalSize? {
        let fd = fileDescriptor ?? 1

        #if canImport(Darwin)
        guard Darwin.isatty(fd) != 0 else { return nil }
        var value = Darwin.winsize()
        let result = Darwin.ioctl(fd, TIOCGWINSZ, &value)
        guard result == 0, value.ws_col > 0, value.ws_row > 0 else { return nil }
        return TerminalSize(columns: Int(value.ws_col), rows: Int(value.ws_row))
        #elseif canImport(Glibc)
        guard Glibc.isatty(fd) != 0 else { return nil }
        var value = Glibc.winsize()
        let result = Glibc.ioctl(fd, UInt(TIOCGWINSZ), &value)
        guard result == 0, value.ws_col > 0, value.ws_row > 0 else { return nil }
        return TerminalSize(columns: Int(value.ws_col), rows: Int(value.ws_row))
        #else
        return nil
        #endif
    }

    // MARK: - 输入(原始模式)

    private var original = termios()
    private var isRaw = false

    func startInput() throws {
        // 只有真实 TTY 才能进入 raw mode;被重定向到文件/管道时直接失败。
        guard isatty(STDIN_FILENO) != 0 else {
            throw TerminalInputError.notTerminal
        }
        guard tcgetattr(STDIN_FILENO, &original) == 0 else {
            throw _terminalInputSystemError("tcgetattr")
        }

        var raw = original
        // 输入侧禁用 CR/LF 转换与软件流控,避免按键语义被终端层吞改。
        raw.c_iflag &= ~tcflag_t(BRKINT | ICRNL | INPCK | ISTRIP | IXON)
        // 8-bit 字符输入。
        raw.c_cflag |= tcflag_t(CS8)
        // 关闭回显和规范模式,使按键按字节即时可读。
        raw.c_lflag &= ~tcflag_t(ECHO | ICANON | IEXTEN)

        withUnsafeMutableBytes(of: &raw.c_cc) { bytes in
            bytes[Int(VMIN)] = 0
            bytes[Int(VTIME)] = 0
        }

        guard tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw) == 0 else {
            throw _terminalInputSystemError("tcsetattr")
        }
        isRaw = true
    }

    func stopInput() {
        guard isRaw else { return }
        var value = original
        _ = tcsetattr(STDIN_FILENO, TCSAFLUSH, &value)
        isRaw = false
    }

    func readKey(timeoutMilliseconds: Int32) throws -> KeyPress? {
        // 超时返回 nil,让上层主循环继续处理动画/信号,而不是阻塞在读输入。
        guard try waitForInput(timeoutMilliseconds: timeoutMilliseconds) else { return nil }
        guard let first = try readByte() else { return nil }

        var bytes = [first]
        if first == 0x1B {
            // ESC 既可能是单键,也可能是 CSI/SS3 序列前缀;
            // 这里做短时间拼包,尽量还原完整功能键。
            while bytes.count < 16,
                  try waitForInput(timeoutMilliseconds: 8),
                  let byte = try readByte() {
                bytes.append(byte)
                if isCompleteEscapeSequence(bytes) { break }
            }
        } else {
            let count = utf8Length(firstByte: first)
            // 多字节 UTF-8 字符继续补齐,保证上层收到完整字符。
            while bytes.count < count {
                guard try waitForInput(timeoutMilliseconds: 20), let byte = try readByte() else { break }
                bytes.append(byte)
            }
        }

        return _KeyPressDecoder.decode(bytes)
    }

    private func waitForInput(timeoutMilliseconds: Int32) throws -> Bool {
        var descriptor = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
        let result = poll(&descriptor, 1, timeoutMilliseconds)
        if result < 0 {
            // 被系统信号打断时交由上层下一次轮询继续,不视为硬错误。
            if errno == _terminalEINTR { return false }
            throw _terminalInputSystemError("poll")
        }
        return result > 0 && (descriptor.revents & Int16(POLLIN)) != 0
    }

    private func readByte() throws -> UInt8? {
        var byte: UInt8 = 0
        let count = read(STDIN_FILENO, &byte, 1)
        if count < 0 {
            if errno == _terminalEINTR { return nil }
            throw _terminalInputSystemError("read")
        }
        return count == 1 ? byte : nil
    }

    private func utf8Length(firstByte: UInt8) -> Int {
        switch firstByte {
        case 0xC0...0xDF: 2
        case 0xE0...0xEF: 3
        case 0xF0...0xF7: 4
        default: 1
        }
    }

    /// ANSI CSI 与 SS3 序列结束于 `0x40...0x7E` 这段 final-byte 范围。
    private func isCompleteEscapeSequence(_ bytes: [UInt8]) -> Bool {
        guard bytes.count >= 3, bytes[0] == 0x1B else { return false }
        switch bytes[1] {
        case 0x5B, 0x4F:
            return (0x40...0x7E).contains(bytes[bytes.count - 1])
        default:
            return true
        }
    }

    // MARK: - 信号(DispatchSourceSignal)

    private let signalQueue = DispatchQueue(label: "TerminalUI.signals")
    private var sources: [any DispatchSourceSignal] = []
    private var previousHandlers: [Int32: _PreviousSignalHandler] = [:]

    func startSignals(handler: @escaping @Sendable (TerminalSignal) -> Void) {
        guard sources.isEmpty else { return }

        for terminalSignal in Self.observedSignals {
            let number = terminalSignal.signalNumber
            let previous = _installSignalHandler(number, SIG_IGN)
            previousHandlers[number] = _PreviousSignalHandler(value: previous)

            let source = DispatchSource.makeSignalSource(signal: number, queue: signalQueue)
            source.setEventHandler {
                handler(terminalSignal)
            }
            source.resume()
            sources.append(source)
        }
    }

    func stopSignals() {
        for source in sources {
            source.cancel()
        }
        sources.removeAll()

        for (number, previous) in previousHandlers {
            _ = _installSignalHandler(number, previous.value)
        }
        previousHandlers.removeAll()
    }

    func suspendCurrentProcess() {
        _ = _installSignalHandler(SIGTSTP, SIG_DFL)
        _raiseSignal(SIGTSTP)
        _ = _installSignalHandler(SIGTSTP, SIG_IGN)
    }

    private static let observedSignals: [TerminalSignal] = [
        .interrupt,
        .terminate,
        .hangup,
        .quit,
        .suspend,
        .resume,
        .windowSizeChanged,
    ]

    // MARK: - 输出(Unix 终端原生支持 ANSI,无需 VT 准备)

    func prepareOutput() {}
    func restoreOutput() {}
}
#endif
