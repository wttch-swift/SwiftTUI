import Foundation

package struct _StateDependency: Hashable {
    package let id: ObjectIdentifier
    package let version: UInt64
}

/// 轻量级状态容器，语义上类似 SwiftUI 的 `@State`。
///
/// 当前实现把真实值直接保存在 wrapper 实例里，所以更适合挂在长期存在的
/// screen/view model class 上使用。后续如果 View 大量改成 struct 并频繁重建，
/// 可以把这里的 value 迁移到 runtime 托管的外部 storage，set 后仍然沿用
/// `TerminalStateRuntime.requestRender()` 这条通知链路。
@propertyWrapper
public final class State<Value> {
    private var value: Value
    private var version: UInt64 = 0

    /// 允许 timer、Combine sink、后台任务等跨线程读写状态。
    ///
    /// 注意：锁只保护 value 本身。真正的渲染不会在 set 所在线程发生，
    /// 而是通过 runtime post 一个事件，交给 TerminalApp 主循环统一处理。
    private let lock = NSLock()

    public var wrappedValue: Value {
        get {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
        set {
            lock.lock()
            value = newValue
            version &+= 1
            lock.unlock()

            /// `@State` 的赋值保持同步语义：上面的 value 已经写入完成。
            /// 这里仅请求 UI 在合适的时机重绘，不直接调用 render()。
            ///
            /// 这样按键、timer、Combine、网络消息等来源都能汇聚到同一个
            /// TerminalApp 事件循环里，避免多个线程同时绘制 terminal。
            TerminalStateRuntime.requestRender()
        }
    }

    /// `$state` 暴露为 Binding，子组件通过 Binding 读写父级状态。
    public var projectedValue: Binding<Value> {
        Binding(
            get: { [self] in wrappedValue },
            set: { [self] in wrappedValue = $0 },
            dependencies: { [self] in [dependency] }
        )
    }

    public init(wrappedValue: Value) {
        self.value = wrappedValue
    }

    package var dependency: _StateDependency {
        lock.lock()
        defer { lock.unlock() }
        return _StateDependency(id: ObjectIdentifier(self), version: version)
    }
}

/// 一个最小 Binding：由 getter/setter 组成，不拥有状态。
///
/// 它的职责是把父级 `@State` 的读写能力传给子组件，例如
/// `ProgressBar(value: $progress)`。写入 Binding 最终仍会回到原始 State，
/// 并触发同一条 render request。
public struct Binding<Value> {
    private let getter: () -> Value
    private let setter: (Value) -> Void
    private let dependencyProvider: () -> [_StateDependency]

    public var wrappedValue: Value {
        get { getter() }
        nonmutating set { setter(newValue) }
    }

    public init(get: @escaping () -> Value, set: @escaping (Value) -> Void) {
        self.getter = get
        self.setter = set
        self.dependencyProvider = { [] }
    }

    package init(
        get: @escaping () -> Value,
        set: @escaping (Value) -> Void,
        dependencies: @escaping () -> [_StateDependency]
    ) {
        self.getter = get
        self.setter = set
        self.dependencyProvider = dependencies
    }

    public static func constant(_ value: Value) -> Binding<Value> {
        Binding(get: { value }, set: { _ in })
    }

    package var dependencies: [_StateDependency] {
        dependencyProvider()
    }

    public func map<Mapped>(
        get: @escaping (Value) -> Mapped,
        set: @escaping (Mapped, Value) -> Value
    ) -> Binding<Mapped> {
        Binding<Mapped>(
            get: { get(wrappedValue) },
            set: { wrappedValue = set($0, wrappedValue) },
            dependencies: { dependencies }
        )
    }
}

/// 接收外部传入的 Binding，并把它伪装成当前对象上的普通属性。
///
/// 这相当于 SwiftUI 里的 `@Binding`，这里只是为了避免和标准库/框架命名混淆，
/// 目前叫 `@Bind`。
@propertyWrapper
public struct Bind<Value> {
    private var binding: Binding<Value>

    public var wrappedValue: Value {
        get { binding.wrappedValue }
        nonmutating set { binding.wrappedValue = newValue }
    }

    public var projectedValue: Binding<Value> {
        binding
    }

    public init(_ binding: Binding<Value>) {
        self.binding = binding
    }
}

/// TerminalApp 主循环能够处理的事件类型。
///
/// 所有异步状态来源都应该最终转换成这里的事件：
/// - `renderRequested` 来自 `@State`、未来的 `@StateObject`、Environment 变化等。
/// - `action` 给 timer / Combine / 网络回调使用，把状态修改切回主循环执行。
public enum TerminalAppEvent {
    /// 请求重绘。多个请求会被 `needsRender` 合并，通常一批事件只画一次。
    case renderRequested

    /// 任意需要在 TerminalApp 主循环执行的动作。
    ///
    /// 推荐 timer / Combine sink 使用这个事件包裹状态修改：
    /// `TerminalStateRuntime.post(.action { progress += 0.01 })`
    /// 这样状态变更和渲染都在同一条 UI 线程语义里完成。
    case action(() -> Void)

    /// 请求当前 TerminalApp.run() 退出。
    case stopRequested
}

/// 全局 runtime 桥接层：property wrapper 不直接持有 TerminalApp，
/// 只通过这里把事件交给当前正在运行的 app。
///
/// 现在只支持一个活动 TerminalApp，因为 eventHandler 是进程级 static。
/// 如果将来要同时跑多个 TerminalApp，可以把这层改成 per-app runtime/context。
public enum TerminalStateRuntime {
    private static let lock = NSLock()

    /// Swift 6 下闭包本身不是 Sendable，这里用 `nonisolated(unsafe)` 表明：
    /// 访问由上面的 NSLock 保护，调用方需要遵守 runtime 的单 app 约束。
    nonisolated(unsafe) private static var eventHandler: ((TerminalAppEvent) -> Void)?

    /// TerminalApp.run() 启动时注册 handler，退出时清空。
    public static func setEventHandler(_ handler: ((TerminalAppEvent) -> Void)?) {
        lock.lock()
        eventHandler = handler
        lock.unlock()
    }

    /// 从任意事件来源投递事件。
    ///
    /// 这里故意在锁外调用 handler，避免 handler 内部再次 post 事件时造成死锁。
    public static func post(_ event: TerminalAppEvent) {
        lock.lock()
        let handler = eventHandler
        lock.unlock()

        handler?(event)
    }

    /// 状态对象使用的便捷入口。
    ///
    /// 后续 `@StateObject`、`@Environment` 如果影响 UI，也应该走这个方法，
    /// 而不是直接触碰 TerminalApp 或 Canvas。
    static func requestRender() {
        post(.renderRequested)
    }

    /// 结束当前活动的 TerminalApp 事件循环。
    public static func stop() {
        post(.stopRequested)
    }
}
