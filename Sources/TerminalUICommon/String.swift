    
public extension Character {
    /// 计算字符在终端中占用的单元格宽度。
    var displayWidth: Int {
        Segment.cellLength(of: String(self))
    }
}

public extension String {
    var displayWidth: Int {
        Segment.cellLength(of: self)
    }

    func truncated(toWidth maxWidth: Int) -> String {
        Segment.truncate(self, to: maxWidth)
    }
}
