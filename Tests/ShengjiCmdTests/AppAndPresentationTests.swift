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

@Test func terminalSignalsMapToTheirPOSIXNumbers() {
    let cases: [(TerminalSignal, Int32)] = [
        (.interrupt, SIGINT),
        (.terminate, SIGTERM),
        (.hangup, SIGHUP),
        (.quit, SIGQUIT),
        (.suspend, SIGTSTP),
        (.resume, SIGCONT),
        (.windowSizeChanged, SIGWINCH),
    ]

    for (signal, number) in cases {
        #expect(signal.signalNumber == number)
        #expect(TerminalSignal(signalNumber: number) == signal)
    }
    #expect(TerminalSignal(signalNumber: SIGUSR1) == nil)
}

@Test func tabViewNavigationWinsOverFocusedTextFieldArrowKeys() {
    var selection = TestTab.settings
    var text = "abc"
    let app = _TerminalAppHost(width: 20, height: 4) {
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
        let app = _TerminalAppHost(width: 20, height: 10) {
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

@Test func sheetAllowsTabToMoveFocusInsidePresentedContent() {
    var isPresented = true
    var first = ""
    var second = ""
    let app = _TerminalAppHost(width: 24, height: 8) {
        Text("底层")
            .sheet(isPresented: Binding(get: { isPresented }, set: { isPresented = $0 })) {
                VStack {
                    TextField("First", text: Binding(get: { first }, set: { first = $0 }))
                    TextField("Second", text: Binding(get: { second }, set: { second = $0 }))
                }
            }
    }

    _ = app.render()
    #expect(app.send(KeyPress(key: .character("A"), characters: "A")) == .handled)
    #expect(first == "A")
    #expect(second == "")

    #expect(app.send(KeyPress(key: .tab, characters: "\t")) == .handled)
    #expect(app.send(KeyPress(key: .character("B"), characters: "B")) == .handled)
    #expect(first == "A")
    #expect(second == "B")
}

@Test func sheetInitializesFocusStateFieldsBeforeTabMovesFocus() {
    enum SheetField: Hashable {
        case first
        case second
    }

    var isPresented = true
    var first = ""
    var second = ""
    let focus = FocusState<SheetField?>()
    let app = _TerminalAppHost(width: 24, height: 8) {
        Text("底层")
            .sheet(isPresented: Binding(get: { isPresented }, set: { isPresented = $0 })) {
                VStack {
                    TextField("First", text: Binding(get: { first }, set: { first = $0 }))
                        .focused(focus.projectedValue, equals: .first)
                    TextField("Second", text: Binding(get: { second }, set: { second = $0 }))
                        .focused(focus.projectedValue, equals: .second)
                }
            }
    }

    _ = app.render()
    #expect(focus.wrappedValue == .first)
    #expect(app.send(KeyPress(key: .character("A"), characters: "A")) == .handled)
    #expect(first == "A")
    #expect(second == "")

    #expect(app.send(KeyPress(key: .tab, characters: "\t")) == .handled)
    #expect(focus.wrappedValue == .second)
    #expect(app.send(KeyPress(key: .character("B"), characters: "B")) == .handled)
    #expect(first == "A")
    #expect(second == "B")
}

@Test func toastUsesAlignmentWithoutBlockingUnderlyingContent() {
    var isPresented = true
    var keyCount = 0
    let app = _TerminalAppHost(width: 20, height: 10) {
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
    let app = _TerminalAppHost(width: 28, height: 3) {
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
    let app = _TerminalAppHost(width: 20, height: 3) {
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

@Test func onEventHandlesKeyPressThroughUnifiedDispatcher() {
    var received = false
    let app = _TerminalAppHost(width: 20, height: 2) {
        Text("事件")
            .onEvent { event in
                guard case .key(let keyPress) = event,
                      keyPress.key == .character("x") else {
                    return .ignored
                }
                received = true
                return .handled
            }
    }

    _ = app.render()
    #expect(app.send(KeyPress(key: .character("x"), characters: "x")) == .handled)
    #expect(received)
}

@Test func consumedOnEventStopsPropagationToOuterViews() {
    var innerCount = 0
    var outerCount = 0
    let app = _TerminalAppHost(width: 20, height: 2) {
        Text("事件")
            .onEvent { event in
                guard case .key = event else { return .ignored }
                innerCount += 1
                return .handled
            }
            .onEvent { event in
                guard case .key = event else { return .ignored }
                outerCount += 1
                return .handled
            }
    }

    _ = app.render()
    #expect(app.send(KeyPress(key: .character("x"), characters: "x")) == .handled)
    #expect(innerCount == 1)
    #expect(outerCount == 0)
}

