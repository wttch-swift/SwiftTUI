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

@Test func checkmarkTitleUsesTextWidthWhenDrawingGroupBoxBorder() {
    let title = "✓ 2. DeepSeek 回答"
    #expect(title.displayWidth == 18)

    let group = GroupBox(title) { Text("content") }
    let node = group._makeLayoutNode()
    let size = node.measure(proposed: ProposedSize())
    let canvas = Canvas(width: size.w, height: size.h)

    Render.render(node, in: Rect(x: 0, y: 0, w: size.w, h: size.h), to: canvas)

    #expect(canvas.grid[0][2].char == "✓")
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
    let app = _TerminalAppHost(width: 4, height: 1) {
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

