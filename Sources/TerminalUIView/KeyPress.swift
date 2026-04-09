/// 一次终端按键事件。
public struct KeyPress: Equatable, Sendable {
    public enum Key: Equatable, Hashable, Sendable {
        case character(Character)
        case upArrow
        case downArrow
        case leftArrow
        case rightArrow
        case escape
        case returnKey
        case tab
        case backspace
        case delete
        case home
        case end
        case pageUp
        case pageDown
        case unknown
    }

    public struct Modifiers: OptionSet, Equatable, Hashable, Sendable {
        public let rawValue: UInt8

        public init(rawValue: UInt8) { self.rawValue = rawValue }

        public static let shift = Modifiers(rawValue: 1 << 0)
        public static let control = Modifiers(rawValue: 1 << 1)
        public static let option = Modifiers(rawValue: 1 << 2)
    }

    public enum Result: Equatable, Sendable {
        case handled
        case ignored
    }

    public let key: Key
    public let characters: String
    public let modifiers: Modifiers

    public init(
        key: Key,
        characters: String = "",
        modifiers: Modifiers = []
    ) {
        self.key = key
        self.characters = characters
        self.modifiers = modifiers
    }
}
