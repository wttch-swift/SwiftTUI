import Foundation

public struct GeometryProxy: Sendable {
    public let frame: Rect

    package init(frame: Rect) {
        self.frame = frame
    }

    public var size: Size { Size(w: frame.w, h: frame.h) }
}

public struct GeometryReader<Content: View>: View, _NeverView {
    package let content: (GeometryProxy) -> Content

    public init(@ViewBuilder content: @escaping (GeometryProxy) -> Content) {
        self.content = content
    }
}

public struct ForEach<Data, ID, Content>: View, _NeverView
where Data: RandomAccessCollection, ID: Hashable, Content: View {
    package let data: Data
    package let id: KeyPath<Data.Element, ID>
    package let content: (Data.Element) -> Content

    public init(
        _ data: Data,
        id: KeyPath<Data.Element, ID>,
        @ViewBuilder content: @escaping (Data.Element) -> Content
    ) {
        self.data = data
        self.id = id
        self.content = content
    }
}

public extension ForEach where Data.Element: Identifiable, ID == Data.Element.ID {
    init(_ data: Data, @ViewBuilder content: @escaping (Data.Element) -> Content) {
        self.init(data, id: \.id, content: content)
    }
}

public extension ForEach where Data == Range<Int>, ID == Int {
    init(_ data: Range<Int>, @ViewBuilder content: @escaping (Int) -> Content) {
        self.init(data, id: \.self, content: content)
    }
}

/// 按固定时间间隔循环显示一组文本帧。
public struct AnimatedText: View, _NeverView {
    package let frames: [String]
    package let interval: TimeInterval

    public init(_ frames: [String], interval: TimeInterval = 0.1) {
        self.frames = frames
        self.interval = max(0.05, interval)
    }
}
