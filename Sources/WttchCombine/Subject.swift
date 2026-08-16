import Foundation

/// 手动驱动的发布端:任意线程 `send(_:)`,订阅者同步收到值。
///
/// 这是把"值产生"与"值消费"解耦的桥:生产者调用 `send`,不关心谁在听;
/// 消费者订阅,不关心值从哪来。类似一个没有缓冲的多播广播器。
///
/// 线程安全:订阅者列表由 `NSLock` 保护,`send` 取快照后再逐个回调,因此
/// 回调不持锁(持锁调用任意用户代码是死锁高危区);"谁先订阅谁先收到"
/// 的顺序由列表顺序保证,且中途订阅/退订不影响本次投递。
///
/// 已完成(subject 发过 completion)之后不再接受新订阅者。
public final class PassthroughSubject<Output, Failure: Error>: Publisher, @unchecked Sendable {
    public typealias Output = Output
    public typealias Failure = Failure

    private let lock = NSLock()
    private var boxes: [Box<Output, Failure>] = []

    public init() {}

    /// 向当前所有订阅者同步发送一个值。
    ///
    /// 取订阅者快照后逐个回调,所以本次投递不因回调中途的订阅/退订而变。
    /// 每个订阅者按自己的 demand 决定收不收该值。
    public func send(_ value: Output) {
        for box in snapshot() {
            _ = box.receive(value)
        }
    }

    /// 终止所有订阅者。
    ///
    /// 先发 completion,再清空订阅者列表:发完即置为不可再订阅,
    /// 也避免之后的 `send` 投给已完成的订阅者。
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
        // 每个订阅者用一个 Box 擦除,才能异构地放进数组。
        let box = Box(subscriber)
        // 连接对象把"请求流量"与"退订"两件事委托回 subject/box:
        // 请求累加到 box 的 demand;退订按引用相等把 box 从列表移除。
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

    /// 线程安全地取订阅者快照:回调放在锁外执行,避免持锁调用任意用户代码。
    private func snapshot() -> [Box<Output, Failure>] {
        lock.lock()
        defer { lock.unlock() }
        return boxes
    }
}

/// 订阅箱:把任意 Subscriber 用闭包擦除成统一类型,subject 才能异构存储。
///
/// 每个订阅者一个 Box,Box 同时充当"当前订阅是否还活着"的判定对象
/// (退订时按引用相等从 subject 的数组移除)。
///
/// 背压:Box 把订阅者每次 `request` 的 demand 累加起来,`receive(_:)` 时先
/// 检查、扣减再回调下游;demand 为零时直接返回 `.none` 丢弃该值。
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

    /// 把订阅者的流量请求累加到 demand。
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
///
/// 每个订阅对应一个 SubjectConnection;`onDemand` / `onCancel` 各只触发一次
/// (内部用 `isCancelled` 做幂等保护),避免重复请求或重复退订。
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
