import Testing
import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
@testable import TerminalUI
@testable import TerminalUICore
@testable import TerminalUILayout
@testable import TerminalUIRender
@testable import TerminalUIView

@Test func verticalScrollViewScrollsAndClipsItsContent() {
    let app = _TerminalAppHost(width: 1, height: 4) {
        VStack {
            Text("T")
            ScrollView(.vertical, showsIndicators: false) {
                VStack {
                    ForEach(0..<4, id: \.self) { value in
                        Text("\(value)")
                    }
                }
            }
            .frame(height: 2)
            Text("Z")
        }
    }

    let initial = app.render()
    #expect(initial.grid.map { $0[0].char } == ["T", "0", "1", "Z"])

    #expect(app.send(KeyPress(key: .downArrow)) == .handled)
    let scrolled = app.render()
    #expect(scrolled.grid.map { $0[0].char } == ["T", "1", "2", "Z"])

    #expect(app.send(KeyPress(key: .end)) == .handled)
    let end = app.render()
    #expect(end.grid.map { $0[0].char } == ["T", "2", "3", "Z"])
}

@Test func scrollViewSkipsOffscreenRenderableNodes() {
    let node = ScrollView(.vertical, showsIndicators: false) {
        VStack {
            ForEach(0..<500) { row in
                Text("row \(row) — 大量滚动内容")
            }
        }
    }
    .frame(height: 5)
    ._makeLayoutNode()
    let bounds = Rect(x: 0, y: 0, w: 30, h: 5)
    node.layout(in: bounds)

    let canvas = Canvas(width: bounds.w, height: bounds.h)
    let cache = RenderCache()
    Render.drawLaidOut(node, to: canvas, cache: cache)

    // Only the five visible rows and the fixed ScrollView indicator reach the
    // renderable path; the other 495 text nodes are rejected by the active clip.
    #expect(cache.stats.totalRenderableNodes <= 6)
    #expect(String(canvas.grid[0].map(\.char)).hasPrefix("row 0"))
}

@Test func lazyVStackScrollsLargeCollectionsWithoutMaterializingEveryRow() {
    let node = ScrollView(.vertical, showsIndicators: false) {
        LazyVStack(0..<500, spacing: 1, estimatedRowHeight: 1) { row in
            Text("lazy row \(row)")
        }
    }
    .frame(height: 5)
    ._makeLayoutNode()
    let bounds = Rect(x: 0, y: 0, w: 30, h: 5)
    node.layout(in: bounds)

    let canvas = Canvas(width: bounds.w, height: bounds.h)
    let cache = RenderCache()
    Render.drawLaidOut(node, to: canvas, cache: cache)

    #expect(String(canvas.grid[0].map(\.char)).hasPrefix("lazy row 0"))
    // Five visible rows plus overscan may exist, but the remaining hundreds of
    // rows must never enter the render tree.
    #expect(cache.stats.totalRenderableNodes < 20)
}

@Test func lazyVStackRestoresMeasuredHeightsAndScrollOffsetAcrossFrames() {
    let app = _TerminalAppHost(width: 24, height: 4) {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(0..<100, estimatedRowHeight: 1) { row in
                Text("lazy row \(row)")
            }
        }
        .frame(height: 4)
    }

    var canvas = app.render()
    #expect(String(canvas.grid[0].map(\.char)).hasPrefix("lazy row 0"))

    #expect(app.send(KeyPress(key: .downArrow)) == .handled)
    canvas = app.render()
    #expect(String(canvas.grid[0].map(\.char)).hasPrefix("lazy row 1"))

    #expect(app.send(KeyPress(key: .pageDown)) == .handled)
    canvas = app.render()
    #expect(String(canvas.grid[0].map(\.char)).hasPrefix("lazy row 4"))
}

@Test func horizontalScrollViewUsesLeftAndRightArrowKeys() {
    let app = _TerminalAppHost(width: 3, height: 1) {
        ScrollView(.horizontal, showsIndicators: false) {
            Text("ABCDE")
        }
    }

    #expect(String(app.render().grid[0].map(\.char)) == "ABC")
    #expect(app.send(KeyPress(key: .rightArrow)) == .handled)
    #expect(String(app.render().grid[0].map(\.char)) == "BCD")
}

