import Foundation
import TerminalUI

@main
struct ShengjiCmd: TerminalApp {
    let isWide: Bool

    init() {
        let size = TerminalSizeReader.current(or: TerminalSize(columns: 108, rows: 32))
        isWide = size.width >= 96
    }

    var body: some View {
        ObservatoryDemo(isWide: isWide)
    }
}

private enum ObservatoryTab: Hashable {
    case overview
    case activity
    case settings
    case chat
}

private struct ServiceSnapshot: Identifiable {
    let id: Int
    let name: String
    let region: String
    let status: String
    let load: Int
    let latency: String
}

private struct EventRecord: Identifiable {
    let id: Int
    let time: String
    let source: String
    let message: String
    let level: String
}

private struct ChatMessage: Identifiable {
    enum Role {
        case user
        case assistant
    }

    let id: Int
    let role: Role
    let content: String
    let timestamp: String
}

private struct ChatConversation: Identifiable {
    let id: Int
    var title: String
    var summary: String
    var updatedAt: String
    var messages: [ChatMessage]
}

private struct SelectedMessageKey: Hashable {
    let conversationID: Int
    let messageID: Int
}

private struct ObservatoryDemo: View {
    private enum Field: Hashable {
        case operatorNote
        case chatHistory
        case chatMessage
        case deepseekKey
        case deepseekPrompt
        case hexoRepoPath
        case markdownTitle
    }

    let isWide: Bool

    @State private var selection = ObservatoryTab.overview
    @State private var refreshCount = 0
    @State private var liveUpdates = true
    @State private var notifications = true
    @State private var compactRows = false
    @State private var operatorNote = ""
    @State private var savedNote = "尚未保存操作备注。"
    @State private var chatDraft = ""
    @State private var chatStatus = "Tab 聚焦记录/输入 · 记录区 ↑↓ 翻页 · A 配置 AI · X 选择回答"
    @State private var showsSheet = false
    @State private var showsAIConfigSheet = false
    @State private var showsMarkdownSheet = false
    @State private var showsDebugMetricsToast = false
    @State private var showsToast = false
    @State private var activeConversationID = 0
    @State private var selectedMessageKeys: Set<SelectedMessageKey> = [
        SelectedMessageKey(conversationID: 0, messageID: 2),
        SelectedMessageKey(conversationID: 1, messageID: 1),
    ]
    @State private var isSelectingMessages = false
    @State private var deepseekAPIKey = ""
    @State private var deepseekSystemPrompt = "你是一个帮助我把聊天记录整理成 Hexo 博客草稿的写作助手。请保留事实、提炼结构，并使用中文 Markdown。"
    @State private var hexoRepositoryPath = "~/workspace/blog"
    @State private var markdownTitle = "一次终端 AI 助手的设计记录"
    @State private var generatedMarkdown = "尚未生成 Markdown 草稿。"
    @State private var draftStatus = "选择回答后按 G 生成草稿。"
    @FocusState private var focusedField: Field?
    @State private var conversations = [
        ChatConversation(
            id: 0,
            title: "TerminalUI 渲染优化",
            summary: "双缓冲、RenderCache、fingerprint 与 benchmark",
            updatedAt: "今天 19:36",
            messages: [
                ChatMessage(
                    id: 0,
                    role: .assistant,
                    content: "欢迎来到命令行写作助手。我可以把多段技术对话整理成 Hexo Markdown 草稿。",
                    timestamp: "19:10"
                ),
                ChatMessage(
                    id: 1,
                    role: .user,
                    content: "记录一下 RenderCache 和双缓冲的优化结论。",
                    timestamp: "19:12"
                ),
                ChatMessage(
                    id: 2,
                    role: .assistant,
                    content: "可以。当前渲染路径已经能统计 body 展开、layout、draw、fingerprint、cache lookup、paste 和输出生成等阶段。",
                    timestamp: "19:12"
                ),
                ChatMessage(
                    id: 3,
                    role: .user,
                    content: "如果后续要写成博客，哪些结论值得保留？",
                    timestamp: "19:18"
                ),
                ChatMessage(
                    id: 4,
                    role: .assistant,
                    content: "最值得保留的是优化链路：先做按行 diff 减少输出，再用双缓冲减少 Canvas 分配，最后用 RenderCache 复用稳定叶子节点的 cell 快照。",
                    timestamp: "19:18"
                ),
                ChatMessage(
                    id: 5,
                    role: .assistant,
                    content: "benchmark 也很重要。它把完整帧拆成清空画布、View body 展开、布局、渲染遍历、输出生成和缓存内部耗时，因此能解释每一步为什么变快。",
                    timestamp: "19:19"
                ),
                ChatMessage(
                    id: 6,
                    role: .user,
                    content: "那焦点和事件系统怎么描述？",
                    timestamp: "19:22"
                ),
                ChatMessage(
                    id: 7,
                    role: .assistant,
                    content: "可以写成第二节：统一事件队列负责收敛键盘、信号、状态变化和自定义消息；事件被消费后停止传播，主循环在事件批处理后统一重绘。",
                    timestamp: "19:22"
                ),
            ]
        ),
        ChatConversation(
            id: 1,
            title: "SwiftUI 风格事件系统",
            summary: "统一事件队列、onEvent、消费后停止传播",
            updatedAt: "今天 19:40",
            messages: [
                ChatMessage(
                    id: 0,
                    role: .user,
                    content: "事件队列能不能做成 SwiftUI 风格的 onEvent？",
                    timestamp: "19:30"
                ),
                ChatMessage(
                    id: 1,
                    role: .assistant,
                    content: "可以。内部保留 TerminalRuntimeEvent，公开给视图的是 TerminalEvent，并提供 onEvent、onResize、onSignal 和 onMessage。",
                    timestamp: "19:31"
                ),
            ]
        ),
        ChatConversation(
            id: 2,
            title: "Hexo 发布流程",
            summary: "把生成的 Markdown 放入 Hexo 仓库，由 GitHub Actions 发布",
            updatedAt: "待整理",
            messages: [
                ChatMessage(
                    id: 0,
                    role: .user,
                    content: "最终草稿要放到 Hexo 仓库中，由 GitHub Actions 自动发布。",
                    timestamp: "19:45"
                ),
                ChatMessage(
                    id: 1,
                    role: .assistant,
                    content: "后续可以把生成草稿写入 source/_posts，再由仓库已有 workflow 完成构建发布。",
                    timestamp: "19:45"
                ),
            ]
        ),
    ]

