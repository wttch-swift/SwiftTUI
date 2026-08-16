# WttchCombine

一个**最小 Combine**:协议骨架 + Demand 背压 + `DispatchQueue` 作调度器,不依赖任何
TerminalUI target,也不依赖 Apple Combine。

## 组成

| 类型 | 作用 |
| --- | --- |
| `Publisher` / `Subscriber` / `Subscription` / `Cancellable` | 订阅契约四件套 |
| `Subscribers.Completion` / `Demand` / `Sink` | 终止信号、背压计数、终结订阅者 |
| `PassthroughSubject<Output, Failure>` | 任意线程 `send(_:)`,订阅者同步收到值 |
| `AnyCancellable` | 类型擦除的取消句柄 |
| `map` / `receive(on:)` / `sink` | 同步变换、DispatchQueue 投递、终结订阅 |
| `debounce(for:queue:)` | 把高频突发值收敛为静默期满后的最后一个值 |

## 使用

```swift
let subject = PassthroughSubject<Int, Never>()
let token = subject
    .map { $0 * 10 }
    .receive(on: someQueue)          // 可选:在指定串行队列投递
    .debounce(for: .milliseconds(300), queue: someQueue)   // 可选:输入防抖
    .sink { print($0) }
subject.send(1)                      // 打印 10
token.cancel()                       // 断开订阅
```

## 与真 Combine 的差距

- 无 `AnyPublisher` / `AnySubscriber` 类型擦除,类型会一路携带具体链。
- Demand 只有 `.none` / `.unlimited` / `.max(n)` 基础计数,无 `Subscription` 暂停语义。
- 操作符集合很小,无 `flatMap` / `combineLatest` 等。
- `sink` 只重载了 `Failure == Never`;`Failure` 非 `Never` 的流需自定义 Subscriber。

## Swift 6 并发

线程安全类(`PassthroughSubject`、`Sink`、内部箱、`ReceiveOnSubscriber`、`DebounceSubscriber`)标注
`@unchecked Sendable`(内部锁或队列串行化保证);协议要求本身不加并发注解,跨线程
投递责任归调用方。`Subscription: Sendable`,使 `receive(on:)` 能把订阅对象捕获进
`@Sendable` 闭包。