@Test func focusStateRoutesArrowKeysToScrollViewUntilTabMovesToTextField() {
    enum Target: Hashable {
        case history
        case input
    }

    let focus = FocusState<Target?>(wrappedValue: .history)
    let text = State(wrappedValue: "")
    let app = _TerminalAppHost(width: 4, height: 3) {
        VStack {
            ScrollView(.vertical) {
                VStack {
                    ForEach(0..<4) { value in
                        Text("\(value)")
                    }
                }
            }
            .frame(height: 2)
            .focused(focus.projectedValue, equals: .history)

            TextField("Input", text: text.projectedValue)
                .focused(focus.projectedValue, equals: .input)
        }
    }

    let initial = app.render()
    #expect(initial.grid[0][0].char == "0")
    #expect(initial.grid[0][3].style.foregroundColor == .brightCyan)

    #expect(app.send(KeyPress(key: .downArrow)) == .handled)
    let scrolled = app.render()
    #expect(scrolled.grid[0][0].char == "1")

    #expect(app.send(KeyPress(key: .tab, characters: "\t")) == .handled)
    #expect(focus.wrappedValue == .input)
    #expect(app.send(KeyPress(key: .downArrow)) == .ignored)
    let inputFocused = app.render()
    #expect(inputFocused.grid[0][0].char == "1")
    #expect(inputFocused.grid[0][3].style.foregroundColor != .brightCyan)
}

@Test func unmanagedScrollViewReceivesArrowKeysBubbledFromFocusedTextField() {
    let text = State(wrappedValue: "")
    let app = _TerminalAppHost(width: 5, height: 3) {
        VStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack {
                    ForEach(0..<4) { value in
                        Text("\(value)")
                    }
                }
            }
            .frame(height: 2)

            TextField("Input", text: text.projectedValue)
        }
    }

    let initial = app.render()
    #expect(initial.grid[0][0].char == "0")
    #expect(app.send(KeyPress(key: .downArrow)) == .handled)
    let scrolled = app.render()
    #expect(scrolled.grid[0][0].char == "1")
}

@Test func rebuiltUnmanagedScrollViewRestoresOffsetAcrossRenderPasses() {
    let text = State(wrappedValue: "")
    let app = _TerminalAppHost(width: 5, height: 3) {
        RebuiltScrollBenchmarkView(text: text.projectedValue)
    }

    let initial = app.render()
    #expect(initial.grid[0][0].char == "0")
    #expect(app.send(KeyPress(key: .downArrow)) == .handled)
    let scrolled = app.render()
    #expect(scrolled.grid[0][0].char == "1")
}

@Test func rebuiltFocusedScrollViewCanReceiveFocusAndRestoreOffset() {
    let focus = FocusState<RebuiltFocusedScrollBenchmarkView.Target?>(wrappedValue: .history)
    let text = State(wrappedValue: "")
    let app = _TerminalAppHost(width: 5, height: 3) {
        RebuiltFocusedScrollBenchmarkView(focus: focus, text: text.projectedValue)
    }

    let initial = app.render()
    #expect(focus.wrappedValue == .history)
    #expect(initial.grid[0][0].char == "0")

    #expect(app.send(KeyPress(key: .downArrow)) == .handled)
    let scrolled = app.render()
    #expect(scrolled.grid[0][0].char == "1")

    #expect(app.send(KeyPress(key: .tab, characters: "\t")) == .handled)
    #expect(focus.wrappedValue == .input)
}

@Test func focusedScrollViewInsideGroupBoxHighlightsAndScrolls() {
    enum Target: Hashable {
        case history
        case input
    }

    let focus = FocusState<Target?>()
    let text = State(wrappedValue: "")
    let app = _TerminalAppHost(width: 9, height: 6) {
        VStack {
            GroupBox("History") {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack {
                        ForEach(0..<4) { value in
                            Text("\(value)")
                        }
                    }
                }
                .frame(height: 2)
                .focused(focus.projectedValue, equals: .history)
            }
            .foregroundColor(.gray)
            .accentColor(.brightCyan)

            TextField("Input", text: text.projectedValue)
                .focused(focus.projectedValue, equals: .input)
        }
    }

    _ = app.render()
    #expect(app.send(KeyPress(key: .tab, characters: "\t")) == .handled)
    #expect(focus.wrappedValue == .history)
    let focused = app.render()
    #expect(focused.grid[0][0].style.foregroundColor == .brightCyan)

    #expect(app.send(KeyPress(key: .downArrow)) == .handled)
    let scrolled = app.render()
    #expect(scrolled.grid[1][1].char == "1")
}

