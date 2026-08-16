import Dispatch
import Foundation

/// `map` 操作符:同步变换值。
///
/// 每个值到达 `MapSubscriber.receive(_:)` 时立刻套用 `transform`,
/// 再把结果原样转交给下游。同步、无缓冲、不跨线程,是反应链里最廉价的一环。
public struct Map<Upstream: Publisher, Mapped>: Publisher {
    public typealias Output = Mapped
    public typealias Failure = Upstream.Failure

    /// 上游 publisher,事件流真正的来源。
    private let upstream: Upstream
    /// 值变换函数:把上游的 `Output` 变成下游要的 `Mapped`。
    private let transform: (Upstream.Output) -> Mapped

    public init(upstream: Upstream, transform: @escaping (Upstream.Output) -> Mapped) {
        self.upstream = upstream
        self.transform = transform
    }

    /// 把下游订阅者包装成 `MapSubscriber` 再交给上游。
    ///
    /// 类型映射:上游的 `Output` 是 `MapSubscriber` 的 `Input`,
    /// 下游的 `Input` 必须是变换后的 `Mapped`。
    public func receive<S: Subscriber>(subscriber: S)
        where S.Input == Mapped, S.Failure == Upstream.Failure {
        upstream.receive(subscriber: MapSubscriber<Upstream.Output, S, Mapped>(
            downstream: subscriber, transform: transform))
    }
}

/// `Map` 的内部订阅者:把上游事件转接到下游,值经 `transform` 变换后转发。
///
/// 生命周期与订阅一一对应,无需自加锁:它只被上游在同一线程串行回调,
/// 并把下游的订阅/值/完成事件原样透传。
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
/// 上游仍在原线程产生事件,本操作符负责把它们搬到目标队列——常用于把 UI 更新
/// 放到主队列、把 IO 结果放回后台队列等。
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
///
/// `DispatchQueue.async` 的闭包要求 `@Sendable`,而非 Sendable 的载荷(值、完成事件、
/// 下游引用)不能直接捕获。本箱把载荷包一层:箱体是 `@unchecked Sendable`,
/// 允许进入队列闭包;箱内值只在目标队列上解箱读取,装箱与拆箱之间不存在
/// 跨线程并发访问,因此这一"不检查"是安全的。
private final class SendableBox<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) {
        self.value = value
    }
}

/// `ReceiveOn` 的内部订阅者:把上游事件装箱后投递到目标队列,由队列串行化隔离。
///
/// 线程模型:下游 `downstream` 只在目标 `queue` 上被触碰;`receive(subscription:)`
/// 中的同步 `request(.unlimited)` 是唯一例外——它必须赶在任何 `send` 之前生效,
/// 因此不能跟着订阅一起排队,而是在任意线程同步执行(Subscription 本身是 Sendable,
/// 它的线程安全由实现保证)。
///
/// Swift 并发细节:泛型 `Downstream` 的元类型 `Downstream.Type` 不是 `Sendable`。
/// 若在 `queue.async` 的 `@Sendable` 闭包里直接写 `self.downstream.receive(...)`,
/// 静态协议分发需要元类型作 witness 表,闭包就会捕获 `Downstream.Type` 并触发
/// `SendableMetatypes` 诊断;把泛型值提成局部变量也躲不开(`#SendableClosureCaptures`
/// 同时还会报)。因此这里把三个转发动作在 `init` 里擦成普通(非 `@Sendable`)闭包
/// 并装箱:普通闭包可以安全持有泛型上下文(值 + 元类型都进它的捕获),之后队列闭包
/// 只捕获"已实例化的具体装箱值",不再需要任何泛型元类型。`@unchecked Sendable`
/// 同样是刻意的——转发闭包与载荷都由目标队列串行化保证互斥。
private final class ReceiveOnSubscriber<Downstream: Subscriber>: Subscriber, @unchecked Sendable {
    typealias Input = Downstream.Input
    typealias Failure = Downstream.Failure

    /// 目标队列:所有下游回调都在这里串行执行。
    private let queue: DispatchQueue
    /// 三个转发动作的装箱版本,`init` 里一次擦除,之后队列闭包只调用 `value`。
    private let forwardSubscription: SendableBox<(Subscription) -> Void>
    private let forwardValue: SendableBox<(Downstream.Input) -> Void>
    private let forwardCompletion: SendableBox<(Subscribers.Completion<Downstream.Failure>) -> Void>