    private let services = [
        ServiceSnapshot(id: 0, name: "极光接口", region: "上海", status: "正常", load: 42, latency: "18 毫秒"),
        ServiceSnapshot(id: 1, name: "向量仓库", region: "东京", status: "正常", load: 67, latency: "31 毫秒"),
        ServiceSnapshot(id: 2, name: "事件流", region: "新加坡", status: "同步中", load: 81, latency: "44 毫秒"),
        ServiceSnapshot(id: 3, name: "边缘缓存", region: "悉尼", status: "正常", load: 29, latency: "12 毫秒"),
    ]

    private let events = [
        EventRecord(id: 0, time: "01:14:08", source: "极光接口", message: "部署完成", level: "信息"),
        EventRecord(id: 1, time: "01:13:42", source: "事件流", message: "副本已追平", level: "同步"),
        EventRecord(id: 2, time: "01:12:19", source: "向量仓库", message: "索引压缩完成", level: "信息"),
        EventRecord(id: 3, time: "01:10:03", source: "边缘缓存", message: "命中率达到 96%", level: "良好"),
        EventRecord(id: 4, time: "01:08:51", source: "调度器", message: "快照已归档", level: "信息"),
        EventRecord(id: 5, time: "01:06:22", source: "极光接口", message: "健康检查通过", level: "良好"),
        EventRecord(id: 6, time: "01:03:17", source: "向量仓库", message: "分片重新均衡", level: "同步"),
        EventRecord(id: 7, time: "00:58:40", source: "边缘缓存", message: "配置已重新载入", level: "信息"),
        EventRecord(id: 8, time: "00:54:06", source: "调度器", message: "备份窗口已开启", level: "信息"),
        EventRecord(id: 9, time: "00:49:33", source: "事件流", message: "检查点已提交", level: "良好"),
    ]

