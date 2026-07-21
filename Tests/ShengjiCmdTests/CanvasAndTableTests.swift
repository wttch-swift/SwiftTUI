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

@Test func zStackPassesTheSameProposalToFlexibleChildren() {
    final class FlexibleProbe: _Layoutable, _FlexibleLayoutNode {
        var proposals: [ProposedSize] = []
        var expandsHorizontally: Bool { true }
        var expandsVertically: Bool { true }

        func measure(proposed: ProposedSize) -> Size {
            proposals.append(proposed)
            return Size(w: proposed.width ?? 1, h: proposed.height ?? 1)
        }

        func layout(in rect: Rect) {}
    }

    let child = FlexibleProbe()
    let node = _makeZStackLayoutNode(children: [child], alignment: .center)

    let measured = node.measure(proposed: ProposedSize(width: 7, height: 3))
    node.layout(in: Rect(x: 0, y: 0, w: 5, h: 2))

    #expect(measured == Size(w: 7, h: 3))
    #expect(child.proposals.count == 2)
    #expect(child.proposals[0].width == 7)
    #expect(child.proposals[0].height == 3)
    #expect(child.proposals[1].width == 5)
    #expect(child.proposals[1].height == 2)
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
