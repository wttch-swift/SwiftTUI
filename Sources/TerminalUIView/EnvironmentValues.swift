

/// 环境数值保存的结构体，用于在布局和渲染过程中传递环境信息。
public struct EnvironmentValues {
    /// 存储环境值的字典。
    private var storage: [ObjectIdentifier: Any] = [:]

    package init() {}

    /// 获取指定环境键的值，如果不存在则返回默认值。
    package subscript<K: EnvironmentKey>(key: K.Type) -> K.Value {
        get {
            let id = ObjectIdentifier(key)
            if let value = storage[id] as? K.Value {
                return value
            } else {
                return key.defaultValue
            }
        }
        set {
            let id = ObjectIdentifier(key)
            storage[id] = newValue
        }
    }


    // MARK: 文字

    // 文字装饰

    /// 当前环境是否启用粗体；默认关闭，可由后代环境覆盖。
    package var _isBold: Bool {
        get { self[BoldTextKey.self] }
        set { self[BoldTextKey.self] = newValue }
    }
    /// 当前环境是否启用斜体；默认关闭，可由后代环境覆盖。
    package var _isItalic: Bool {
        get { self[ItalicTextKey.self] }
        set { self[ItalicTextKey.self] = newValue }
    }
    /// 当前环境是否启用下划线；默认关闭，可由后代环境覆盖。
    package var _isUnderline: Bool {
        get { self[UnderlineTextKey.self] }
        set { self[UnderlineTextKey.self] = newValue }
    }
    /// 当前环境是否启用删除线；默认关闭，可由后代环境覆盖。
    package var _isStrikethrough: Bool {
        get { self[StrikethroughTextKey.self] }
        set { self[StrikethroughTextKey.self] = newValue }
    }

    /// 行限制
    package var lineLimit: Int? = nil
}
