import Foundation

/// Combine 式命名空间:Completion / Demand / Sink。
public enum Subscribers {
    /// 流终止信号:正常结束或失败。
    public enum Completion<Failure: Error> {
        case finished
        case failure(Failure)
    }

    /// 背压需求。`.unlimited` 表示不限量;`.max(n)` 表示最多再投递 n 个值。
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
