import Testing
import Foundation
@testable import TerminalUI
@testable import TerminalUICore
@testable import TerminalUILayout
@testable import TerminalUIRender
@testable import TerminalUIView

private enum TestTab: Hashable {
    case home
    case settings
}

@Test func tabViewNavigationWinsOverFocusedTextFieldArrowKeys() {
    var selection = TestTab.settings
    var text = "abc"
    let app = TerminalApp(width: 20, height: 4) {
        TabView(selection: Binding(get: { selection }, set: { selection = $0 })) {
            Text("首页").tag(TestTab.home)
            TextField("设置", text: Binding(get: { text }, set: { text = $0 }))
                .tag(TestTab.settings)
        }
    }

    _ = app.render()
    #expect(app.send(KeyPress(key: .leftArrow)) == .handled)
    #expect(selection == .home)
    #expect(text == "abc")
}

@Test func sheetSupportsAllNineAlignmentEdgesAndEscapeDismissal() {
    let cases: [(AlignmentEdge, Int, Int)] = [
        (.topLeading, 2, 2), (.top, 9, 2), (.topTrailing, 17, 2),
        (.leading, 2, 4), (.center, 9, 4), (.trailing, 17, 4),
        (.bottomLeading, 2, 7), (.bottom, 9, 7), (.bottomTrailing, 17, 7),
    ]

    for (alignment, expectedX, expectedY) in cases {
        var isPresented = true
        var underlyingKeyCount = 0
        var dismissCount = 0
        let app = TerminalApp(width: 20, height: 10) {
            Text("底层")
                .frame(width: 20, height: 10)
                .onKeyPress { _ in
                    underlyingKeyCount += 1
                    return .handled
                }
                .sheet(
                    isPresented: Binding(
                        get: { isPresented },
                        set: { isPresented = $0 }
                    ),
                    alignment: alignment,
                    onDismiss: { dismissCount += 1 }
                ) {
                    Text("X")
                }
        }

        let canvas = app.render()
        #expect(canvas.grid[expectedY][expectedX].char == "X")
        #expect(app.send(KeyPress(key: .character("a"))) == .handled)
        #expect(underlyingKeyCount == 0)
        #expect(app.send(KeyPress(key: .escape)) == .handled)
        #expect(!isPresented)
        #expect(dismissCount == 1)
    }
}

@Test func toastUsesAlignmentWithoutBlockingUnderlyingContent() {
    var isPresented = true
    var keyCount = 0
    let app = TerminalApp(width: 20, height: 10) {
        Text("底层")
            .frame(width: 20, height: 10)
            .onKeyPress { _ in
                keyCount += 1
                return .handled
            }
            .toast(
                isPresented: Binding(get: { isPresented }, set: { isPresented = $0 }),
                alignment: .bottomTrailing
            ) {
                Text("!")
            }
    }

    let canvas = app.render()
    #expect(canvas.grid[9][18].char == "!")
    #expect(canvas.grid[9][18].style.backgroundColor == .brightCyan)
    #expect(app.send(KeyPress(key: .character("a"))) == .handled)
    #expect(keyCount == 1)
}

@Test func tabViewMatchesSwiftUISelectionTagAndTabItemSyntax() {
    var selection = TestTab.settings
    let binding = Binding(
        get: { selection },
        set: { selection = $0 }
    )
    let app = TerminalApp(width: 28, height: 3) {
        TabView(selection: binding) {
            Text("Home page")
                .tabItem { Text("Home") }
                .tag(TestTab.home)
            Text("Settings page")
                .tag(TestTab.settings)
                .tabItem { Text("Settings") }
        }
    }

    var canvas = app.render()
    #expect(String(canvas.grid[0].map(\.char)).hasPrefix(" Home  [Settings]"))
    #expect(String(canvas.grid[1].map(\.char)).hasPrefix("Settings page"))
    #expect(canvas.grid[0][7].style.foregroundColor == .black)
    #expect(canvas.grid[0][7].style.backgroundColor == .brightCyan)
    #expect(canvas.grid[0][7].style.bold)

    #expect(app.send(KeyPress(key: .leftArrow)) == .handled)
    #expect(selection == .home)
    canvas = app.render()
    #expect(String(canvas.grid[0].map(\.char)).hasPrefix("[Home]  Settings "))
    #expect(String(canvas.grid[1].map(\.char)).hasPrefix("Home page"))
    #expect(canvas.grid[0][0].style.backgroundColor == .brightCyan)
    #expect(canvas.grid[0][7].style.backgroundColor != .brightCyan)
}

@Test func tabViewWithoutSelectionRetainsItsCurrentTabAcrossRenders() {
    let app = TerminalApp(width: 20, height: 3) {
        TabView {
            Text("First").tabItem { Text("One") }
            Text("Second").tabItem { Text("Two") }
        }
    }

    #expect(String(app.render().grid[1].map(\.char)).hasPrefix("First"))
    #expect(app.send(KeyPress(key: .rightArrow)) == .handled)
    #expect(String(app.render().grid[0].map(\.char)).hasPrefix(" One  [Two]"))
    #expect(String(app.render().grid[1].map(\.char)).hasPrefix("Second"))
}

@Test func terminalSizeReaderUsesFallbackForInvalidDescriptor() {
    let fallback = TerminalSize(columns: 120, rows: 36)

    #expect(TerminalSizeReader.current(fileDescriptor: -1) == nil)
    #expect(TerminalSizeReader.current(or: fallback, fileDescriptor: -1) == fallback)
    #expect(fallback.width == 120)
    #expect(fallback.height == 36)
}

@Test func segmentMeasuresAsciiAndCJKText() {
    #expect(Segment.cellLength(of: "abc") == 3)
    #expect(Segment.cellLength(of: "升级") == 4)
    #expect(Segment.cellLength(of: "A升级K") == 6)
}

