/// 父节点向子节点提出的尺寸约束。
///
/// `nil` 表示该轴没有上限；具体布局节点可根据固有尺寸和提议值决定
/// 最终测量结果。它是一次协商，不代表最终分配的 frame。
public struct ProposedSize: Equatable, Hashable, Sendable {
    /// 建议宽度，单位为终端 cell；`nil` 表示不受约束。
    public var width: Int?
    /// 建议高度，单位为终端行；`nil` 表示不受约束。
    public var height: Int?

    public init(width: Int? = nil, height: Int? = nil) {
        self.width = width
        self.height = height
    }

    /// 从确定尺寸创建两个轴均受约束的提议尺寸。
    public init(_ size: Size) {
        self.init(width: size.w, height: size.h)
    }
}

/// 使用终端单元格表示的确定二维尺寸。
public struct Size: Equatable, Hashable, Sendable {
    /// 水平方向的 cell 数量。
    public let w: Int
    /// 垂直方向的行数。
    public let h: Int

    public init(w: Int, h: Int) {
        self.w = w
        self.h = h
    }
}

/// 统计数组中所有尺寸的扩展函数。
public extension Array where Element == Size {
    var totalWidth: Int { reduce(0) { $0 + $1.w } }
    var maxHeight: Int { map(\.h).max() ?? 0 }
}

public extension Size {
    static let zero = Size(w: 0, h: 0)
}

public struct Offset: Equatable, Hashable, Sendable {
    public let x: Int
    public let y: Int

    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }
}

public extension Offset {
    static let zero = Offset(x: 0, y: 0)
}

public struct Rect: Equatable, Hashable, Sendable {
    public let x: Int
    public let y: Int
    public let w: Int
    public let h: Int

    public init(x: Int, y: Int, w: Int, h: Int) {
        self.x = x
        self.y = y
        self.w = w
        self.h = h
    }
}

public extension Rect {
    /// 返回矩形的原点。
    var origin: Offset { Offset(x: x, y: y) }
    /// 返回矩形的尺寸。
    var size: Size { Size(w: w, h: h) }
}

public extension Rect {
    static let zero = Rect(x: 0, y: 0, w: 0, h: 0)

    var maxX: Int { x + w }
    var maxY: Int { y + h }

    func insetBy(dx: Int, dy: Int) -> Rect {
        Rect(
            x: x + dx,
            y: y + dy,
            w: max(0, w - 2 * dx),
            h: max(0, h - 2 * dy)
        )
    }

    /// 返回两个矩形的重叠区域；不相交时返回位于计算交点处的零尺寸矩形。
    ///
    /// 宽高始终钳制为非负数，调用方可直接把结果继续用于嵌套裁剪，
    /// 无需用可选值额外表示“空裁剪区”。
    func intersection(_ other: Rect) -> Rect {
        let left = max(x, other.x)
        let top = max(y, other.y)
        let right = min(maxX, other.maxX)
        let bottom = min(maxY, other.maxY)
        return Rect(
            x: left,
            y: top,
            w: max(0, right - left),
            h: max(0, bottom - top)
        )
    }
}