    var body: some View {
        DebugMetricsReader { metrics in
            ZStack {
                Spacer()
                    .backgroundColor(.rgb(8, 13, 24))

                TabView(selection: tabSelection) {
                    overviewPage
                        .tabItem { Text("◇ 概览") }
                        .tag(ObservatoryTab.overview)
                    activityPage
                        .tabItem { Text("≋ 动态") }
                        .tag(ObservatoryTab.activity)

                    settingsPage
                        .tabItem { Text("⚙ 设置") }
                        .tag(ObservatoryTab.settings)

                    chatPage
                        .tabItem { Text("◈ 智能对话") }
                        .tag(ObservatoryTab.chat)
                }
                .foregroundColor(.rgb(203, 213, 225))
            }
            .onKeyPress { event in
                handleGlobalKey(event)
            }
            .sheet(isPresented: $showsSheet, alignment: .center) {
                VStack(alignment: .center) {
                    Text("九宫格弹出框")
                        .foregroundColor(.brightWhite)
                        .bold()
                    Spacer(height: 1)
                    Text("当前位于屏幕中央")
                        .foregroundColor(.brightCyan)
                    Text("同一接口支持九个对齐方向")
                        .foregroundColor(.rgb(148, 163, 184))
                    Spacer(height: 1)
                    Text("按退出键关闭")
                        .foregroundColor(.brightYellow)
                }
            }
            .sheet(isPresented: $showsAIConfigSheet, alignment: .center) {
                aiConfigSheet
            }
            .sheet(isPresented: $showsMarkdownSheet, alignment: .center) {
                markdownDraftSheet
            }
            .toast(isPresented: $showsToast, alignment: .topTrailing) {
                Text("✓ 快照已刷新 #\(refreshCount)")
            }
            .toast(isPresented: $showsDebugMetricsToast, alignment: .bottomTrailing) {
                debugMetricsToast(metrics)
            }
        }
    }

    private var overviewPage: some View {
        GeometryReader { geometry in
            VStack {
                masthead(
                    section: "网络概览",
                    detail: "\(geometry.size.w)×\(geometry.size.h) 画布"
                )
                Spacer(height: 1)

                HStack {
                    GroupBox("系统脉搏", style: .rounded) {
                        metric(label: "处理", value: 0.42, text: "42%", color: .brightCyan)
                        Spacer(height: 1)
                        metric(label: "内存", value: 0.68, text: "68%", color: .brightMagenta)
                        Spacer(height: 1)
                        metric(label: "网络", value: 0.31, text: "1.8 吉字节/秒", color: .brightGreen)
                    }
                    .foregroundColor(.rgb(56, 189, 248))

                    if isWide {
                        Spacer(width: 2)
                        GroupBox("今日数据", style: .rounded) {
                            HStack {
                                bigNumber("1.28万", caption: "请求数", color: .brightWhite)
                                Spacer()
                                bigNumber("99.98%", caption: "可用率", color: .brightGreen)
                                Spacer()
                                bigNumber("24 毫秒", caption: "P95 延迟", color: .brightYellow)
                            }
                            Spacer(height: 1)
                            Text("▁▂▃▅▄▆▇▅▆█▇▆  流量 · 最近 12 小时")
                                .foregroundColor(.brightCyan)
                        }
                        .foregroundColor(.rgb(168, 85, 247))
                    }
                }

                Spacer(height: 1)
                GroupBox("实时信号", style: .double) {
                    HStack(alignment: .center) {
                        AnimatedText(["◐", "◓", "◑", "◒"], interval: 0.15)
                            .foregroundColor(liveUpdates ? .brightGreen : .brightBlack)
                        Text(liveUpdates ? " 遥测数据流运行正常" : " 遥测数据流已暂停")
                            .foregroundColor(liveUpdates ? .brightWhite : .rgb(100, 116, 139))
                        Spacer()
                        Text("刷新 #\(refreshCount)")
                            .foregroundColor(.rgb(100, 116, 139))
                    }
                }
                .foregroundColor(liveUpdates ? .brightGreen : .rgb(71, 85, 105))
                Spacer()
                statusBar(hint: "R 刷新提示 · S 弹出框 · D 调试指标 · 空格 暂停/继续")
            }
        }
    }

    private var tabSelection: Binding<ObservatoryTab> {
        Binding(
            get: { selection },
            set: { newSelection in
                selection = newSelection
                switch newSelection {
                case .chat:
                    if focusedField != .chatHistory && focusedField != .chatMessage {
                        focusedField = .chatHistory
                    }
                case .settings:
                    if focusedField == .chatHistory || focusedField == .chatMessage {
                        focusedField = nil
                    }
                case .overview, .activity:
                    focusedField = nil
                }
            }
        )
    }

