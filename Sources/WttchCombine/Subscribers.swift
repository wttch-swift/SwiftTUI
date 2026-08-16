import Foundation

/// Combine 式命名空间:Completion / Demand / Sink。
public enum Subscribers {
    /// 流终止信号:正常结束或失败。一个流恰好收到一次,之后不再有值。
    public enum Completion<Failure: Error> {
        case finished
        case failure(Failure)
    }

    /// 背压需求。订阅者通过返回值告诉上游"还能投多少"。
    ///
    /// - `.unlimited`:不限量(内部用 `Int.max` 表示,与 `+` 运算配合不递减)。
    /// - `.max(n)`:最多再投递 `n` 个值,每投一个递减一。
    /// - `.none`:暂停投递。
    public struct Demand: Equatable, Sendable {
        /// 无穷大,始终可投递。
        public static let unlimited = Demand(.max)
        /// 不再投递。
        public static let none = Demand(0)

        /// 剩余可投递数量;`.unlimited` 用 `Int.max` 表示。
        public let count: Int

        public init(_ count: Int) {
            self.count = Swift.max(0, count)
        }

        /// 最多再投递 `n` 个值;`n <= 0` 视为 `.none`。
        public static func max(_ n: Int) -> Demand {
            Demand(n)
        }

        /// 加法合并需求(累加订阅者的多次请求)。
        ///
        /// 任意一方为 unlimited,或相加溢出 `Int.max`,结果都是 unlimited——
        /// 需求只会越借越多,不可能借到退回去。
        public static func + (lhs: Demand, rhs: Demand) -> Demand {
            let (a, b) = (lhs.count, rhs.count)
            if a == .max || b == .max || a > .max - b {
                return .unlimited
            }
            return Demand(a + b)
        }

        /// 是否允许再投递一个值。
        var canDemand: Bool {
            count != 0
        }

        /// 投递一个值后剩余的需求(非 unlimited 时递减)。
        func demanding() -> Demand {
            guard count != .max else { return self }
            return Demand(count - 1)
        }
    }

    /// 最常用的终结订阅者:收到值就调用闭包,请求 unlimited 流量。
    ///
    /// 通常由 `Publisher.sink` 创建并立即订阅;持有者调用 `cancel()` 断开订阅,
    /// 取消后再次收到的事件会被忽略(因为订阅已被取消)。
    ///
    /// 线程安全:对 `subscription` 的读写都经 `NSLock` 串行化,因此 `receive`
    /// 与 `cancel` 可以来自不同线程;`receive(subscription:)` 在锁内先保存再
    /// 锁外请求,避免在持锁时回调用户代码造成死锁。
    public final class Sink<Input, Failure: Error>: Subscriber, Cancellable, @unchecked Sendable {
        private let onValue: (Input) -> Void
        private let onCompletion: (Completion<Failure>) -> Void
        private let lock = NSLock()
        private var subscription: (any Subscription)?

        public init(
            receiveValue: @escaping (Input) -> Void,
            receiveCompletion: @escaping (Completion<Failure>) -> Void = { _ in }
        ) {
            onValue = receiveValue
            onCompletion = receiveCompletion
        }

        public func receive(subscription: Subscription) {
            lock.lock(); self.subscription = subscription; lock.unlock()
            subscription.request(.unlimited)
        }

        public func receive(_ input: Input) -> Demand {
            onValue(input)
            return .unlimited
        }

        public func receive(completion: Completion<Failure>) {
            onCompletion(completion)
        }

        public func cancel() {
            lock.lock()
            let subscription = self.subscription
            self.subscription = nil
            lock.unlock()
            subscription?.cancel()
        }
    }
}
