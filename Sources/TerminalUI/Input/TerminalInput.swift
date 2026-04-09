#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public enum TerminalInputError: Error, CustomStringConvertible {
    case notTerminal
    case systemCall(String)

    public var description: String {
        switch self {
        case .notTerminal:
            "standard input is not a terminal"
        case .systemCall(let message):
            message
        }
    }
}

/// 基于 POSIX termios 的跨 macOS/Linux 终端按键读取器。
final class _TerminalInput {
    private var original = termios()
    private var isRaw = false

    func start() throws {
        guard isatty(STDIN_FILENO) == 1 else { throw TerminalInputError.notTerminal }
        guard tcgetattr(STDIN_FILENO, &original) == 0 else {
            throw systemError("tcgetattr")
        }

        var raw = original
        raw.c_iflag &= ~tcflag_t(BRKINT | ICRNL | INPCK | ISTRIP | IXON)
        // 保留 OPOST/ONLCR，让 Canvas 输出的换行同时回到行首。
        raw.c_cflag |= tcflag_t(CS8)
        // 保留 ISIG，使 Ctrl-C/Ctrl-Z 继续遵守系统终端语义。
        raw.c_lflag &= ~tcflag_t(ECHO | ICANON | IEXTEN)
        withUnsafeMutableBytes(of: &raw.c_cc) { bytes in
            bytes[Int(VMIN)] = 0
            bytes[Int(VTIME)] = 0
        }

        guard tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw) == 0 else {
            throw systemError("tcsetattr")
        }
        isRaw = true
    }

    func stop() {
        guard isRaw else { return }
        var value = original
        _ = tcsetattr(STDIN_FILENO, TCSAFLUSH, &value)
        isRaw = false
    }

    /// 等待至多 timeoutMilliseconds；超时返回 nil。
    func readKey(timeoutMilliseconds: Int32) throws -> KeyPress? {
        guard try waitForInput(timeoutMilliseconds: timeoutMilliseconds) else { return nil }
        guard let first = try readByte() else { return nil }

        var bytes = [first]
        if first == 0x1B {
            while bytes.count < 16, try waitForInput(timeoutMilliseconds: 8), let byte = try readByte() {
                bytes.append(byte)
                // CSI/SS3 的 final byte 已到达时序列已经完整，不再额外等待 8ms。
                if isCompleteEscapeSequence(bytes) { break }
            }
        } else {
            let count = utf8Length(firstByte: first)
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
            if errno == EINTR { return false }
            throw systemError("poll")
        }
        return result > 0 && (descriptor.revents & Int16(POLLIN)) != 0
    }

    private func readByte() throws -> UInt8? {
        var byte: UInt8 = 0
        let count = read(STDIN_FILENO, &byte, 1)
        if count < 0 {
            if errno == EINTR { return nil }
            throw systemError("read")
        }
        return count == 1 ? byte : nil
    }

    private func systemError(_ operation: String) -> TerminalInputError {
        TerminalInputError.systemCall("\(operation) failed (errno \(errno))")
    }

    private func utf8Length(firstByte: UInt8) -> Int {
        switch firstByte {
        case 0xC0...0xDF: 2
        case 0xE0...0xEF: 3
        case 0xF0...0xF7: 4
        default: 1
        }
    }

    /// ANSI CSI 与 SS3 序列都由 0x40...0x7E 范围内的 final byte 结束。
    private func isCompleteEscapeSequence(_ bytes: [UInt8]) -> Bool {
        guard bytes.count >= 3, bytes[0] == 0x1B else { return false }
        switch bytes[1] {
        case 0x5B, 0x4F:
            return (0x40...0x7E).contains(bytes[bytes.count - 1])
        default:
            return true
        }
    }

    deinit { stop() }
}

enum _KeyPressDecoder {
    static func decode(_ bytes: [UInt8]) -> KeyPress {
        switch bytes {
        case [0x1B]: return KeyPress(key: .escape, characters: "\u{1B}")
        case [0x0D], [0x0A]: return KeyPress(key: .returnKey, characters: "\n")
        case [0x09]: return KeyPress(key: .tab, characters: "\t")
        case [0x08], [0x7F]: return KeyPress(key: .backspace)
        case [0x1B, 0x5B, 0x41]: return KeyPress(key: .upArrow)
        case [0x1B, 0x5B, 0x42]: return KeyPress(key: .downArrow)
        case [0x1B, 0x5B, 0x43]: return KeyPress(key: .rightArrow)
        case [0x1B, 0x5B, 0x44]: return KeyPress(key: .leftArrow)
        case [0x1B, 0x5B, 0x48], [0x1B, 0x4F, 0x48]: return KeyPress(key: .home)
        case [0x1B, 0x5B, 0x46], [0x1B, 0x4F, 0x46]: return KeyPress(key: .end)
        case [0x1B, 0x5B, 0x33, 0x7E]: return KeyPress(key: .delete)
        case [0x1B, 0x5B, 0x35, 0x7E]: return KeyPress(key: .pageUp)
        case [0x1B, 0x5B, 0x36, 0x7E]: return KeyPress(key: .pageDown)
        // CSI Z 是终端为 BackTab（通常由 Shift-Tab 产生）发送的标准序列。
        case [0x1B, 0x5B, 0x5A]: return KeyPress(key: .tab, characters: "\t", modifiers: .shift)
        default: break
        }

        if bytes.count == 1, let byte = bytes.first, (1...26).contains(byte) {
            let scalar = UnicodeScalar(UInt8(ascii: "a") + byte - 1)
            let text = String(Character(scalar))
            return KeyPress(key: .character(Character(text)), characters: text, modifiers: .control)
        }

        if bytes.first == 0x1B, bytes.count > 1,
           let text = String(bytes: bytes.dropFirst(), encoding: .utf8),
           let character = text.first {
            return KeyPress(key: .character(character), characters: text, modifiers: .option)
        }

        if let text = String(bytes: bytes, encoding: .utf8), let character = text.first {
            let modifiers: KeyPress.Modifiers = character.isUppercase ? .shift : []
            return KeyPress(key: .character(character), characters: text, modifiers: modifiers)
        }

        return KeyPress(key: .unknown)
    }
}