    private var activityPage: some View {
        VStack {
            masthead(section: "服务动态", detail: "实时拓扑")
            Spacer(height: 1)

            Table(services, style: .rounded) {
                TableColumn("服务", value: \.name)
                TableColumn("区域", value: \.region)
                TableColumn("状态") { service in
                    Text(service.status)
                        .foregroundColor(service.status == "正常" ? .brightGreen : .brightYellow)
                        .bold()
                }
                TableColumn("负载", alignment: .trailing) { service in
                    Text("\(service.load)%")
                        .foregroundColor(service.load > 75 ? .brightYellow : .brightCyan)
                }
                TableColumn("延迟", value: \.latency, alignment: .trailing)
            }
            .foregroundColor(.rgb(71, 184, 255))

            Spacer(height: 1)
            if isWide {
                GroupBox("事件日志", style: .rounded) {
                    ScrollView(.vertical) {
                        VStack {
                            ForEach(events) { event in
                                HStack {
                                    Text(event.time).foregroundColor(.rgb(100, 116, 139))
                                    Spacer(width: 2)
                                    Text(event.level)
                                        .foregroundColor(levelColor(event.level))
                                        .bold()
                                    Spacer(width: 2)
                                    Text(event.source).foregroundColor(.brightCyan)
                                    Spacer(width: 2)
                                    Text(event.message).foregroundColor(.rgb(203, 213, 225))
                                    Spacer()
                                }
                            }
                        }
                    }
                    .frame(height: 5)
                }
                .foregroundColor(.rgb(71, 85, 105))
            }
            Spacer()
            statusBar(hint: "R 获取最新快照 · D 调试指标")
        }
    }

    private var settingsPage: some View {
        VStack {
            masthead(section: "控制室", detail: "本地偏好设置")
            Spacer(height: 1)

            HStack {
                GroupBox("运行设置", style: .rounded) {
                    settingRow(key: "1") {
                        Toggle("实时遥测", isOn: $liveUpdates)
                    }
                    Spacer(height: 1)
                    settingRow(key: "2") {
                        Toggle("告警通知", isOn: $notifications)
                    }
                    Spacer(height: 1)
                    settingRow(key: "3") {
                        Toggle("紧凑表格行", isOn: $compactRows)
                    }
                }
                .foregroundColor(.brightCyan)

                if isWide {
                    Spacer(width: 2)
                    GroupBox("外观", style: .rounded) {
                        Text("配色方案")
                            .foregroundColor(.rgb(100, 116, 139))
                        Text("● 青色   ● 紫色   ● 翠绿")
                            .foregroundColor(.brightCyan)
                        Spacer(height: 1)
                        Text("渲染器")
                            .foregroundColor(.rgb(100, 116, 139))
                        Text("声明式渲染器 · 真彩色 · 60 帧/秒")
                            .foregroundColor(.brightWhite)
                    }
                    .foregroundColor(.brightMagenta)
                }
            }

            Spacer(height: 1)
            GroupBox("关于本演示", style: .double) {
                Text("完全使用声明式终端视图构建。")
                    .foregroundColor(.brightWhite)
                    .bold()
                Text("标签视图负责导航；数据绑定、表格、分组框、进度条与动画文本共同组成仪表盘。")
                    .foregroundColor(.rgb(148, 163, 184))
            }
            .foregroundColor(.brightMagenta)
            Spacer(height: 1)
            GroupBox("操作备注", style: .rounded) {
                HStack(alignment: .center) {
                    Text("❯").foregroundColor(.brightCyan).bold()
                    Spacer(width: 1)
                    TextField("输入备注后按回车保存", text: $operatorNote, onCommit: saveNote)
                        .focused($focusedField, equals: .operatorNote)
                }
                Text(savedNote)
                    .foregroundColor(.rgb(100, 116, 139))
            }
            .foregroundColor(.brightCyan)
            Spacer()
            statusBar(hint: "1–3 切换 · D 调试指标 · 回车保存")
        }
    }

