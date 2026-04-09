/// 声明式终端界面的基础协议，保持与 SwiftUI `View` 相同的 body 模型。
public protocol View {
    associatedtype Body: View

    @ViewBuilder
    var body: Body { get }
}
