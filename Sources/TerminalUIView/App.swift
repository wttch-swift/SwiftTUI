/// 终端应用的协议，类似于 SwiftUI 的 `App` 协议。
///
/// 符合该协议的类型可以使用 `@main` 标记，自动获得终端尺寸检测、
/// 事件循环和渲染能力。
///
/// ```swift
/// @main
/// struct MyApp: TerminalApp {
///     var body: some View {
///         Text("Hello, terminal!")
///     }
/// }
/// ```
public protocol TerminalApp {
    associatedtype Body: View

    init()

    @ViewBuilder
    var body: Body { get }
}