@Test func segmentMeasuresEmojiAsWideGraphemes() {
    #expect(Segment.cellLength(of: "👍") == 2)
    #expect(Segment.cellLength(of: "❤️") == 2)
    #expect(Segment.cellLength(of: "1️⃣") == 2)
    #expect(Segment.cellLength(of: "👨‍👩‍👧‍👦") == 2)
    #expect(Segment.cellLength(of: "🇨🇳") == 2)
}

@Test func segmentKeepsCombiningMarksWithBaseCharacter() {
    #expect(Segment.cellLength(of: "e\u{301}") == 1)
    #expect(Segment.cellLength(of: "\u{301}") == 0)
}

@Test func segmentClassifiesTerminalControls() {
    let segments = Segment.segment("A\n中")

    #expect(segments.map(\.text) == ["A", "\n", "中"])
    #expect(segments.map(\.kind) == [.text, .control, .text])
    #expect(segments.map(\.cellLength) == [1, 0, 2])
}

@Test func truncateStopsBeforePartialWideGrapheme() {
    #expect("A中B".truncated(toWidth: 1) == "A")
    #expect("A中B".truncated(toWidth: 2) == "A")
    #expect("A中B".truncated(toWidth: 3) == "A中")
    #expect("👍OK".truncated(toWidth: 2) == "👍")
    #expect("👍OK".truncated(toWidth: 3) == "👍O")
}

@Test func textWrapsToTheProposedCellWidth() {
    let node = Text("abcdef")._makeLayoutNode()
    let size = node.measure(proposed: ProposedSize(width: 4, height: nil))
    let canvas = Canvas(width: 4, height: 2)

    Render.render(node, in: Rect(x: 0, y: 0, w: 4, h: 2), to: canvas)

    #expect(size.w == 4)
    #expect(size.h == 2)
    #expect(String(canvas.grid[0].map(\.char)) == "abcd")
    #expect(String(canvas.grid[1].map(\.char)) == "ef  ")
}

@Test func textWrapsWideCharactersWithoutSplittingThem() {
    let node = Text("A中文B")._makeLayoutNode()
    let size = node.measure(proposed: ProposedSize(width: 3, height: nil))
    let canvas = Canvas(width: 3, height: 2)

    Render.render(node, in: Rect(x: 0, y: 0, w: 3, h: 2), to: canvas)

    #expect(size.w == 3)
    #expect(size.h == 2)
    #expect(canvas.grid[0][0].char == "A")
    #expect(canvas.grid[0][1].char == "中")
    #expect(canvas.grid[1][0].char == "文")
    #expect(canvas.grid[1][2].char == "B")
}

@Test func textUsesEllipsisWhenHeightCannotShowAllWrappedLines() {
    let canvas = Canvas(width: 4, height: 1)

    Render.render(
        Text("abcdef")._makeLayoutNode(),
        in: Rect(x: 0, y: 0, w: 4, h: 1),
        to: canvas
    )

    #expect(String(canvas.grid[0].map(\.char)) == "abc…")
}

@Test func textEllipsisTruncatesOnlyAtWideCharacterBoundaries() {
    let canvas = Canvas(width: 5, height: 1)

    Render.render(
        Text("中文AB")._makeLayoutNode(),
        in: Rect(x: 0, y: 0, w: 5, h: 1),
        to: canvas
    )

    #expect(canvas.grid[0][0].char == "中")
    #expect(canvas.grid[0][2].char == "文")
    #expect(canvas.grid[0][4].char == "…")
}

@Test func textHonorsExplicitNewlinesAndLineLimit() {
    let canvas = Canvas(width: 5, height: 3)
    let view = Text("one\ntwo").lineLimit(1)

    Render.render(view._makeLayoutNode(), in: Rect(x: 0, y: 0, w: 5, h: 3), to: canvas)

    #expect(String(canvas.grid[0].map(\.char)) == "one… ")
    #expect(String(canvas.grid[1].map(\.char)) == "     ")
}

@Test func textUsesEllipsisWhenAWideCharacterCannotFitAtAll() {
    let canvas = Canvas(width: 1, height: 1)

    Render.render(Text("中")._makeLayoutNode(), in: Rect(x: 0, y: 0, w: 1, h: 1), to: canvas)

    #expect(canvas.grid[0][0].char == "…")
}

@Test func unrenderableWideCharacterDoesNotReplaceAnEarlierVisibleLine() {
    let node = Text("A中")._makeLayoutNode()
    let canvas = Canvas(width: 1, height: 2)

    Render.render(node, in: Rect(x: 0, y: 0, w: 1, h: 2), to: canvas)

    #expect(node.measure(proposed: ProposedSize(width: 1, height: nil)).h == 2)
    #expect(canvas.grid[0][0].char == "A")
    #expect(canvas.grid[1][0].char == "…")
}

@Test func emptyTextAndZeroWidthTextKeepTheirLogicalLineHeight() {
    let empty = Text("")._makeLayoutNode().measure(proposed: ProposedSize())
    let zeroWidth = Text("A\nB")._makeLayoutNode().measure(
        proposed: ProposedSize(width: 0, height: nil)
    )

    #expect(empty.w == 0)
    #expect(empty.h == 1)
    #expect(zeroWidth.w == 0)
    #expect(zeroWidth.h == 2)
}

@Test func viewBuildsLayoutNodeAndRenderWritesCanvas() {
    let view = VStack {
        Text("AB")
        Text("中")
    }
    let node = view._makeLayoutNode() as! _ContainerLayoutNode

    #expect(node.children.count == 2)
    #expect(node.measure(proposed: ProposedSize()).w == 2)
    #expect(node.measure(proposed: ProposedSize()).h == 2)

    let canvas = Canvas(width: 4, height: 2)
    let bounds = Rect(x: 0, y: 0, w: 4, h: 2)
    Render.render(node, in: bounds, to: canvas)
    #expect(canvas.output().contains("A"))
    #expect(canvas.output().contains("B"))
    #expect(canvas.output().contains("中"))
}

