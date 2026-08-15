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

@Test func viewBuildsLayoutNodeAndRenderWritesCanvas() {
    let view = VStack {
        Text("AB")
        Text("中")
    }
    let node = view._makeLayoutNode() as! any _ContainerLayoutable

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

    let node = CustomLabel()._makeLayoutNode() as! any _ContainerLayoutable

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

    let tuple = TupleView(Text("A"), Text("中"))._makeLayoutNode() as! any _ContainerLayoutable
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
    }._makeLayoutNode() as! any _ContainerLayoutable
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
    }._makeLayoutNode() as! any _ContainerLayoutable

    #expect(node.children.count == 3)
    #expect(node.measure(proposed: ProposedSize()).w == 3)
}

@Test func forEachCarriesStableLayoutIdentityAcrossReordering() {
    struct Row: Identifiable {
        let id: Int
        let label: String
    }
    let original = [Row(id: 10, label: "A"), Row(id: 20, label: "B"), Row(id: 30, label: "C")]
    let reordered = [original[2], original[0], original[1]]

    func identities(_ rows: [Row]) -> [(AnyHashable, Int)] {
        let node = VStack {
            ForEach(rows) { row in
                Text(row.label)
            }
        }._makeLayoutNode() as! any _ContainerLayoutable
        return node.children.compactMap { child in
            guard let identified = child as? any _IdentifiedLayoutNode else { return nil }
            return (identified.reconciliationID, identified.reconciliationChildIndex)
        }
    }

    let first = identities(original)
    let second = identities(reordered)
    #expect(first.map(\.0) == [AnyHashable(10), AnyHashable(20), AnyHashable(30)])
    #expect(second.map(\.0) == [AnyHashable(30), AnyHashable(10), AnyHashable(20)])
    #expect(first.allSatisfy { $0.1 == 0 })
    #expect(Set(first.map(\.0)) == Set(second.map(\.0)))
}

@Test func explicitViewIDReachesTheLayoutNodeWithoutChangingLayout() {
    let node = Text("stable").id("message-42")._makeLayoutNode()
    let identified = node as? any _IdentifiedLayoutNode

    #expect(identified?.reconciliationID == AnyHashable("message-42"))
    #expect(node.measure(proposed: ProposedSize()).w == 6)
    #expect(node.measure(proposed: ProposedSize()).h == 1)
}

@Test func forEachSupportsSwiftUIRangeSyntaxWithoutExplicitIdentity() {
    let node = HStack {
        ForEach(0..<3) { value in
            Text("\(value)")
        }
    }._makeLayoutNode() as! any _ContainerLayoutable

    #expect(node.children.count == 3)
    #expect(node.measure(proposed: ProposedSize()).w == 3)
}

@Test func reconciliationMovesInteractionStateByStableIDAfterReordering() {
    let oldFirst = ReconciliationProbeNode(value: 10)
    let oldSecond = ReconciliationProbeNode(value: 20)
    oldSecond.setFocused(true)
    let previous = ReconciliationProbeContainer(children: [
        _makeIdentifiedLayoutNode(child: oldFirst, id: AnyHashable("first"), childIndex: 0),
        _makeIdentifiedLayoutNode(child: oldSecond, id: AnyHashable("second"), childIndex: 0),
    ])

    let newSecond = ReconciliationProbeNode(value: 0)
    let newFirst = ReconciliationProbeNode(value: 0)
    let current = ReconciliationProbeContainer(children: [
        _makeIdentifiedLayoutNode(child: newSecond, id: AnyHashable("second"), childIndex: 0),
        _makeIdentifiedLayoutNode(child: newFirst, id: AnyHashable("first"), childIndex: 0),
    ])

    LayoutReconciler.reconcile(from: previous, to: current)

    #expect(newFirst.value == 10)
    #expect(newSecond.value == 20)
    #expect(newFirst.isFocused == false)
    #expect(newSecond.isFocused == true)
}

private final class ReconciliationProbeNode: _FocusTargetLayoutNode {
    var value: Int
    private(set) var isFocused = false

    init(value: Int) {
        self.value = value
    }

    func measure(proposed: ProposedSize) -> Size { Size(w: 1, h: 1) }
    func layout(in rect: Rect) {}
    func setFocused(_ focused: Bool) { isFocused = focused }
    func handleFocusedKey(_ event: KeyPress) -> KeyPress.Result { .ignored }
    func restoreInteractionState(from node: any _FocusTargetLayoutNode) {
        guard let previous = node as? ReconciliationProbeNode else { return }
        value = previous.value
        isFocused = previous.isFocused
    }
}

private final class ReconciliationProbeContainer: _LayoutContainerStorage, _ContainerLayoutable {
    func measure(proposed: ProposedSize) -> Size {
        Size(w: children.count, h: children.isEmpty ? 0 : 1)
    }

    func layout(in rect: Rect) {
        for (index, child) in children.enumerated() {
            child.layout(in: Rect(x: rect.x + index, y: rect.y, w: 1, h: min(1, rect.h)))
        }
    }
}
