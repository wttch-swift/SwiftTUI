import XCTest
@testable import WttchCombine

final class DebounceTests: XCTestCase {
    /// 突发 1、2、3,静默期满后只投最后一个 3。
    func testCoalescesRapidValues() {
        let subject = PassthroughSubject<Int, Never>()
        let queue = DispatchQueue(label: "debounce.test2")
        var received: [Int] = []
        let token = subject
            .debounce(for: .milliseconds(100), queue: queue)
            .sink { received.append($0) }
        subject.send(1)
        subject.send(2)
        subject.send(3)
        Thread.sleep(forTimeInterval: 0.3)
        token.cancel()
        XCTAssertEqual(received, [3])
    }

    /// 值间隔大于 dueTime,每个都单独投递。
    func testSpacedValuesEachDelivered() {
        let subject = PassthroughSubject<Int, Never>()
        let queue = DispatchQueue(label: "debounce.test3")
        var received: [Int] = []
        let token = subject
            .debounce(for: .milliseconds(100), queue: queue)
            .sink { received.append($0) }
        subject.send(1)
        Thread.sleep(forTimeInterval: 0.2)
        subject.send(2)
        Thread.sleep(forTimeInterval: 0.2)
        token.cancel()
        XCTAssertEqual(received, [1, 2])
    }

    /// 完成信号立即透传,丢弃尚未投递的待定值。
    func testCompletionDropsPending() {
        let subject = PassthroughSubject<Int, Never>()
        let queue = DispatchQueue(label: "debounce.test4")
        var received: [Int] = []
        var completed = false
        let sink = Subscribers.Sink<Int, Never>(
            receiveValue: { received.append($0) },
            receiveCompletion: { _ in completed = true }
        )
        subject
            .debounce(for: .milliseconds(100), queue: queue)
            .receive(subscriber: sink)
        subject.send(1)
        subject.send(completion: .finished)
        XCTAssertTrue(completed)  // 完成同步透传,不等待防抖窗口
        Thread.sleep(forTimeInterval: 0.2)
        XCTAssertEqual(received, [])  // 待定值被丢弃
    }

    /// 静默期满投递与下一个值重置计时器:先突发,等 200ms,再发一个等 200ms。
    func testTimerResetThenDeliver() {
        let subject = PassthroughSubject<Int, Never>()
        let queue = DispatchQueue(label: "debounce.test5")
        var received: [Int] = []
        let token = subject
            .debounce(for: .milliseconds(100), queue: queue)
            .sink { received.append($0) }
        subject.send(1)  // 排定 t+100ms 投 1
        subject.send(2)  // 重置:排定 t+100ms 投 2,投 1 的任务作废
        Thread.sleep(forTimeInterval: 0.2)  // 静默期满,应投 2
        subject.send(3)  // 重置:排定 t+100ms 投 3
        Thread.sleep(forTimeInterval: 0.2)  // 应投 3
        token.cancel()
        XCTAssertEqual(received, [2, 3])
    }
}
