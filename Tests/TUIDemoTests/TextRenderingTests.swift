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

