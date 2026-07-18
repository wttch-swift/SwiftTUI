/// 终端窗口的字符网格尺寸。
///
/// `columns` 和 `rows` 分别对应 POSIX `winsize` 的 `ws_col` 与 `ws_row`；
/// `width`、`height` 是便于传给 `TerminalApp` 的同义属性。
public struct TerminalSize: Equatable, Sendable {
    public let columns: Int
    public let rows: Int

    public var width: Int { columns }
    public var height: Int { rows }

    public init(columns: Int, rows: Int) {
        self.columns = max(1, columns)
        self.rows = max(1, rows)
    }
}
