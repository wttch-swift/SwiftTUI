import Foundation

/// 手动驱动的发布端:任意线程 `send(_:)`,订阅者同步收到值。
public final class PassthroughSubject<Output, Failure: Error>: Publisher, @unchecked Sendable {
    public typealias Output = Output
    public typealias Failure = Failure

    private let lock = NSLock()
    private var boxes: [Box<Output, Failure>] = []

    public init() {}

    /// 向当前所有订阅者同步发送一个值。
    public func send(_ value: Output) {
        for box in snapshot() {
            _ = box.receive(value)
        }
    }

    /// 终止所有订阅者。
    public func send(completion: Subscribers.Completion<Failure>) {
        for box in snapshot() {
            box.receive(completion: completion)
        }
        lock.lock()
        boxes.removeAll()
        lock.unlock()
    }

    public func receive<S: Subscriber>(subscriber: S)
        where S.Input == Output, S.Failure == Failure {
        let box = Box(subscriber)
        let connection = SubjectConnection(
            onDemand: { [weak box] in box?.addDemand($0) },
            onCancel: { [weak self, weak box] in
                guard let self, let box else { return }
                self.lock.lock()
                self.boxes.removeAll { $0 === box }
                self.lock.unlock()
            }
        )
        lock.lock()
        boxes.append(box)
        lock.unlock()
        box.receive(subscription: connection)
    }

    private func snapshot() -> [Box<Output, Failure>] {
        lock.lock()
        defer { lock.unlock() }
        return boxes
    }
}

/// 订阅箱:把任意 Subscriber 用闭包擦除成统一类型,subject 才能异构存储。
private final class Box<Input, Failure: Error>: Subscriber, @unchecked Sendable {
    private let onSubscription: (Subscription) -> Void
    private let onValue: (Input) -> Subscribers.Demand
    private let onCompletion: (Subscribers.Completion<Failure>) -> Void
    private let lock = NSLock()
    private var demand: Subscribers.Demand = .none

    init<S: Subscriber>(_ s: S) where S.Input == Input, S.Failure == Failure {
        onSubscription = { s.receive(subscription: $0) }
        onValue = { s.receive($0) }
        onCompletion = { s.receive(completion: $0) }
    }

    func addDemand(_ additional: Subscribers.Demand) {
        lock.lock()
        demand = demand + additional
        lock.unlock()
    }

    func receive(subscription: Subscription) {
        onSubscription(subscription)
    }

    func receive(_ input: Input) -> Subscribers.Demand {
        lock.lock()
        guard demand.canDemand else {
            lock.unlock()
            return .none
        }
        demand = demand.demanding()
        lock.unlock()
        return onValue(input)
    }

    func receive(completion: Subscribers.Completion<Failure>) {
        onCompletion(completion)
    }
}

/// subject 内部使用的连接对象:request 累加需求,cancel 时把自己从 subject 移除。
private final class SubjectConnection: Subscription, @unchecked Sendable {
    private var isCancelled = false
    private let onDemand: (Subscribers.Demand) -> Void
    private let onCancel: () -> Void

    init(onDemand: @escaping (Subscribers.Demand) -> Void, onCancel: @escaping () -> Void) {
        self.onDemand = onDemand
        self.onCancel = onCancel
    }

    func request(_ demand: Subscribers.Demand) {
        guard !isCancelled else { return }
        onDemand(demand)
    }

    func cancel() {
        guard !isCancelled else { return }
        isCancelled = true
        onCancel()
    }
}
