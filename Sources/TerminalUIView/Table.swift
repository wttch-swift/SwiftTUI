public struct TableColumn<RowValue> {
    package let title: String
    package let alignment: HorizontalAlignment
    package let makeCell: (RowValue) -> any View

    public init<Value: CustomStringConvertible>(
        _ title: String,
        value: KeyPath<RowValue, Value>,
        alignment: HorizontalAlignment = .leading
    ) {
        self.title = title
        self.alignment = alignment
        self.makeCell = { row in Text(String(describing: row[keyPath: value])) }
    }

    public init<Content: View>(
        _ title: String,
        alignment: HorizontalAlignment = .leading,
        @ViewBuilder content: @escaping (RowValue) -> Content
    ) {
        self.title = title
        self.alignment = alignment
        self.makeCell = { row in content(row) }
    }
}

@resultBuilder
public enum TableColumnBuilder<RowValue> {
    public static func buildExpression(_ expression: TableColumn<RowValue>) -> [TableColumn<RowValue>] {
        [expression]
    }

    public static func buildBlock(_ components: [TableColumn<RowValue>]...) -> [TableColumn<RowValue>] {
        components.flatMap { $0 }
    }

    public static func buildOptional(_ component: [TableColumn<RowValue>]?) -> [TableColumn<RowValue>] {
        component ?? []
    }

    public static func buildEither(first component: [TableColumn<RowValue>]) -> [TableColumn<RowValue>] {
        component
    }

    public static func buildEither(second component: [TableColumn<RowValue>]) -> [TableColumn<RowValue>] {
        component
    }

    public static func buildArray(_ components: [[TableColumn<RowValue>]]) -> [TableColumn<RowValue>] {
        components.flatMap { $0 }
    }
}

public struct Table<RowValue>: View, _NeverView {
    package let rows: [RowValue]
    package let columns: [TableColumn<RowValue>]
    package let style: BorderStyle

    public init<Data: Sequence>(
        _ data: Data,
        style: BorderStyle = .single,
        @TableColumnBuilder<RowValue> columns: () -> [TableColumn<RowValue>]
    ) where Data.Element == RowValue {
        rows = Array(data)
        self.columns = columns()
        self.style = style
    }
}
