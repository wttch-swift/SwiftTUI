import Foundation

/// 可取消令牌。
///
/// 所有订阅连接都应实现本协议:调用方持有返回的句柄,`cancel()` 后上游不再
/// 向下游投递任何事件。订阅方可以随时调用,包括在事件回调中途。
public protocol Cancellable {
    func cancel()
}

/// 一次订阅连接,订阅方通过它向上游申请流量或取消订阅。
///
/// `Sendable` 是刻意要求的:像 `receive(on:)` 这样的跨队列操作符需要把
/// `Subscription` 捕获进 `@Sendable` 闭包投递到目标队列。线程安全由具体
/// 实现负责(本库内部用 `NSLock` 或串行队列保证)。
public protocol Subscription: Cancellable, Sendable {
    func request(_ demand: Subscribers.Demand)
}

/// 下游接收端。
///
/// 这是反应链的终点协议。上游 publisher 通过 `receive(subscriber:)` 接入一个
/// 具体订阅者,之后按事件先后依次回调:
///
/// - `receive(subscription:)`:先建立连接,必须同步发生;
/// - `receive(_:)`:投递值,返回值表示背压需求;
/// - `receive(completion:)`:恰好一次地终止流。
///
/// `Input` / `Failure` 必须与 publisher 的 `Output` / `Failure` 严格对应,
/// 由 `Publisher.receive(subscriber:)` 的泛型约束在编译期保证类型一致。
public protocol Subscriber {
    associatedtype Input
    associatedtype Failure: Error

    func receive(subscription: Subscription)
    func receive(_ input: Input) -> Subscribers.Demand
    func receive(completion: Subscribers.Completion<Failure>)
}

/// 上游发布端。
///
/// 反应式管道的源头。`receive(subscriber:)` 是管道唯一的入口:调用方创建
/// 订阅者并交给 publisher,后续所有事件都通过订阅者回调驱动,发布端本身
/// 不持有任何下游的具体类型。
public protocol Publisher {
    associatedtype Output
    associatedtype Failure: Error

    func receive<S: Subscriber>(subscriber: S)
        where S.Input == Output, S.Failure == Failure
}

/// 类型擦除的可取消令牌。
///
/// 需要把"取消"这个动作保存下来稍后触发时(例如 `sink` 返回句柄),用闭包
/// 擦除掉具体的订阅者类型,调用方看到的只是一个可以 `cancel()` 的句柄。
/// `AnyCancellable` 的 `deinit` 不隐式取消,与 Combine 语义一致。
///
/// `@unchecked Sendable`:`cancel()` 可能在任意线程被调用,而底层 `_cancel`
/// 闭包捕获的订阅者未必是 `Sendable`;这里由调用方保证取消与订阅生命周期
/// 不同步竞争,与 Combine 的 `AnyCancellable` 语义一致。
public final class AnyCancellable: Cancellable, @unchecked Sendable {
    /// 擦除后的取消动作;初始化时把"具体订阅者的取消"固化进闭包。
    private let _cancel: () -> Void

    public init(_ cancel: @escaping () -> Void) {
        _cancel = cancel
    }

    /// 用任意 `Cancellable` 构造:取消时转发给它的 `cancel()`。
    public init<C: Cancellable>(_ cancellable: C) {
        _cancel = { cancellable.cancel() }
    }

    public func cancel() {
        _cancel()
    }
}