@Test func userDefinedViewOnlyNeedsBody() {
    struct CustomLabel: View {
        var body: some View {
            HStack {
                Text("A")
                Text("B")
            }
        }
    }

    let node = CustomLabel()._makeLayoutNode() as! _ContainerLayoutNode

    #expect(node.children.count == 2)
    #expect(node.measure(proposed: ProposedSize()).w == 2)
    #expect(node.measure(proposed: ProposedSize()).h == 1)
}

@Test func spaceExpandsAcrossHStackRemainingWidth() {
    let canvas = Canvas(width: 5, height: 1)
    let view = HStack {
        Text("A")
        Spacer()
        Text("B")
    }

    Render.render(view._makeLayoutNode(), in: Rect(x: 0, y: 0, w: 5, h: 1), to: canvas)

    #expect(canvas.grid[0][0].char == "A")
    #expect(canvas.grid[0][4].char == "B")
}

@Test func spacerFillsItsAreaWhenItInheritsBackgroundColor() {
    let canvas = Canvas(width: 5, height: 1)
    let view = HStack {
        Text("A")
        Spacer()
        Text("B")
    }
    .backgroundColor(.blue)

    Render.render(view._makeLayoutNode(), in: Rect(x: 0, y: 0, w: 5, h: 1), to: canvas)

    #expect(canvas.grid[0].map { $0.style.backgroundColor } == Array(repeating: .blue, count: 5))
}

@Test func spaceExpandsAcrossVStackRemainingHeight() {
    let canvas = Canvas(width: 1, height: 5)
    let view = VStack {
        Text("A")
        Spacer()
        Text("B")
    }

    Render.render(view._makeLayoutNode(), in: Rect(x: 0, y: 0, w: 1, h: 5), to: canvas)

    #expect(canvas.grid[0][0].char == "A")
    #expect(canvas.grid[4][0].char == "B")
}

@Test func vStackOverflowKeepsTrailingStatusBarVisible() {
    let canvas = Canvas(width: 6, height: 3)
    let view = VStack {
        VStack {
            Text("A")
            Text("B")
            Text("C")
        }
        Text("status").frame(height: 1)
    }

    Render.render(view._makeLayoutNode(), in: Rect(x: 0, y: 0, w: 6, h: 3), to: canvas)

    #expect(String(canvas.grid[2].map(\.char)) == "status")
}

@Test func explicitSpaceWidthStaysFixedInHStack() {
    let canvas = Canvas(width: 6, height: 1)
    let view = HStack {
        Text("A")
        Spacer(width: 2)
        Text("B")
    }

    Render.render(view._makeLayoutNode(), in: Rect(x: 0, y: 0, w: 6, h: 1), to: canvas)

    #expect(canvas.grid[0][0].char == "A")
    #expect(canvas.grid[0][3].char == "B")
}

@Test func environmentModifierFlowsThroughLayoutTreeToRender() {
    let node = Text("R").environment(\.foregroundColor, .red)._makeLayoutNode()
    let canvas = Canvas(width: 1, height: 1)
    let bounds = Rect(x: 0, y: 0, w: 1, h: 1)

    Render.render(node, in: bounds, to: canvas)

    #expect(canvas.output(colorSupport: .ansi8).contains("\u{001B}[31;40mR"))
}

@Test func textDecorationsFlowThroughEnvironmentValuesIntoCells() {
    let canvas = Canvas(width: 4, height: 1)
    let view = Text("BISU")
        .bold()
        .italic()
        .underline()
        .strikethrough()

    Render.render(view._makeLayoutNode(), in: Rect(x: 0, y: 0, w: 4, h: 1), to: canvas)

    #expect(canvas.grid[0].allSatisfy { $0.style.bold })
    #expect(canvas.grid[0].allSatisfy { $0.style.italic })
    #expect(canvas.grid[0].allSatisfy { $0.style.underline })
    #expect(canvas.grid[0].allSatisfy { $0.style.strikethrough })
    #expect(canvas.output(colorSupport: .ansi8).contains("\u{001B}[1;3;4;9;37;40mBISU"))
}

@Test func textDecorationsOnlyAffectTheirEnvironmentBranch() {
    let canvas = Canvas(width: 2, height: 1)
    let view = HStack {
        Text("A").bold().underline()
        Text("B")
    }

    Render.render(view._makeLayoutNode(), in: Rect(x: 0, y: 0, w: 2, h: 1), to: canvas)

    #expect(canvas.grid[0][0].style.bold)
    #expect(canvas.grid[0][0].style.underline)
    #expect(!canvas.grid[0][1].style.bold)
    #expect(!canvas.grid[0][1].style.underline)
}

@Test func textDecorationFalseOverridesAnInheritedEnvironmentValue() {
    let canvas = Canvas(width: 2, height: 1)
    let view = HStack {
        Text("A").bold(false).underline(false)
        Text("B")
    }
    .bold()
    .underline()

    Render.render(view._makeLayoutNode(), in: Rect(x: 0, y: 0, w: 2, h: 1), to: canvas)

    #expect(!canvas.grid[0][0].style.bold)
    #expect(!canvas.grid[0][0].style.underline)
    #expect(canvas.grid[0][1].style.bold)
    #expect(canvas.grid[0][1].style.underline)
}