    init(downstream: Downstream, queue: DispatchQueue) {
        self.queue = queue
        // 非隔离上下文里构建普通闭包,可以安全捕获泛型 Downstream 的值与元类型;
        // 下游被闭包强持有,随闭包一并进入队列,生命周期由队列语义保证。
        self.forwardSubscription = SendableBox { subscription in
            downstream.receive(subscription: subscription)
        }
        self.forwardValue = SendableBox { input in
            _ = downstream.receive(input)
        }
        self.forwardCompletion = SendableBox { completion in
            downstream.receive(completion: completion)
        }
    }

    func receive(subscription: Subscription) {
        // 同步向上游申请 unlimited 流量,避免下游的订阅还在队列里时 send 被丢。
        subscription.request(.unlimited)
        // 先提到局部再进闭包:局部是已实例化的具体装箱值,不携带泛型元类型。
        let forward = forwardSubscription
        queue.async { forward.value(subscription) }
    }

    func receive(_ input: Input) -> Subscribers.Demand {
        let box = SendableBox(input)
        let forward = forwardValue
        queue.async { forward.value(box.value) }
        return .unlimited
    }

    func receive(completion: Subscribers.Completion<Failure>) {
        let box = SendableBox(completion)
        let forward = forwardCompletion
        queue.async { forward.value(box.value) }
    }
}

/// `debounce(for:queue:)`:把突发的高频事件收敛为"静默期满后的最后一个值"。
///
/// 每个值到达时重置计时器,只有连续 `dueTime` 内没有新值(静默期满)时,才把
/// 期间最后一个值投递给下游。常用于搜索框输入、窗口缩放等"频繁变化、只关心
/// 停下来的结果"的场景。
///
/// 与 Combine 语义一致:上游完成后,尚未到期投递的待定值被丢弃,完成信号立即
/// 透传,不会因为防抖窗口未过而拖延。
public struct Debounce<Upstream: Publisher>: Publisher {
    public typealias Output = Upstream.Output
    public typealias Failure = Upstream.Failure

    private let upstream: Upstream
    private let dueTime: DispatchTimeInterval
    private let queue: DispatchQueue

    public init(upstream: Upstream, dueTime: DispatchTimeInterval, queue: DispatchQueue) {
        self.upstream = upstream
        self.dueTime = dueTime
        self.queue = queue
    }

    public func receive<S: Subscriber>(subscriber: S)
        where S.Input == Upstream.Output, S.Failure == Upstream.Failure {
        upstream.receive(subscriber: DebounceSubscriber(downstream: subscriber, dueTime: dueTime, queue: queue))
    }
}

/// `Debounce` 的内部订阅者:维护"待投递值 + 到期任务",每个值到达即重置到期时间。
///
/// 线程模型:上游事件在任意线程到达(`receive(_:)` / `receive(completion:)`),
/// 到期投递在目标 `queue` 上执行;待定值与到期任务由 `NSLock` 串行化。下游的
/// 值回调只在目标 `queue` 上发生;完成回调随上游线程同步透传(与 Combine 一致,
/// 完成不排队等待防抖窗口)。
///
/// 投递任务的身份判定:每个待投递值用一个 `SendableBox` 装住,`pending` 持有当前
/// 箱;到期任务在锁内用 `===` 校验自己装的值箱仍是当前待投递值才真正投递。这样
/// 一个已出队、正在执行的旧任务撞上新值到达时不会误投新值、也不会错清当前任务
/// (普通"取走 pending 即投"的写法在这个窗口会把新值提前投出去)。
private final class DebounceSubscriber<Downstream: Subscriber>: Subscriber, @unchecked Sendable {
    typealias Input = Downstream.Input
    typealias Failure = Downstream.Failure

    private let downstream: Downstream
    private let dueTime: DispatchTimeInterval
    private let queue: DispatchQueue
    /// 值投递的装箱版本:到期任务在 `@Sendable` 闭包里只调用它,规避泛型元类型
    /// 被捕获触发的 `SendableMetatypes` 诊断(理由同 `ReceiveOnSubscriber`)。
    private let forwardValue: SendableBox<(Downstream.Input) -> Void>

    private let lock = NSLock()
    /// 当前待投递值(装箱以提供身份比较);新值到达时被替换。
    private var pending: SendableBox<Downstream.Input>?
    /// 当前排定的到期任务;新值到达或上游完成时被取消。
    private var workItem: DispatchWorkItem?
    /// 上游是否已完成;完成后的 `send`(契约外)被忽略。
    private var isFinished = false

