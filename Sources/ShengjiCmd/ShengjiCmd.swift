import Foundation
import TerminalUI

@main
struct ShengjiCmd {
    static func main() {
        let size = TerminalSizeReader.current(or: TerminalSize(columns: 108, rows: 32))
        let app = TerminalApp(width: size.width, height: size.height) {
            ObservatoryDemo(isWide: size.width >= 96)
        }

        do {
            try app.run()
        } catch TerminalInputError.notTerminal {
            app.render().flush()
        } catch {
            print("终端输入失败：\(error)")
        }
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

private struct ObservatoryDemo: View {
    private enum Field: Hashable {
        case operatorNote
        case chatHistory
        case chatMessage
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
    @State private var chatStatus = "回车发送 · ↑↓ 滚动 · 退出键离开输入框"
    @State private var showsSheet = false
    @State private var showsToast = false
    @FocusState private var focusedField: Field?
    @State private var messages = [
        ChatMessage(
            id: 0,
            role: .assistant,
            content: "欢迎来到轨道观测站。我可以介绍仪表盘、终端界面组件或当前服务快照。",
            timestamp: "01:14"
        ),
        ChatMessage(
            id: 1,
            role: .user,
            content: "当前网络状态怎么样？",
            timestamp: "01:15"
        ),
        ChatMessage(
            id: 2,
            role: .assistant,
            content: "四项服务均可用。事件流正在同步，负载为 81%；其余节点状态正常，延迟均低于 45 毫秒。",
            timestamp: "01:15"
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
        ZStack {
            Spacer()
                .backgroundColor(.rgb(8, 13, 24))

            TabView(selection: $selection) {
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
        .toast(isPresented: $showsToast, alignment: .topTrailing) {
            Text("✓ 快照已刷新 #\(refreshCount)")
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
                statusBar(hint: "R 刷新提示 · S 弹出框 · 空格 暂停/继续")
            }
        }
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
            statusBar(hint: "R 获取最新快照")
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
            statusBar(hint: "1–3 切换 · 回车保存 · 退出键离开输入框")
        }
    }

    private var chatPage: some View {
        VStack {
            masthead(section: "智能助手", detail: "本地模拟")
            Spacer(height: 1)

            HStack {
                if isWide {
                    GroupBox("快捷提问", style: .rounded) {
                        Text("01  介绍这个仪表盘")
                            .foregroundColor(.brightWhite)
                        Spacer(height: 1)
                        Text("02  总结服务健康状态")
                            .foregroundColor(.brightWhite)
                        Spacer(height: 1)
                        Text("03  讲解终端界面组件")
                            .foregroundColor(.brightWhite)
                        Spacer()
                        Text("本地运行 · 无需联网")
                            .foregroundColor(.brightGreen)
                    }
                    .frame(width: 30)
                    .foregroundColor(.brightMagenta)
                    Spacer(width: 2)
                }

                VStack {
                    ScrollView(.vertical) {
                        VStack(alignment: .leading) {
                            ForEach(messages) { message in
                                ChatMessageView(message: message)
                                Spacer(height: 1)
                            }
                        }
                    }
                    .frame(height: isWide ? 16 : 13)
                    .bordered(.rgb(51, 65, 85), style: .rounded)
                    .focused($focusedField, equals: .chatHistory)

                    HStack(alignment: .center) {
                        Text("❯")
                            .foregroundColor(.brightCyan)
                            .bold()
                        Spacer(width: 1)
                        TextField(
                            "向观测站提问……",
                            text: $chatDraft,
                            onCommit: sendChatMessage
                        )
                        .focused($focusedField, equals: .chatMessage)
                    }
                    .padding(horizontal: 1)
                    .frame(height: 3, alignment: .center)
                    .bordered(.brightCyan, style: .rounded)
                }
            }

            Spacer()
            statusBar(hint: chatStatus)
        }
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

        let nextID = (messages.map(\.id).max() ?? -1) + 1
        messages += [
            ChatMessage(id: nextID, role: .user, content: prompt, timestamp: "现在"),
            ChatMessage(
                id: nextID + 1,
                role: .assistant,
                content: chatResponse(to: prompt),
                timestamp: "现在"
            ),
        ]
        chatDraft = ""
        chatStatus = "已生成本地回复 · 按结束键查看最新消息"
    }

    private func chatResponse(to prompt: String) -> String {
        let value = prompt.lowercased()
        if value.contains("health") || value.contains("service") || value.contains("状态") {
            return "极光接口、向量仓库和边缘缓存均运行正常。事件流仍在同步，但延迟与负载都处于演示阈值以内。"
        }
        if value.contains("terminalui") || value.contains("component") || value.contains("组件") {
            return "这个页面将标签视图、滚动视图、输入框、分组框、数据循环、状态、绑定、堆栈、边框、颜色和键盘处理组合成一棵声明式视图树。"
        }
        if value.contains("dashboard") || value.contains("仪表盘") {
            return "“概览”展示实时指标，“动态”包含服务表格与事件流，“设置”则演示数据绑定和可编辑的操作备注。"
        }
        return "我收到了：\(prompt)\n\n这是一条本地模拟回复。将本地回复函数替换为异步模型请求，即可接入真正的智能服务。"
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
        case .character(" "):
            liveUpdates.toggle()
        case .character("1"):
            liveUpdates.toggle()
        case .character("2"):
            notifications.toggle()
        case .character("3"):
            compactRows.toggle()
        default:
            return .ignored
        }
        return .handled
    }
}

private struct ChatMessageView: View {
    let message: ChatMessage

    var body: some View {
        GroupBox(
            message.role == .assistant ? "◈ 观测站智能助手" : "◆ 你",
            titleAlignment: .leading,
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
        .foregroundColor(message.role == .assistant ? .brightCyan : .brightYellow)
    }
}
