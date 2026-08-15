import Foundation

/// 可取消令牌。订阅方调用 `cancel()` 断开订阅。
public protocol Cancellable {
    func cancel()
}

/// 一次订阅连接。`request(_:)` 申请流量,`cancel()` 断开。
///
/// `Sendable` 允许 `receive(on:)` 等跨队列操作符把订阅对象捕获进 `@Sendable`
/// 闭包;具体实现负责自己的线程安全。
public protocol Subscription: Cancellable, Sendable {
    func request(_ demand: Subscribers.Demand)
}

/// 下游接收端。
public protocol Subscriber {
    associatedtype Input
    associatedtype Failure: Error

    func receive(subscription: Subscription)
    func receive(_ input: Input) -> Subscribers.Demand
    func receive(completion: Subscribers.Completion<Failure>)
}

/// 上游发布端。
public protocol Publisher {
    associatedtype Output
    associatedtype Failure: Error

    func receive<S: Subscriber>(subscriber: S)
        where S.Input == Output, S.Failure == Failure
}

/// 类型擦除的 Cancellable,方便把订阅句柄返回给调用方。
public final class AnyCancellable: Cancellable, @unchecked Sendable {
    private let _cancel: () -> Void

    public init(_ cancel: @escaping () -> Void) {
        _cancel = cancel
    }

    public init<C: Cancellable>(_ cancellable: C) {
        _cancel = { cancellable.cancel() }
    }

    public func cancel() {
        _cancel()
    }
}