    init(downstream: Downstream, dueTime: DispatchTimeInterval, queue: DispatchQueue) {
        self.downstream = downstream
        self.dueTime = dueTime
        self.queue = queue
        self.forwardValue = SendableBox { input in
            _ = downstream.receive(input)
        }
    }

    func receive(subscription: Subscription) {
        // 同步向上游请求 unlimited:防抖必须看到每个值,才能判定"静默期满",
        // 否则最后几个值可能因 demand 不足到不了本操作符。连接原样转发给下游,
        // 取消仍由下游经同一连接触发。
        subscription.request(.unlimited)
        downstream.receive(subscription: subscription)
    }

    func receive(_ input: Input) -> Subscribers.Demand {
        lock.lock()
        guard !isFinished else {
            lock.unlock()
            return .none
        }
        // 重置:取消旧的到期任务,用新值重新排定。
        workItem?.cancel()
        let valueBox = SendableBox(input)
        pending = valueBox
        let forward = forwardValue
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.takePending(valueBox) else { return }
            forward.value(valueBox.value)
        }
        self.workItem = workItem
        queue.asyncAfter(deadline: .now() + dueTime, execute: workItem)
        lock.unlock()
        // 与 `ReceiveOn` 一致:本操作符不追踪下游回传的 demand,一律按 unlimited 继续。
        return .unlimited
    }

    func receive(completion: Subscribers.Completion<Failure>) {
        lock.lock()
        isFinished = true
        // 丢弃尚未投递的待定值:防抖只等在途的"静默",不拖延完成。
        workItem?.cancel()
        workItem = nil
        pending = nil
        lock.unlock()
        downstream.receive(completion: completion)
    }

    /// 到期任务执行时校验并取走自己的待投递值。
    ///
    /// 仅当 `valueBox` 仍是当前待投递值时返回 `true` 并清空状态;若期间已有
    /// 更新的值接管(或上游已完成清掉了 pending),返回 `false`,本任务作废。
    private func takePending(_ valueBox: SendableBox<Downstream.Input>) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard pending === valueBox else { return false }
        pending = nil
        workItem = nil
        return true
    }
}

// MARK: - Publisher 扩展入口

public extension Publisher {
    /// 终结订阅,返回可取消句柄。仅适用于 `Failure == Never` 的流。
    ///
    /// 收到每个值调用 `receiveValue`;流结束时静默忽略。底层创建一个
    /// `Subscribers.Sink` 并立即请求 unlimited 流量,所以从订阅那一刻起
    /// 每个值都会到达。想处理完成事件时,用 `Subscribers.Sink` 的完整
    /// 初始化形式(`receiveCompletion`)。
    func sink(receiveValue: @escaping (Output) -> Void) -> AnyCancellable where Failure == Never {
        let sink = Subscribers.Sink<Output, Failure>(receiveValue: receiveValue)
        receive(subscriber: sink)
        return AnyCancellable(sink)
    }

    /// 同步变换每个值,返回 `Map` publisher。
    ///
    /// 变换在值到达时立刻执行、不跨线程;闭包应当无副作用或只做纯计算,
    /// 否则副作用发生的时机(原线程)可能与预期不符。
    func map<Mapped>(_ transform: @escaping (Output) -> Mapped) -> Map<Self, Mapped> {
        Map(upstream: self, transform: transform)
    }

    /// 在指定 DispatchQueue 上异步投递事件。
    ///
    /// 事件在目标队列上串行执行,顺序与上游产生顺序一致;`send` 返回时事件
    /// 未必已投递。常用于把昂贵计算或 IO 挪出主队列、再切回主队列更新 UI。
    func receive(on queue: DispatchQueue) -> ReceiveOn<Self> {
        ReceiveOn(upstream: self, queue: queue)
    }

    /// 把快速连续到达的值收敛为"静默期满后的最后一个值"。
    ///
    /// 每个值到达都会重置 `dueTime` 计时,只有连续 `dueTime` 内没有新值时,
    /// 才把最后一个值投递到下游,投递发生在 `queue` 上。上游完成时待定值被
    /// 丢弃、完成信号立即透传。常用于搜索框输入等"只关心停下来的结果"的场景。
    func debounce(for dueTime: DispatchTimeInterval, queue: DispatchQueue) -> Debounce<Self> {
        Debounce(upstream: self, dueTime: dueTime, queue: queue)
    }
}
