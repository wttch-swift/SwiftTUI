import Dispatch
import Foundation

/// map 操作符:同步变换值。
public struct Map<Upstream: Publisher, Mapped>: Publisher {
    public typealias Output = Mapped
    public typealias Failure = Upstream.Failure

    private let upstream: Upstream
    private let transform: (Upstream.Output) -> Mapped

    public init(upstream: Upstream, transform: @escaping (Upstream.Output) -> Mapped) {
        self.upstream = upstream
        self.transform = transform
    }

    public func receive<S: Subscriber>(subscriber: S)
        where S.Input == Mapped, S.Failure == Upstream.Failure {
        upstream.receive(subscriber: MapSubscriber<Upstream.Output, S, Mapped>(
            downstream: subscriber, transform: transform))
    }
}

private final class MapSubscriber<UpstreamOutput, Downstream: Subscriber, Mapped>: Subscriber
    where Downstream.Input == Mapped {
    typealias Input = UpstreamOutput
    typealias Failure = Downstream.Failure

    private let downstream: Downstream
    private let transform: (UpstreamOutput) -> Mapped

    init(downstream: Downstream, transform: @escaping (UpstreamOutput) -> Mapped) {
        self.downstream = downstream
        self.transform = transform
    }

    func receive(subscription: Subscription) {
        downstream.receive(subscription: subscription)
    }

    func receive(_ input: UpstreamOutput) -> Subscribers.Demand {
        downstream.receive(transform(input))
    }

    func receive(completion: Subscribers.Completion<Downstream.Failure>) {
        downstream.receive(completion: completion)
    }
}

/// `receive(on:)`:把事件通过 DispatchQueue 异步投递到目标队列。
///
/// DispatchQueue 就是本库的最小 Scheduler;事件在指定队列串行执行,避免跨线程竞争。
public struct ReceiveOn<Upstream: Publisher>: Publisher {
    public typealias Output = Upstream.Output
    public typealias Failure = Upstream.Failure

    private let upstream: Upstream
    private let queue: DispatchQueue

    public init(upstream: Upstream, queue: DispatchQueue) {
        self.upstream = upstream
        self.queue = queue
    }

    public func receive<S: Subscriber>(subscriber: S)
        where S.Input == Upstream.Output, S.Failure == Upstream.Failure {
        upstream.receive(subscriber: ReceiveOnSubscriber(downstream: subscriber, queue: queue))
    }
}

/// 跨线程捕获非 Sendable 载荷的容器;投递责任由接收方的队列串行化保证。
private final class SendableBox<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) {
        self.value = value
    }
}

private final class ReceiveOnSubscriber<Downstream: Subscriber>: Subscriber, @unchecked Sendable {
    typealias Input = Downstream.Input
    typealias Failure = Downstream.Failure

    private let downstream: Downstream
    private let queue: DispatchQueue

    init(downstream: Downstream, queue: DispatchQueue) {
        self.downstream = downstream
        self.queue = queue
    }

    func receive(subscription: Subscription) {
        // 同步向上游申请 unlimited 流量,避免下游的订阅还在队列里时 send 被丢。
        subscription.request(.unlimited)
        queue.async { self.downstream.receive(subscription: subscription) }
    }

    func receive(_ input: Input) -> Subscribers.Demand {
        let box = SendableBox(input)
        queue.async { _ = self.downstream.receive(box.value) }
        return .unlimited
    }

    func receive(completion: Subscribers.Completion<Failure>) {
        let box = SendableBox(completion)
        queue.async { self.downstream.receive(completion: box.value) }
    }
}

// MARK: - Publisher 扩展入口

public extension Publisher {
    /// 终结订阅,返回可取消句柄。仅适用于 `Failure == Never` 的流。
    func sink(receiveValue: @escaping (Output) -> Void) -> AnyCancellable where Failure == Never {
        let sink = Subscribers.Sink<Output, Failure>(receiveValue: receiveValue)
        receive(subscriber: sink)
        return AnyCancellable(sink)
    }

    func map<Mapped>(_ transform: @escaping (Output) -> Mapped) -> Map<Self, Mapped> {
        Map(upstream: self, transform: transform)
    }

    /// 在指定 DispatchQueue 上异步投递事件。
    func receive(on queue: DispatchQueue) -> ReceiveOn<Self> {
        ReceiveOn(upstream: self, queue: queue)
    }
}
