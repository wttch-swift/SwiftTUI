/// 滚动视图使用的坐标轴。
public enum Axis {
    public struct Set: OptionSet, Sendable {
        public let rawValue: UInt8

        public init(rawValue: UInt8) { self.rawValue = rawValue }

        public static let horizontal = Set(rawValue: 1 << 0)
        public static let vertical = Set(rawValue: 1 << 1)
    }
}

/// 在有限视口内显示可滚动内容。
public struct ScrollView<Content: View>: View, _NeverView {
    package let axes: Axis.Set
    package let showsIndicators: Bool
    package let content: Content
    package let state = _ScrollViewState()

    public init(
        _ axes: Axis.Set = .vertical,
        showsIndicators: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.axes = axes
        self.showsIndicators = showsIndicators
        self.content = content()
    }
}

package final class _ScrollViewState {
    package var isFocusManaged = false
    package var isFocused = false
    package var offsetX = 0
    package var offsetY = 0
    package var maximumX = 0
    package var maximumY = 0
    package var viewportWidth = 0
    package var viewportHeight = 0
    package var contentWidth = 0
    package var contentHeight = 0
}