    private var chatPage: some View {
        GeometryReader { geometry in
            let historyWidth = isWide ? 34 : 0
            let gapWidth = isWide ? 2 : 0
            let conversationWidth = max(32, geometry.size.w - historyWidth - gapWidth)
            let messageBubbleWidth = max(20, Int(Double(conversationWidth) * 0.6))
            let messageHeight = max(8, geometry.size.h - 10)
            let historyHeight = max(8, geometry.size.h - 8)

            VStack {
                masthead(section: "DeepSeek 写作助手", detail: "对话 → 选择 → Markdown → Hexo")
                Spacer(height: 1)

                HStack {
                    if isWide {
                        GroupBox("历史对话", style: .rounded) {
                            ScrollView(.vertical) {
                                LazyVStack(
                                    conversations,
                                    alignment: .leading,
                                    spacing: 1,
                                    estimatedRowHeight: 3
                                ) { conversation in
                                    conversationRow(conversation)
                                }
                            }
                            .frame(height: historyHeight)

                            Text("数字键打开对话 · X 选择当前对话中的回答")
                                .foregroundColor(.rgb(100, 116, 139))
                        }
                        .frame(width: historyWidth)
                        .foregroundColor(.brightMagenta)
                        Spacer(width: gapWidth)
                    }

                    VStack {
                        GroupBox(currentConversationTitle, style: .rounded) {
                            ScrollView(.vertical) {
                                LazyVStack(
                                    currentMessages,
                                    alignment: .leading,
                                    spacing: 1,
                                    estimatedRowHeight: 5
                                ) { message in
                                    SelectableChatMessageView(
                                        message: message,
                                        index: messageSelectionNumber(for: message),
                                        isSelecting: isSelectingMessages,
                                        isSelected: isMessageSelected(message),
                                        bubbleWidth: messageBubbleWidth
                                    )
                                }
                            }
                            .frame(height: messageHeight)
                            .focused($focusedField, equals: .chatHistory)
                        }
                        .foregroundColor(.rgb(71, 85, 105))
                        .accentColor(.brightCyan)

                        HStack(alignment: .center) {
                            Text("❯")
                                .foregroundColor(.brightCyan)
                                .bold()
                            Spacer(width: 1)
                            TextField(
                                "输入消息，回车发送到当前对话……",
                                text: $chatDraft,
                                onCommit: sendChatMessage
                            )
                            .focused($focusedField, equals: .chatMessage)
                            Spacer(width: 1)
                        }
                        .padding(horizontal: 1)
                        .frame(height: 3, alignment: .center)
                        .bordered(.brightCyan, style: .rounded)
                    }
                    .frame(width: conversationWidth)
                }

                Spacer(height: 1)
                HStack {
                    Text(deepseekAPIKey.isEmpty ? "DeepSeek Key 未配置" : "DeepSeek Key 已配置")
                        .foregroundColor(deepseekAPIKey.isEmpty ? .brightYellow : .brightGreen)
                    Spacer(width: 2)
                    Text("选中 \(selectedMessageKeys.count) 条回答")
                        .foregroundColor(.brightCyan)
                    Spacer(width: 2)
                    Text("Hexo: \(hexoRepositoryPath)")
                        .foregroundColor(.rgb(148, 163, 184))
                    Spacer()
                }
                Spacer()
                statusBar(hint: chatStatus)
            }
        }
    }

    private var aiConfigSheet: some View {
        VStack(alignment: .leading) {
            Text("DeepSeek 与 Hexo 配置")
                .foregroundColor(.brightWhite)
                .bold()
            Spacer(height: 1)
            Text("API Key")
                .foregroundColor(.rgb(100, 116, 139))
            TextField("sk-...", text: $deepseekAPIKey)
                .focused($focusedField, equals: .deepseekKey)
                .bordered(.brightCyan, style: .rounded)
            Spacer(height: 1)
            Text("系统 Prompt")
                .foregroundColor(.rgb(100, 116, 139))
            TextField("整理聊天记录的写作要求", text: $deepseekSystemPrompt)
                .focused($focusedField, equals: .deepseekPrompt)
                .bordered(.brightMagenta, style: .rounded)
            Spacer(height: 1)
            Text("Hexo 仓库路径")
                .foregroundColor(.rgb(100, 116, 139))
            TextField("~/workspace/blog", text: $hexoRepositoryPath)
                .focused($focusedField, equals: .hexoRepoPath)
                .bordered(.brightGreen, style: .rounded)
            Spacer(height: 1)
            Text("Esc 关闭 · 当前只保存到界面状态，后续接入配置文件。")
                .foregroundColor(.brightYellow)
        }
        .frame(width: 76)
    }

    private var markdownDraftSheet: some View {
        VStack(alignment: .leading) {
            Text("Markdown 草稿预览")
                .foregroundColor(.brightWhite)
                .bold()
            Spacer(height: 1)
            TextField("文章标题", text: $markdownTitle)
                .focused($focusedField, equals: .markdownTitle)
                .bordered(.brightCyan, style: .rounded)
            Spacer(height: 1)
            ScrollView(.vertical) {
                Text(generatedMarkdown)
                    .foregroundColor(.rgb(203, 213, 225))
            }
            .frame(height: 14)
            .bordered(.rgb(51, 65, 85), style: .rounded)
            Spacer(height: 1)
            Text(draftStatus)
                .foregroundColor(.brightGreen)
            Text("下一步可以把它写入 \(hexoRepositoryPath)/source/_posts。")
                .foregroundColor(.rgb(100, 116, 139))
        }
        .frame(width: 86)
    }

