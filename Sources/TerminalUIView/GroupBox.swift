/// 带可选标题和内边距的分组容器。
///
/// 内容先通过 `VStack` 纵向排列，再增加一格水平 padding，最外层由
/// `_BorderNode` 绘制边框。标题过长时会按终端 cell 宽度安全截断。
public struct GroupBox<Content: View>: View {
    let title: String?
    let titleAlignment: HorizontalAlignment
    let style: BorderStyle
    let content: Content

    /// 创建分组框。
    /// - Parameters:
    ///   - title: 显示在顶部边框上的标题；`nil` 表示不显示。
    ///   - titleAlignment: 标题在顶部边框中的水平位置。
    ///   - style: 边框字形样式。
    ///   - content: 分组内从上到下排列的子视图。
    public init(
        _ title: String? = nil,
        titleAlignment: HorizontalAlignment = .leading,
        style: BorderStyle = .rounded,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.titleAlignment = titleAlignment
        self.style = style
        self.content = content()
    }

    public var body: some View {
        VStack {
            content
            // background 不参与父视图测量，显式为标题保留最小宽度。
            Spacer(width: (title?.displayWidth ?? 0) + 2, height: 0)
        }
            .padding(horizontal: 1, vertical: 1)
            .background(
                ZStack {
                    _Box(style: style)
                    VStack {
                        HStack {
                            switch titleAlignment {
                            case .leading:
                                Spacer(width: 2)
                                Text(title ?? "")
                                Spacer()
                            case .center:
                                Spacer()
                                Text(title ?? "")
                                Spacer()
                            case .trailing:
                                Spacer()
                                Text(title ?? "")
                                Spacer(width: 2)
                            }
                        }
                        Spacer()
                    }
                }
            )
    }
}