@Test func existingViewModifierCompositionBuildsLayoutNodes() {
    let padded = Text("P").padding(1)._makeLayoutNode()
    #expect(padded.measure(proposed: ProposedSize()).w == 3)
    #expect(padded.measure(proposed: ProposedSize()).h == 3)

    let colored = Text("M").modifier(_ForegroundModifier(color: .green))._makeLayoutNode()
    let canvas = Canvas(width: 1, height: 1)
    let bounds = Rect(x: 0, y: 0, w: 1, h: 1)
    Render.render(colored, in: bounds, to: canvas)
    #expect(canvas.output(colorSupport: .ansi8).contains("\u{001B}[32;40mM"))
}

@Test func coreViewWrappersProduceLayoutNodes() {
    let emptySize = EmptyView()._makeLayoutNode().measure(proposed: ProposedSize())
    #expect(emptySize.w == 0)
    #expect(emptySize.h == 0)

    let anySize = AnyView(Text("A"))._makeLayoutNode().measure(proposed: ProposedSize())
    #expect(anySize.w == 1)
    #expect(anySize.h == 1)

    let tuple = TupleView(Text("A"), Text("中"))._makeLayoutNode() as! _ContainerLayoutNode
    #expect(tuple.children.count == 2)
}

@Test func forEachExpandsIdentifiableDataIntoSiblingViews() {
    struct Row: Identifiable {
        let id: Int
        let label: String
    }
    let rows = [Row(id: 1, label: "A"), Row(id: 2, label: "中"), Row(id: 3, label: "C")]
    let node = VStack {
        ForEach(rows) { row in
            Text(row.label)
        }
    }._makeLayoutNode() as! _ContainerLayoutNode
    let canvas = Canvas(width: 2, height: 3)

    Render.render(node, in: Rect(x: 0, y: 0, w: 2, h: 3), to: canvas)

    #expect(node.children.count == 3)
    #expect(canvas.grid[0][0].char == "A")
    #expect(canvas.grid[1][0].char == "中")
    #expect(canvas.grid[2][0].char == "C")
}

@Test func forEachSupportsExplicitIdentityKeyPaths() {
    let node = HStack {
        ForEach(["A", "B", "C"], id: \.self) { value in
            Text(value)
        }
    }._makeLayoutNode() as! _ContainerLayoutNode

    #expect(node.children.count == 3)
    #expect(node.measure(proposed: ProposedSize()).w == 3)
}

@Test func forEachSupportsSwiftUIRangeSyntaxWithoutExplicitIdentity() {
    let node = HStack {
        ForEach(0..<3) { value in
            Text("\(value)")
        }
    }._makeLayoutNode() as! _ContainerLayoutNode

    #expect(node.children.count == 3)
    #expect(node.measure(proposed: ProposedSize()).w == 3)
}