    private func debugMetricsToast(_ metrics: TerminalDebugMetrics) -> some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Debug Reader")
                    .foregroundColor(.black)
                    .bold()
                Spacer()
                Text(metrics.frameCount == 0 ? "等待" : "#\(metrics.frameCount)")
                    .foregroundColor(.black)
            }
            Spacer(height: 1)
            debugMetricRow("节点", "\(metrics.cache.totalRenderableNodes)")
            debugMetricRow("复用", "\(metrics.cache.reusedNodes)/\(metrics.cache.reusableNodes)")
            debugMetricRow("脏节点", "\(metrics.cache.dirtyReusableNodes)")
            debugMetricRow("渲染", formatDuration(metrics.renderNanoseconds))
            debugMetricRow("输出", formatDuration(metrics.outputNanoseconds))
            debugMetricRow("速度", formatFPS(metrics.framesPerSecond))
            debugMetricRow("平均", formatFPS(metrics.averageFramesPerSecond))
            debugMetricRow("字节", "\(metrics.outputBytes)")
            Spacer(height: 1)
            Text("D 隐藏 · 上一帧快照")
                .foregroundColor(.black)
        }
        .frame(width: 34)
    }

    private var currentConversationTitle: String {
        conversations.first(where: { $0.id == activeConversationID })?.title ?? "新对话"
    }

    private var currentMessages: [ChatMessage] {
        conversations.first(where: { $0.id == activeConversationID })?.messages ?? []
    }

    private var selectableAssistantMessages: [ChatMessage] {
        currentMessages.filter { $0.role == .assistant }
    }

    private func conversationRow(_ conversation: ChatConversation) -> some View {
        let isActive = conversation.id == activeConversationID
        return VStack(alignment: .leading) {
            HStack {
                Text("\(conversation.id + 1).")
                    .foregroundColor(.rgb(100, 116, 139))
                    .bold(isActive)
                Spacer(width: 1)
                Text(conversation.title)
                    .foregroundColor(isActive ? .brightWhite : .rgb(203, 213, 225))
                    .bold(isActive)
                Spacer()
            }
            Text(conversation.summary)
                .foregroundColor(.rgb(148, 163, 184))
                .lineLimit(1)
            Text(conversation.updatedAt)
                .foregroundColor(.rgb(100, 116, 139))
        }
    }

    private func messageSelectionNumber(for message: ChatMessage) -> Int? {
        guard message.role == .assistant,
              let index = selectableAssistantMessages.firstIndex(where: { $0.id == message.id }) else {
            return nil
        }
        return index + 1
    }

    private func isMessageSelected(_ message: ChatMessage) -> Bool {
        selectedMessageKeys.contains(
            SelectedMessageKey(conversationID: activeConversationID, messageID: message.id)
        )
    }

    private func masthead(section: String, detail: String) -> some View {
        HStack(alignment: .center) {
            Text(" ◆ ")
                .foregroundColor(.rgb(8, 13, 24))
                .backgroundColor(.brightCyan)
                .bold()
            Text(" 轨道观测站 ")
                .foregroundColor(.brightWhite)
                .bold()
            Text("// \(section)")
                .foregroundColor(.brightMagenta)
            Spacer()
            Text(detail)
                .foregroundColor(.rgb(100, 116, 139))
            Text("  ")
        }
        .frame(height: 2, alignment: .center)
        .backgroundColor(.rgb(17, 25, 42))
    }

    private func metric(label: String, value: Double, text: String, color: Color) -> some View {
        HStack(alignment: .center) {
            Text(label)
                .foregroundColor(.rgb(148, 163, 184))
                .frame(width: 4)
            Spacer(width: 1)
            ProgressBar(value: value, width: isWide ? 24 : 14)
                .tint(color)
                .trackColor(.rgb(15, 23, 42))
            Spacer(width: 2)
            Text(text)
                .foregroundColor(.brightWhite)
                .bold()
        }
    }

    private func bigNumber(_ value: String, caption: String, color: Color) -> some View {
        VStack(alignment: .center) {
            Text(value).foregroundColor(color).bold()
            Text(caption).foregroundColor(.rgb(100, 116, 139))
        }
    }

    private func settingRow<Content: View>(
        key: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack {
            Text(" \(key) ")
                .foregroundColor(.rgb(8, 13, 24))
                .backgroundColor(.brightCyan)
                .bold()
            Spacer(width: 2)
            content().foregroundColor(.brightWhite)
            Spacer()
        }
    }

    private func debugMetricRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.black)
            Spacer()
            Text(value)
                .foregroundColor(.black)
                .bold()
        }
    }

    private func saveNote() {
        let note = operatorNote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !note.isEmpty else {
            savedNote = "尚未保存——请先输入一条简短备注。"
            return
        }
        savedNote = "已保存到本地：\(note)"
        operatorNote = ""
    }

    private func sendChatMessage() {
        let prompt = chatDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else {
            chatStatus = "请先输入消息再发送。"
            return
        }

        guard let index = conversations.firstIndex(where: { $0.id == activeConversationID }) else {
            chatStatus = "没有找到当前对话。"
            return
        }

        let nextID = (conversations[index].messages.map(\.id).max() ?? -1) + 1
        conversations[index].messages += [
            ChatMessage(id: nextID, role: .user, content: prompt, timestamp: "现在"),
            ChatMessage(
                id: nextID + 1,
                role: .assistant,
                content: chatResponse(to: prompt),
                timestamp: "现在"
            ),
        ]
        conversations[index].summary = prompt
        conversations[index].updatedAt = "刚刚"
        chatDraft = ""
        chatStatus = deepseekAPIKey.isEmpty
            ? "已生成本地模拟回复 · 配置 Key 后可接 DeepSeek"
            : "已生成回复 · 后续接入 DeepSeek API 请求"
    }

    private func chatResponse(to prompt: String) -> String {
        let value = prompt.lowercased()
        if value.contains("hexo") || value.contains("markdown") || value.contains("博客") {
            return "可以先把选中的回答整理成 front matter + 正文结构，再写入 Hexo 仓库的 source/_posts。当前页面已经预留了标题、仓库路径和草稿预览。"
        }
        if value.contains("deepseek") || value.contains("api") || value.contains("key") {
            return "配置页会保存 DeepSeek API Key 和系统 Prompt。真正请求时建议通过统一事件队列回到主循环更新状态，避免后台线程直接绘制终端。"
        }
        if value.contains("选择") || value.contains("整理") || value.contains("生成") {
            return "按 X 可以进入回答选择模式，用数字键勾选当前对话中的某些助手回答，再按 G 生成 Markdown 草稿。"
        }
        return "我收到了：\(prompt)\n\n这是一条本地模拟回复。后续把这里替换成 DeepSeek API 调用，就可以形成真正的命令行聊天软件。"
    }

    private func toggleMessageSelection(number: Int) -> Bool {
        guard number > 0,
              selectableAssistantMessages.indices.contains(number - 1) else {
            return false
        }
        let message = selectableAssistantMessages[number - 1]
        let key = SelectedMessageKey(conversationID: activeConversationID, messageID: message.id)
        if selectedMessageKeys.contains(key) {
            selectedMessageKeys.remove(key)
            chatStatus = "已取消选择回答 #\(number)"
        } else {
            selectedMessageKeys.insert(key)
            chatStatus = "已选择回答 #\(number)"
        }
        return true
    }

    private func activateConversation(number: Int) -> Bool {
        guard number > 0,
              let conversation = conversations.first(where: { $0.id == number - 1 }) else {
            return false
        }
        activeConversationID = conversation.id
        chatStatus = "已打开对话：\(conversation.title)"
        return true
    }

    private func generateMarkdownDraft() {
        let selectedEntries = conversations.flatMap { conversation in
            conversation.messages.compactMap { message -> (ChatConversation, ChatMessage)? in
                let key = SelectedMessageKey(conversationID: conversation.id, messageID: message.id)
                guard selectedMessageKeys.contains(key) else { return nil }
                return (conversation, message)
            }
        }
        guard !selectedEntries.isEmpty else {
            generatedMarkdown = "还没有选择任何回答。\n\n进入聊天页后按 X 开启选择模式，再用数字键勾选当前对话中的助手回答。"
            draftStatus = "请先选择某些回答。"
            showsMarkdownSheet = true
            return
        }

        var grouped: [(ChatConversation, [ChatMessage])] = []
        for (conversation, message) in selectedEntries {
            if let index = grouped.firstIndex(where: { $0.0.id == conversation.id }) {
                grouped[index].1.append(message)
            } else {
                grouped.append((conversation, [message]))
            }
        }
        let body = grouped.map { conversation, messages in
            let transcript = messages.map { message in
                "- **选中回答**（\(message.timestamp)）：\(message.content)"
            }.joined(separator: "\n")
            return """
            ## \(conversation.title)

            > 来源摘要：\(conversation.summary)

            \(transcript)
            """
        }.joined(separator: "\n\n")

        generatedMarkdown = """
        ---
        title: \(markdownTitle)
        date: \(Date())
        tags:
          - TerminalUI
          - DeepSeek
          - Hexo
        ---

        # \(markdownTitle)

        这篇草稿由命令行聊天中被选中的回答整理而来。后续接入 DeepSeek API 后，这里会替换为模型润色后的文章结构。

        \(body)

        ## 后续修订清单

        - [ ] 核对技术事实
        - [ ] 补充代码片段
        - [ ] 调整 Hexo front matter
        - [ ] 写入 `source/_posts`
        """
        draftStatus = "已基于 \(selectedEntries.count) 条选中回答生成草稿。"
        showsMarkdownSheet = true
    }

    private func statusBar(hint: String) -> some View {
        HStack(alignment: .center) {
            Text(liveUpdates ? " ● 实时 " : " ○ 已暂停 ")
                .foregroundColor(.rgb(8, 13, 24))
                .backgroundColor(liveUpdates ? .brightGreen : .brightYellow)
                .bold()
            if isWide {
                Text("  \(hint)")
                    .foregroundColor(.rgb(148, 163, 184))
                Spacer()
                Text("← → 切换标签 · Q 退出  ")
                    .foregroundColor(.rgb(100, 116, 139))
            } else {
                Spacer()
                Text("制表键聚焦 · ← → 标签 · Q 退出  ")
                    .foregroundColor(.rgb(100, 116, 139))
            }
        }
        .frame(height: 1, alignment: .center)
        .backgroundColor(.rgb(17, 25, 42))
    }

    private func levelColor(_ level: String) -> Color {
        switch level {
        case "良好": .brightGreen
        case "同步": .brightYellow
        default: .rgb(148, 163, 184)
        }
    }

    private func formatDuration(_ nanoseconds: UInt64) -> String {
        if nanoseconds >= 1_000_000 {
            return String(format: "%.2f 毫秒", Double(nanoseconds) / 1_000_000)
        }
        if nanoseconds >= 1_000 {
            return String(format: "%.2f 微秒", Double(nanoseconds) / 1_000)
        }
        return "\(nanoseconds) 纳秒"
    }

    private func formatFPS(_ framesPerSecond: Double) -> String {
        guard framesPerSecond.isFinite, framesPerSecond > 0 else { return "0.0 帧/秒" }
        return String(format: "%.1f 帧/秒", framesPerSecond)
    }

    private func handleGlobalKey(_ event: KeyPress) -> KeyPress.Result {
        switch event.key {
        case .character("q"):
            TerminalStateRuntime.stop()
        case .character("c") where event.modifiers.contains(.control):
            TerminalStateRuntime.stop()
        case .character("r"):
            refreshCount += 1
            showsToast.toggle()
        case .character("s"):
            showsSheet = true
        case .character("d"):
            showsDebugMetricsToast.toggle()
        case .character("a"):
            showsAIConfigSheet = true
        case .character("x"):
            isSelectingMessages.toggle()
            chatStatus = isSelectingMessages
                ? "回答选择模式：数字键勾选当前对话的助手回答 · G 生成 Markdown"
                : "已退出回答选择模式。"
        case .character("g"):
            generateMarkdownDraft()
        case .character(" "):
            liveUpdates.toggle()
        case .character("1"):
            if selection == .chat,
               (isSelectingMessages ? toggleMessageSelection(number: 1) : activateConversation(number: 1)) {
                break
            }
            liveUpdates.toggle()
        case .character("2"):
            if selection == .chat,
               (isSelectingMessages ? toggleMessageSelection(number: 2) : activateConversation(number: 2)) {
                break
            }
            notifications.toggle()
        case .character("3"):
            if selection == .chat,
               (isSelectingMessages ? toggleMessageSelection(number: 3) : activateConversation(number: 3)) {
                break
            }
            compactRows.toggle()
        default:
            return .ignored
        }
        return .handled
    }
}

private struct SelectableChatMessageView: View {
    let message: ChatMessage
    let index: Int?
    let isSelecting: Bool
    let isSelected: Bool
    let bubbleWidth: Int

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer()
            }

            GroupBox(
                title,
                titleAlignment: message.role == .user ? .trailing : .leading,
                style: .rounded
            ) {
                Text(message.content)
                    .foregroundColor(.rgb(203, 213, 225))
                HStack {
                    Spacer()
                    Text(message.timestamp)
                        .foregroundColor(.rgb(100, 116, 139))
                }
            }
            .frame(width: bubbleWidth)
            .foregroundColor(message.role == .assistant ? .brightCyan : .brightYellow)

            if message.role == .assistant {
                Spacer()
            }
        }
    }

    private var title: String {
        if message.role == .user {
            return "◆ 你"
        }
        guard let index else {
            return "◈ DeepSeek"
        }
        if isSelecting {
            return "\(isSelected ? "[x]" : "[ ]") \(index). DeepSeek 回答"
        }
        if isSelected {
            return "✓ \(index). DeepSeek 回答"
        }
        return "\(index). DeepSeek 回答"
    }
}
