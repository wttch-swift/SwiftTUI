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
    let app = _TerminalAppHost(width: 6, height: 1) {
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
    let app = _TerminalAppHost(width: 5, height: 2) {
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
    let app = _TerminalAppHost(width: 4, height: 1) {
        TextField(
            "Value",
            text: value.projectedValue,
            onEditingChanged: { editingChanges.append($0) }
        )
    }

    let initial = app.render()
    #expect(initial.grid[0][1].char == "▏")
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
    let app = _TerminalAppHost(width: 5, height: 2) {
        VStack {
            TextField("First", text: first.projectedValue)
                .focused(focus.projectedValue, equals: .first)
            TextField("Second", text: second.projectedValue)
                .focused(focus.projectedValue, equals: .second)
        }
    }

    let initial = app.render()
    #expect(initial.grid[0][1].char == " ")
    #expect(initial.grid[1][1].char == "▏")
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
    let app = _TerminalAppHost(width: 5, height: 1) {
        TextField("Value", text: value.projectedValue)
            .focused(focus.projectedValue)
    }

    let initial = app.render()
    #expect(initial.grid[0][0].char != "▏")
    #expect(focus.wrappedValue == false)

    #expect(app.send(KeyPress(key: .tab, characters: "\t")) == .handled)
    #expect(focus.wrappedValue == true)
    #expect(app.send(KeyPress(key: .escape, characters: "\u{1B}")) == .handled)
    #expect(focus.wrappedValue == false)
}

@Test func borderedViewUsesSharedFocusColorForItsFocusedDescendant() {
    let value = State(wrappedValue: "A")
    let app = _TerminalAppHost(width: 5, height: 3) {
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
    let custom = _TerminalAppHost(width: 5, height: 3) {
        TextField("Value", text: customValue.projectedValue)
            .bordered(.gray)
            .focusBorderColor(.brightGreen)
    }
    #expect(custom.render().grid[0][0].style.foregroundColor == .brightGreen)

    let disabledValue = State(wrappedValue: "B")
    let disabled = _TerminalAppHost(width: 5, height: 3) {
        TextField("Value", text: disabledValue.projectedValue)
            .bordered(.magenta)
            .focusEffectDisabled()
    }
    #expect(disabled.render().grid[0][0].style.foregroundColor == .magenta)
}

@Test func accentColorDrivesFocusedBorderAndTextFieldCursor() {
    let borderedValue = State(wrappedValue: "A")
    let bordered = _TerminalAppHost(width: 5, height: 3) {
        TextField("Value", text: borderedValue.projectedValue)
            .bordered(.gray)
            .accentColor(.brightMagenta)
    }
    #expect(bordered.render().grid[0][0].style.foregroundColor == .brightMagenta)

    let cursorValue = State(wrappedValue: "")
    let cursor = _TerminalAppHost(width: 6, height: 1) {
        TextField("Value", text: cursorValue.projectedValue)
            .accentColor(.brightGreen)
    }
    let focused = cursor.render()
    #expect(focused.grid[0][0].char == "▏")
    #expect(focused.grid[0][0].style.foregroundColor == .brightGreen)
}

@Test func groupBoxBackgroundBorderUsesTheSharedFocusEffect() {
    let value = State(wrappedValue: "A")
    let app = _TerminalAppHost(width: 9, height: 5) {
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
    let placeholderApp = _TerminalAppHost(width: 4, height: 1) {
        TextField("Name", text: empty.projectedValue)
    }
    let placeholder = placeholderApp.render()

    #expect(String(placeholder.grid[0].map(\.char)) == "▏Nam")
    #expect(placeholder.grid[0][0].style.foregroundColor == .brightCyan)
    #expect(placeholder.grid[0][0].style.backgroundColor == .black)
    #expect(placeholder.grid[0][1].style.foregroundColor == .gray)
    #expect(placeholder.grid[0][1].style.backgroundColor == .black)

    let long = State(wrappedValue: "ABCDE")
    let scrollingApp = _TerminalAppHost(width: 3, height: 1) {
        TextField("值", text: long.projectedValue)
    }
    #expect(String(scrollingApp.render().grid[0].map(\.char)) == "DE▏")
}

@Test func textFieldShowsInsertionCursorAfterTheLastCharacter() {
    let value = State(wrappedValue: "Alice")
    let app = _TerminalAppHost(width: 8, height: 1) {
        TextField("姓名", text: value.projectedValue)
    }

    let canvas = app.render()

    #expect(String(canvas.grid[0].map(\.char)) == "Alice▏  ")
}

@Test func textFieldUsesAColoredInsertionCursorToShowFocus() {
    let first = State(wrappedValue: "A")
    let second = State(wrappedValue: "B")
    let app = _TerminalAppHost(width: 4, height: 2) {
        VStack {
            TextField("First", text: first.projectedValue)
            TextField("Second", text: second.projectedValue)
        }
    }

    let initial = app.render()
    #expect(initial.grid[0][1].char == "▏")
    #expect(initial.grid[0][1].style.foregroundColor == .brightCyan)
    #expect(initial.grid[0][3].style.backgroundColor == .black)
    #expect(initial.grid[1][1].char == " ")

    _ = app.send(KeyPress(key: .tab, characters: "\t"))
    let moved = app.render()
    #expect(moved.grid[0][1].char == " ")
    #expect(moved.grid[1][1].char == "▏")
    #expect(moved.grid[1][1].style.foregroundColor == .brightCyan)
}

@Test func borderedChatInputClipsTextBeforeTheRightBorder() {
    let value = State(wrappedValue: "")
    let app = _TerminalAppHost(width: 34, height: 3) {
        HStack(alignment: .center) {
            Text("❯")
                .foregroundColor(.brightCyan)
                .bold()
            Spacer(width: 1)
            TextField(
                "输入消息，回车发送到当前对话……",
                text: value.projectedValue
            )
            Spacer(width: 1)
        }
        .padding(horizontal: 1)
        .frame(width: 30, height: 3, alignment: .center)
        .bordered(.brightCyan, style: .rounded)
    }

    let initial = app.render()
    #expect(initial.grid[1][28].char == " ")
    #expect(initial.grid[1][29].char == "│")

    for _ in 0..<40 {
        #expect(app.send(KeyPress(key: .character("w"), characters: "w")) == .handled)
    }

    let canvas = app.render()
    #expect(canvas.grid[1][28].char == " ")
    #expect(canvas.grid[1][29].char == "│")
    #expect(String(canvas.grid[1][30..<34].map(\.char)) == "    ")
}

@Test func textFieldInvokesEditingAndCommitCallbacks() {
    let value = State(wrappedValue: "")
    var editingChanges: [Bool] = []
    var commits = 0
    let app = _TerminalAppHost(width: 4, height: 1) {
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
    let app = _TerminalAppHost(width: 5, height: 1) { form }
    _ = app.render()
    _ = app.send(KeyPress(key: .leftArrow))
    _ = app.render()
    _ = app.send(KeyPress(key: .character("X"), characters: "X"))

    #expect(form.value == "AXB")
}

@Test func focusedTextFieldAndCursorFollowForEachIDAfterReordering() {
    struct ReorderableFields: View {
        let order: Binding<[Int]>
        let text: (Int) -> Binding<String>

        var body: some View {
            VStack {
                ForEach(order.wrappedValue, id: \.self) { id in
                    TextField("field \(id)", text: text(id))
                }
            }
        }
    }

    var order = [1, 2]
    var values = [1: "AB", 2: "CD"]
    let app = _TerminalAppHost(width: 12, height: 2) {
        ReorderableFields(
            order: Binding(get: { order }, set: { order = $0 }),
            text: { id in
                Binding(
                    get: { values[id] ?? "" },
                    set: { values[id] = $0 }
                )
            }
        )
    }

    _ = app.render()
    #expect(app.send(KeyPress(key: .leftArrow)) == .handled)
    order = [2, 1]
    _ = app.render()
    #expect(app.send(KeyPress(key: .character("x"), characters: "x")) == .handled)

    #expect(values[1] == "AxB")
    #expect(values[2] == "CD")
}