@Test func verticalScrollViewScrollsAndClipsItsContent() {
    let app = TerminalApp(width: 1, height: 4) {
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

@Test func horizontalScrollViewUsesLeftAndRightArrowKeys() {
    let app = TerminalApp(width: 3, height: 1) {
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
    let app = TerminalApp(width: 4, height: 3) {
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

@Test func stateBindingRetainsSynchronousValueSemantics() {
    let state = State(wrappedValue: 1)
    let binding = state.projectedValue

    binding.wrappedValue = 2

    #expect(state.wrappedValue == 2)
}

@Test func toggleRendersBindingValueWithoutInputEvents() {
    let canvas = Canvas(width: 8, height: 1)
    let bounds = Rect(x: 0, y: 0, w: 8, h: 1)

    Render.render(
        Toggle("状态", isOn: .constant(true))._makeLayoutNode(),
        in: bounds,
        to: canvas
    )

    #expect(canvas.grid[0][0].char == "[")
    #expect(canvas.grid[0][1].char == "x")
    #expect(canvas.grid[0][2].char == "]")
}

@Test func textFieldUsesSwiftUIBindingSyntaxAndEditsWideCharacters() {
    let value = State(wrappedValue: "A")
    let app = TerminalApp(width: 6, height: 1) {
        TextField("姓名", text: value.projectedValue)
    }

    _ = app.render()
    #expect(app.send(KeyPress(key: .character("中"), characters: "中")) == .handled)
    #expect(value.wrappedValue == "A中")

    #expect(app.send(KeyPress(key: .leftArrow)) == .handled)
    #expect(app.send(KeyPress(key: .delete)) == .handled)
    #expect(value.wrappedValue == "A")
}

@Test func textFieldMovesFocusWithTabAndShiftTab() {
    let first = State(wrappedValue: "")
    let second = State(wrappedValue: "")
    let app = TerminalApp(width: 5, height: 2) {
        VStack {
            TextField("第一项", text: first.projectedValue)
            TextField("第二项", text: second.projectedValue)
        }
    }

    _ = app.render()
    _ = app.send(KeyPress(key: .character("A"), characters: "A"))
    #expect(first.wrappedValue == "A")
    #expect(second.wrappedValue == "")

    #expect(app.send(KeyPress(key: .tab, characters: "\t")) == .handled)
    _ = app.send(KeyPress(key: .character("B"), characters: "B"))
    #expect(second.wrappedValue == "B")

    #expect(app.send(KeyPress(key: .tab, characters: "\t", modifiers: .shift)) == .handled)
    _ = app.send(KeyPress(key: .character("C"), characters: "C"))
    #expect(first.wrappedValue == "AC")
}

@Test func escapeRemovesTextFieldFocusUntilTabSelectsItAgain() {
    let value = State(wrappedValue: "A")
    var editingChanges: [Bool] = []
    let app = TerminalApp(width: 4, height: 1) {
        TextField(
            "Value",
            text: value.projectedValue,
            onEditingChanged: { editingChanges.append($0) }
        )
    }

    let initial = app.render()
    #expect(initial.grid[0][1].char == "_")
    #expect(editingChanges == [true])

    #expect(app.send(KeyPress(key: .escape, characters: "\u{1B}")) == .handled)
    let unfocused = app.render()
    #expect(String(unfocused.grid[0].map(\.char)) == "A   ")
    #expect(editingChanges == [true, false])
    #expect(app.send(KeyPress(key: .character("B"), characters: "B")) == .ignored)
    #expect(value.wrappedValue == "A")

    #expect(app.send(KeyPress(key: .tab, characters: "\t")) == .handled)
    #expect(app.send(KeyPress(key: .character("B"), characters: "B")) == .handled)
    #expect(value.wrappedValue == "AB")
    #expect(editingChanges == [true, false, true])
}

@Test func optionalFocusStateDrivesTextFieldsAndTracksKeyboardFocus() {
    enum Field: Hashable {
        case first
        case second
    }

    let first = State(wrappedValue: "A")
    let second = State(wrappedValue: "B")
    let focus = FocusState<Field?>(wrappedValue: .second)
    let app = TerminalApp(width: 5, height: 2) {
        VStack {
            TextField("First", text: first.projectedValue)
                .focused(focus.projectedValue, equals: .first)
            TextField("Second", text: second.projectedValue)
                .focused(focus.projectedValue, equals: .second)
        }
    }

    let initial = app.render()
    #expect(initial.grid[0][1].char == " ")
    #expect(initial.grid[1][1].char == "_")
    #expect(app.send(KeyPress(key: .character("X"), characters: "X")) == .handled)
    #expect(second.wrappedValue == "BX")

    #expect(app.send(KeyPress(key: .escape, characters: "\u{1B}")) == .handled)
    #expect(focus.wrappedValue == nil)

    focus.wrappedValue = .first
    _ = app.render()
    #expect(app.send(KeyPress(key: .character("Y"), characters: "Y")) == .handled)
    #expect(first.wrappedValue == "AY")
    #expect(focus.wrappedValue == .first)
}

@Test func boolFocusStateStartsUnfocusedAndTabWritesBackTrue() {
    let value = State(wrappedValue: "")
    let focus = FocusState<Bool>()
    let app = TerminalApp(width: 5, height: 1) {
        TextField("Value", text: value.projectedValue)
            .focused(focus.projectedValue)
    }

    let initial = app.render()
    #expect(initial.grid[0][0].char != "_")
    #expect(focus.wrappedValue == false)

    #expect(app.send(KeyPress(key: .tab, characters: "\t")) == .handled)
    #expect(focus.wrappedValue == true)
    #expect(app.send(KeyPress(key: .escape, characters: "\u{1B}")) == .handled)
    #expect(focus.wrappedValue == false)
}

@Test func borderedViewUsesSharedFocusColorForItsFocusedDescendant() {
    let value = State(wrappedValue: "A")
    let app = TerminalApp(width: 5, height: 3) {
        TextField("Value", text: value.projectedValue)
            .bordered(.gray, style: .rounded)
    }

    let focused = app.render()
    #expect(focused.grid[0][0].style.foregroundColor == .brightCyan)

    #expect(app.send(KeyPress(key: .escape, characters: "\u{1B}")) == .handled)
    let unfocused = app.render()
    #expect(unfocused.grid[0][0].style.foregroundColor == .gray)
}

@Test func focusBorderColorCanBeCustomizedOrDisabled() {
    let customValue = State(wrappedValue: "A")
    let custom = TerminalApp(width: 5, height: 3) {
        TextField("Value", text: customValue.projectedValue)
            .bordered(.gray)
            .focusBorderColor(.brightGreen)
    }
    #expect(custom.render().grid[0][0].style.foregroundColor == .brightGreen)

    let disabledValue = State(wrappedValue: "B")
    let disabled = TerminalApp(width: 5, height: 3) {
        TextField("Value", text: disabledValue.projectedValue)
            .bordered(.magenta)
            .focusEffectDisabled()
    }
    #expect(disabled.render().grid[0][0].style.foregroundColor == .magenta)
}

@Test func groupBoxBackgroundBorderUsesTheSharedFocusEffect() {
    let value = State(wrappedValue: "A")
    let app = TerminalApp(width: 9, height: 5) {
        GroupBox("Input") {
            TextField("Value", text: value.projectedValue)
        }
        .foregroundColor(.gray)
        .focusBorderColor(.brightGreen)
    }

    let focused = app.render()
    #expect(focused.grid[0][0].style.foregroundColor == .brightGreen)

    #expect(app.send(KeyPress(key: .escape, characters: "\u{1B}")) == .handled)
    let unfocused = app.render()
    #expect(unfocused.grid[0][0].style.foregroundColor == .gray)
}

@Test func textFieldShowsPlaceholderCursorAndScrollsHorizontally() {
    let empty = State(wrappedValue: "")
    let placeholderApp = TerminalApp(width: 4, height: 1) {
        TextField("Name", text: empty.projectedValue)
    }
    let placeholder = placeholderApp.render()

    #expect(String(placeholder.grid[0].map(\.char)) == "_Nam")
    #expect(placeholder.grid[0][0].style.foregroundColor == .brightCyan)
    #expect(placeholder.grid[0][0].style.backgroundColor == .black)
    #expect(placeholder.grid[0][1].style.foregroundColor == .gray)
    #expect(placeholder.grid[0][1].style.backgroundColor == .black)

    let long = State(wrappedValue: "ABCDE")
    let scrollingApp = TerminalApp(width: 3, height: 1) {
        TextField("值", text: long.projectedValue)
    }
    #expect(String(scrollingApp.render().grid[0].map(\.char)) == "DE_")
}

@Test func textFieldShowsUnderscoreCursorAfterTheLastCharacter() {
    let value = State(wrappedValue: "Alice")
    let app = TerminalApp(width: 8, height: 1) {
        TextField("姓名", text: value.projectedValue)
    }

    let canvas = app.render()

    #expect(String(canvas.grid[0].map(\.char)) == "Alice_  ")
}

@Test func textFieldUsesAColoredUnderscoreToShowFocus() {
    let first = State(wrappedValue: "A")
    let second = State(wrappedValue: "B")
    let app = TerminalApp(width: 4, height: 2) {
        VStack {
            TextField("First", text: first.projectedValue)
            TextField("Second", text: second.projectedValue)
        }
    }

    let initial = app.render()
    #expect(initial.grid[0][1].char == "_")
    #expect(initial.grid[0][1].style.foregroundColor == .brightCyan)
    #expect(initial.grid[0][3].style.backgroundColor == .black)
    #expect(initial.grid[1][1].char == " ")

    _ = app.send(KeyPress(key: .tab, characters: "\t"))
    let moved = app.render()
    #expect(moved.grid[0][1].char == " ")
    #expect(moved.grid[1][1].char == "_")
    #expect(moved.grid[1][1].style.foregroundColor == .brightCyan)
}

@Test func textFieldInvokesEditingAndCommitCallbacks() {
    let value = State(wrappedValue: "")
    var editingChanges: [Bool] = []
    var commits = 0
    let app = TerminalApp(width: 4, height: 1) {
        TextField(
            "Value",
            text: value.projectedValue,
            onEditingChanged: { editingChanges.append($0) },
            onCommit: { commits += 1 }
        )
    }

    _ = app.render()
    #expect(editingChanges == [true])
    #expect(app.send(KeyPress(key: .returnKey, characters: "\n")) == .handled)
    #expect(commits == 1)
}

@Test func textFieldPreservesCursorWhenAUserDefinedBodyIsRebuilt() {
    struct Form: View {
        @State var value = "AB"

        var body: some View {
            TextField("Value", text: $value)
        }
    }

    let form = Form()
    let app = TerminalApp(width: 5, height: 1) { form }
    _ = app.render()
    _ = app.send(KeyPress(key: .leftArrow))
    _ = app.render()
    _ = app.send(KeyPress(key: .character("X"), characters: "X"))

    #expect(form.value == "AXB")
}

@Test func groupBoxPositionsTitleAtLeadingCenterAndTrailing() {
    func titleColumn(_ alignment: HorizontalAlignment) -> Int? {
        let canvas = Canvas(width: 20, height: 3)
        let bounds = Rect(x: 0, y: 0, w: 20, h: 3)
        let group = GroupBox("T", titleAlignment: alignment) { Text("X") }
        Render.render(group._makeLayoutNode(), in: bounds, to: canvas)
        return canvas.grid[0].firstIndex { $0.char == "T" }
    }

    #expect(titleColumn(.leading) == 2)
    #expect(titleColumn(.center) == 9)
    #expect(titleColumn(.trailing) == 17)
}

@Test func groupBoxReservesEnoughWidthForItsTitle() {
    let group = GroupBox("较长标题") { Text("X") }
    let node = group._makeLayoutNode()
    let size = node.measure(proposed: ProposedSize())
    let canvas = Canvas(width: size.w, height: size.h)

    Render.render(node, in: Rect(x: 0, y: 0, w: size.w, h: size.h), to: canvas)

    #expect(size.w >= "较长标题".displayWidth + 4)
    #expect(canvas.grid[0][size.w - 1].char == "╮")
}

@Test func geometryReaderReceivesLaidOutSize() {
    let canvas = Canvas(width: 8, height: 2)
    let view = GeometryReader { proxy in
        Text("\(proxy.size.w)x\(proxy.size.h)")
    }

    Render.render(view._makeLayoutNode(), in: Rect(x: 0, y: 0, w: 8, h: 2), to: canvas)

    let plain = canvas.output().replacingOccurrences(
        of: "\u{001B}\\[[0-9;]*m",
        with: "",
        options: .regularExpression
    )
    #expect(plain.hasPrefix("8x2"))
}

@Test func keyPressModifierFiltersAndBubblesEvents() {
    var received: [String] = []
    let app = TerminalApp(width: 4, height: 1) {
        Text("key")
            .onKeyPress(.leftArrow) { _ in
                received.append("left")
                return .handled
            }
            .onKeyPress { event in
                received.append(event.characters)
                return .handled
            }
    }

    #expect(app.send(KeyPress(key: .leftArrow)) == .handled)
    #expect(received == ["left"])

    #expect(app.send(KeyPress(key: .character("x"), characters: "x")) == .handled)
    #expect(received == ["left", "x"])
}

@Test func terminalKeyDecoderHandlesArrowsControlAndUTF8() {
    #expect(_KeyPressDecoder.decode([0x1B, 0x5B, 0x41]).key == .upArrow)
    #expect(_KeyPressDecoder.decode([0x03]).modifiers.contains(.control))

    let event = _KeyPressDecoder.decode(Array("中".utf8))
    #expect(event.key == .character("中"))
    #expect(event.characters == "中")
    #expect(_KeyPressDecoder.decode([0x1B, 0x5B, 0x5A]).modifiers.contains(.shift))
}

@Test func backgroundDoesNotChangeMeasuredContentSize() {
    let size = Text("A")
        .background(_Box(style: .single))
        ._makeLayoutNode()
        .measure(proposed: ProposedSize())

    #expect(size.w == 1)
    #expect(size.h == 1)
}

@Test func borderedUsesExistingSpaceAndInsetsItsChild() {
    let intrinsicNode = Text("A").bordered(.green, style: .ascii)._makeLayoutNode()
    let size = intrinsicNode.measure(proposed: ProposedSize())
    let node = Text("A")
        .frame(width: 3, height: 3, alignment: .center)
        .bordered(.green, style: .ascii)
        ._makeLayoutNode()
    let canvas = Canvas(width: 3, height: 3)

    Render.render(node, in: Rect(x: 0, y: 0, w: 3, h: 3), to: canvas)

    #expect(size.w == 3)
    #expect(size.h == 3)
    #expect(canvas.grid[0][0].char == "+")
    #expect(canvas.grid[1][1].char == "A")
}

@Test func sharedBordersBecomeTableJunctions() {
    let canvas = Canvas(width: 7, height: 5)

    canvas.drawBox(
        in: Rect(x: 0, y: 0, w: 4, h: 3),
        style: .single,
        foreground: .white,
        background: nil
    )
    canvas.drawBox(
        in: Rect(x: 3, y: 0, w: 4, h: 3),
        style: .single,
        foreground: .white,
        background: nil
    )
    canvas.drawBox(
        in: Rect(x: 0, y: 2, w: 4, h: 3),
        style: .single,
        foreground: .white,
        background: nil
    )
    canvas.drawBox(
        in: Rect(x: 3, y: 2, w: 4, h: 3),
        style: .single,
        foreground: .white,
        background: nil
    )

    #expect(canvas.grid[0][3].char == "┬")
    #expect(canvas.grid[2][0].char == "├")
    #expect(canvas.grid[2][3].char == "┼")
    #expect(canvas.grid[2][6].char == "┤")
    #expect(canvas.grid[4][3].char == "┴")
}

@Test func tableUsesSwiftUIStyleColumnDeclarations() {
    struct Player {
        let name: String
        let score: Int
    }

    let table = Table([
        Player(name: "Alice", score: 12),
        Player(name: "小明", score: 8),
    ]) {
        TableColumn("姓名", value: \.name)
        TableColumn("分数", alignment: .trailing) { player in
            Text("\(player.score)")
        }
    }
    let node = table._makeLayoutNode()
    let size = node.measure(proposed: ProposedSize())
    let canvas = Canvas(width: size.w, height: size.h)

    Render.render(node, in: Rect(x: 0, y: 0, w: size.w, h: size.h), to: canvas)

    #expect(size.w == 16)
    #expect(size.h == 7)
    #expect(canvas.grid[0][0].char == "┌")
    #expect(canvas.grid[0][8].char == "┬")
    #expect(canvas.grid[2][8].char == "┼")
    #expect(canvas.grid[1][2].char == "姓")
    #expect(canvas.grid[3][2].char == "A")
    #expect(canvas.grid[5][2].char == "小")
    #expect(canvas.grid[3][12].char == "1")
    #expect(canvas.grid[3][13].char == "2")
}

@Test func tableWrapsWideCellContentWhenConstrained() {
    struct Row { let value: String }
    let node = Table([Row(value: "中文测试")]) {
        TableColumn("内容", value: \.value)
    }._makeLayoutNode()
    let canvas = Canvas(width: 7, height: 6)

    Render.render(node, in: Rect(x: 0, y: 0, w: 7, h: 6), to: canvas)

    #expect(canvas.grid[3][2].char == "中")
    #expect(canvas.grid[4][2].char == "文")
    #expect(canvas.grid[4][4].char == "…")
    #expect(canvas.grid[5][0].char == "└")
    #expect(canvas.grid[5][6].char == "┘")
}

@Test func sharedDoubleBordersUseDoubleJunctions() {
    let canvas = Canvas(width: 7, height: 3)
    canvas.drawBox(in: Rect(x: 0, y: 0, w: 4, h: 3), style: .double, foreground: .white, background: nil)
    canvas.drawBox(in: Rect(x: 3, y: 0, w: 4, h: 3), style: .double, foreground: .white, background: nil)

    #expect(canvas.grid[0][3].char == "╦")
    #expect(canvas.grid[2][3].char == "╩")
}

@Test func stacksDoNotMeasureBeyondTheirProposal() {
    let content = VStack {
        Text("1")
        Text("2")
        Text("3")
        Text("4")
    }

    let vertical = content._makeLayoutNode().measure(proposed: ProposedSize(width: 3, height: 2))
    let root = ZStack { content }._makeLayoutNode().measure(proposed: ProposedSize(width: 3, height: 2))

    #expect(vertical.w <= 3)
    #expect(vertical.h == 2)
    #expect(root.w <= 3)
    #expect(root.h == 2)
}

@Test func zeroHeightRenderableDoesNotOverwriteBorder() {
    let canvas = Canvas(width: 5, height: 3)
    let view = VStack {
        Text("first")
        Text("second")
    }
    .padding(1)
    .background(_Box(style: .single))

    Render.render(view._makeLayoutNode(), in: Rect(x: 0, y: 0, w: 5, h: 3), to: canvas)

    #expect(canvas.grid[2][0].char == "└")
    #expect(canvas.grid[2][4].char == "┘")
    #expect(canvas.grid[2][2].char == "─")
}

@Test func canvasSkipsOnlyWideCharacterContinuationCells() {
    let canvas = Canvas(width: 4, height: 1)
    canvas.drawText(x: 0, y: 0, text: "中A", foreground: .white)

    #expect(canvas.grid[0][1].isSpace)
    #expect(canvas.grid[0][1].render() == nil)
    #expect(!canvas.grid[0][3].isSpace)
    #expect(canvas.grid[0][3].render() != nil)

    let plain = canvas.output().replacingOccurrences(
        of: "\u{001B}\\[[0-9;]*m",
        with: "",
        options: .regularExpression
    )
    #expect(plain == "中A ")
    #expect(Segment.cellLength(of: plain) == 4)
}

@Test func canvasBatchesAdjacentCellsWithTheSameStyle() {
    let canvas = Canvas(width: 9, height: 1)
    canvas.drawText(x: 0, y: 0, text: "Swift 5.9", foreground: .orange)

    let output = canvas.output(colorSupport: .ansi8)
    let resetCount = output.components(separatedBy: "\u{001B}[0m").count - 1

    #expect(resetCount == 1)
    #expect(output.contains("Swift 5.9"))
}

@Test func positionedCanvasOutputUsesAbsoluteRowsWithoutNewlines() {
    let canvas = Canvas(width: 2, height: 2)
    canvas.drawText(x: 0, y: 0, text: "AB", foreground: .white)
    canvas.drawText(x: 0, y: 1, text: "CD", foreground: .white)

    let output = canvas.positionedOutput(colorSupport: .none)

    #expect(output == "\u{001B}[1;1HAB\u{001B}[2;1HCD")
    #expect(!output.contains("\n"))
}

@Test func positionedCanvasOutputOnlyRewritesChangedRows() {
    let previous = Canvas(width: 4, height: 3)
    previous.drawText(x: 0, y: 0, text: "AAAA", foreground: .white)
    previous.drawText(x: 0, y: 1, text: "BBBB", foreground: .white)

    let current = Canvas(width: 4, height: 3)
    current.drawText(x: 0, y: 0, text: "AAAA", foreground: .white)
    current.drawText(x: 0, y: 1, text: "BBXB", foreground: .white)

    let output = current.positionedOutput(comparedTo: previous, colorSupport: .none)
    #expect(output == "\u{001B}[2;1HBBXB")
}

@Test func backgroundColorFillsPaddingAndOtherUnpaintedCells() {
    let canvas = Canvas(width: 5, height: 3)
    let view = Text("X")
        .padding(horizontal: 2, vertical: 1)
        .backgroundColor(.blue)

    Render.render(view._makeLayoutNode(), in: Rect(x: 0, y: 0, w: 5, h: 3), to: canvas)

    for row in canvas.grid {
        #expect(row.allSatisfy { $0.style.backgroundColor == .blue })
    }
}

@Test func overlappingWideGlyphsDoNotLeaveOrphanContinuationCells() {
    let canvas = Canvas(width: 14, height: 1)
    let bounds = Rect(x: 0, y: 0, w: 14, h: 1)
    let stack = ZStack(alignment: .center) {
        Text("ZStack 底层")
        Text("叠加")
    }

    Render.render(stack._makeLayoutNode(), in: bounds, to: canvas)

    #expect(!canvas.grid[0][9].isSpace)
    #expect(canvas.grid[0][10].char == "层")

    let plain = canvas.output().replacingOccurrences(
        of: "\u{001B}\\[[0-9;]*m",
        with: "",
        options: .regularExpression
    )
    #expect(plain == " ZSta叠加 层  ")
    #expect(Segment.cellLength(of: plain) == 14)
}

@Test func terminalColorSupportDetectionUsesEnvironmentAndTTY() {
    #expect(TerminalColorSupport.detect(environment: ["TERM": "xterm"], isTerminal: false) == .none)
    #expect(TerminalColorSupport.detect(environment: ["NO_COLOR": "1"], isTerminal: true) == .none)
    #expect(TerminalColorSupport.detect(environment: ["TERM": "dumb"], isTerminal: true) == .none)
    #expect(TerminalColorSupport.detect(environment: ["TERM": "xterm"], isTerminal: true) == .ansi8)
    #expect(TerminalColorSupport.detect(environment: ["TERM": "xterm-256color"], isTerminal: true) == .ansi256)
    #expect(TerminalColorSupport.detect(environment: ["COLORTERM": "truecolor"], isTerminal: true) == .trueColor)
}

@Test func colorsEncodeAndDowngradeForEachTerminalDepth() {
    #expect(Color.red.rawValue == 1)
    #expect(Color.red.foregroundCode(for: .ansi8) == "31")
    #expect(Color.brightRed.foregroundCode(for: .ansi8) == "31")
    #expect(Color.brightRed.foregroundCode(for: .ansi256) == "91")
    #expect(Color.indexed(196).foregroundCode(for: .ansi256) == "38;5;196")
    #expect(Color.orange.foregroundCode(for: .trueColor) == "38;2;255;165;0")
    #expect(Color.navy.backgroundCode(for: .trueColor) == "48;2;0;0;128")
    #expect(TerminalColorSupport.ansi8.supportsNatively(.red))
    #expect(!TerminalColorSupport.ansi8.supportsNatively(.orange))
    #expect(TerminalColorSupport.trueColor.supportsNatively(.orange))

    #expect(
        "X".colored(fg: .orange, bg: .navy, support: .trueColor) ==
            "\u{001B}[38;2;255;165;0;48;2;0;0;128mX\u{001B}[0m"
    )
    #expect("X".colored(fg: .orange, bg: nil, support: .none) == "X")
}

@Test func rgbColorIdentityDoesNotCollapseToItsNearestTerminalPaletteEntry() {
    let first = Color.rgb(1, 2, 3)
    let second = Color.rgb(2, 3, 4)

    // 两者可能降级到同一个 xterm 色号，但仍是不同的声明颜色。
    #expect(first != second)
    #expect(Set([first, second]).count == 2)
}

@Test func animatedTextRendersSingleFrameAndHandlesEmptyFrames() {
    let single = Canvas(width: 3, height: 1)
    Render.render(
        AnimatedText(["⠋"])._makeLayoutNode(),
        in: Rect(x: 0, y: 0, w: 3, h: 1),
        to: single
    )
    #expect(single.grid[0][0].char == "⠋")

    let empty = AnimatedText([])._makeLayoutNode()
    #expect(empty.measure(proposed: ProposedSize(width: 3, height: 1)).w == 0)
}