@Test func tabViewPageCanFocusScrollViewInsideGroupBoxAfterSwitchingTabs() {
    enum Page: Hashable {
        case settings
        case chat
    }
    enum Target: Hashable {
        case setting
        case history
        case input
    }

    var page = Page.settings
    let focus = FocusState<Target?>()
    let setting = State(wrappedValue: "")
    let input = State(wrappedValue: "")
    let app = _TerminalAppHost(width: 18, height: 8) {
        TabView(selection: Binding(get: { page }, set: { page = $0 })) {
            TextField("Setting", text: setting.projectedValue)
                .focused(focus.projectedValue, equals: .setting)
                .tag(Page.settings)
                .tabItem { Text("Settings") }

            VStack {
                GroupBox("History") {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack {
                            ForEach(0..<4) { value in
                                Text("\(value)")
                            }
                        }
                    }
                    .frame(height: 2)
                    .focused(focus.projectedValue, equals: .history)
                }
                .foregroundColor(.gray)
                .accentColor(.brightCyan)

                TextField("Input", text: input.projectedValue)
                    .focused(focus.projectedValue, equals: .input)
            }
            .tag(Page.chat)
            .tabItem { Text("Chat") }
        }
    }

    _ = app.render()
    #expect(app.send(KeyPress(key: .rightArrow)) == .handled)
    _ = app.render()
    #expect(page == .chat)
    #expect(app.send(KeyPress(key: .tab, characters: "\t")) == .handled)
    #expect(focus.wrappedValue == .history)
    let focused = app.render()
    #expect(focused.grid[1][0].style.foregroundColor == .brightCyan)

    #expect(app.send(KeyPress(key: .downArrow)) == .handled)
    let scrolled = app.render()
    #expect(scrolled.grid[2][1].char == "1")
}

@Test func chatLikeTabPageFocusesHistoryScrollViewWhenSelectionBindingSetsFocus() {
    enum Page: Hashable {
        case overview
        case chat
    }
    enum Target: Hashable {
        case history
        case input
    }

    var page = Page.overview
    let focus = FocusState<Target?>()
    let input = State(wrappedValue: "")
    let selection = Binding<Page>(
        get: { page },
        set: { newPage in
            page = newPage
            focus.wrappedValue = newPage == .chat ? .history : nil
        }
    )
    let app = _TerminalAppHost(width: 54, height: 14) {
        TabView(selection: selection) {
            Text("Overview")
                .tag(Page.overview)
                .tabItem { Text("Overview") }

            GeometryReader { geometry in
                let historyWidth = 16
                let gapWidth = 2
                let conversationWidth = max(20, geometry.size.w - historyWidth - gapWidth)
                HStack {
                    GroupBox("History") {
                        Text("Old")
                    }
                    .frame(width: historyWidth)
                    .foregroundColor(.brightMagenta)

                    Spacer(width: gapWidth)

                    VStack {
                        GroupBox("Conversation") {
                            ScrollView(.vertical, showsIndicators: false) {
                                VStack(alignment: .leading) {
                                    ForEach(0..<8) { value in
                                        Text("Message \(value)")
                                        Spacer(height: 1)
                                    }
                                }
                            }
                            .frame(height: 4)
                            .focused(focus.projectedValue, equals: .history)
                        }
                        .foregroundColor(.rgb(71, 85, 105))
                        .accentColor(.brightCyan)

                        TextField("Input", text: input.projectedValue)
                            .focused(focus.projectedValue, equals: .input)
                    }
                    .frame(width: conversationWidth)
                }
            }
            .tag(Page.chat)
            .tabItem { Text("Chat") }
        }
    }

    _ = app.render()
    #expect(app.send(KeyPress(key: .rightArrow)) == .handled)
    let focused = app.render()
    #expect(page == .chat)
    #expect(focus.wrappedValue == .history)
    let focusedForegroundColors = focused.grid.flatMap { row in
        row.map(\.style.foregroundColor)
    }
    #expect(focusedForegroundColors.contains(.brightCyan))

    #expect(app.send(KeyPress(key: .downArrow)) == .handled)
    _ = app.render()
}

@Test func scrollViewClipsChildBordersToItsViewport() {
    let canvas = Canvas(width: 5, height: 3)
    let view = ScrollView(.vertical, showsIndicators: false) {
        Text("A")
            .frame(width: 5, height: 5)
            .bordered(.white, style: .single)
    }

    Render.render(view._makeLayoutNode(), in: Rect(x: 0, y: 1, w: 5, h: 1), to: canvas)

    #expect(String(canvas.grid[0].map(\.char)) == "     ")
    #expect(String(canvas.grid[2].map(\.char)) == "     ")
}

