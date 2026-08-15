import Foundation

/// 按固定时间间隔循环显示一组文本帧。
///
/// 为避免动画过程中改变 Stack 布局，建议所有帧使用相同的终端显示宽度。
/// 帧索引由单调时钟计算，即使某次重绘延迟，也会直接追上当前时间对应的帧，
/// 不会把延迟不断累积到后续动画中。
extension AnimatedText: _LayoutNodeProducing {
    package func _makeLayoutNode() -> any _Layoutable {
        guard !frames.isEmpty else { return Text("")._makeLayoutNode() }
        let index = _TerminalAnimationClock.shared.frameIndex(
            count: frames.count,
            interval: interval
        )
        return Text(frames[index])._makeLayoutNode()
    }
}

/// 所有 AnimatedText 共用一个低频计时器，避免每个动画创建独立线程或 Timer。
private final class _TerminalAnimationClock: @unchecked Sendable {
    static let shared = _TerminalAnimationClock()

    private let source: DispatchSourceTimer

    private init() {
        source = DispatchSource.makeTimerSource(queue: .global(qos: .userInteractive))
        source.schedule(
            deadline: .now() + .milliseconds(50),
            repeating: .milliseconds(50),
            leeway: .milliseconds(5)
        )
        source.setEventHandler {
            TerminalStateRuntime.post(.renderRequested)
        }
        source.resume()
    }

    func frameIndex(count: Int, interval: TimeInterval) -> Int {
        let nanosecondsPerFrame = UInt64(interval * 1_000_000_000)
        let tick = DispatchTime.now().uptimeNanoseconds / max(1, nanosecondsPerFrame)
        return Int(tick % UInt64(count))
    }
}
