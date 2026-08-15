/// 将“平台输入字节流”还原成统一的 `KeyPress` 语义。
///
/// 解码优先级：
/// - 先匹配完整控制序列（方向键、Home/End、PageUp/PageDown）；
/// - 再识别 Ctrl 组合（1...26）；
/// - 再识别 Alt 前缀（ESC + UTF-8）；
/// - 最后回落到普通 UTF-8 字符。
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
