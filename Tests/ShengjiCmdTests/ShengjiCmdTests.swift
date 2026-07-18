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

private enum TestTab: Hashable {
    case home
    case settings
}

private struct IncrementalRefreshBenchmarkView: View {
    let counter: Binding<Int>

    var body: some View {
        // 这个视图故意模拟“终端仪表盘”类场景：大面积背景、边框、进度条和说明文字
        // 大多不变，只有顶部 frame 计数和底部刷新计数随帧变化。这样可以观察
        // RenderCache 对稳定子树的收益，以及增量输出只刷新少数行时的收益。
        ZStack {
            Spacer()
                .backgroundColor(.rgb(8, 13, 24))

            VStack {
                HStack {
                    Text(" ◆ ")
                        .foregroundColor(.rgb(8, 13, 24))
                        .backgroundColor(.brightCyan)
                        .bold()
                    Text(" 增量刷新基准测试 ")
                        .foregroundColor(.brightWhite)
                        .bold()
                    Spacer()
                    Text("frame \(counter.wrappedValue)")
                        .foregroundColor(.rgb(148, 163, 184))
                }
                .frame(height: 2, alignment: .center)
                .backgroundColor(.rgb(17, 25, 42))

                Spacer(height: 1)
                GroupBox("稳定内容", style: .rounded) {
                    Text("这一块模拟仪表盘中每帧都保持不变的大面积内容。")
                        .foregroundColor(.rgb(203, 213, 225))
                    Spacer(height: 1)
                    ProgressBar(value: 0.68, width: 42)
                        .tint(.brightCyan)
                        .trackColor(.rgb(15, 23, 42))
                }
                .foregroundColor(.brightCyan)

                Spacer()
                HStack(alignment: .center) {
                    Text(" ● 实时 ")
                        .foregroundColor(.rgb(8, 13, 24))
                        .backgroundColor(.brightGreen)
                        .bold()
                    Text(" 只有计数器和状态栏变化")
                        .foregroundColor(.rgb(148, 163, 184))
                    Spacer()
                    Text("刷新 #\(counter.wrappedValue)  ")
                        .foregroundColor(.rgb(100, 116, 139))
                }
                .frame(height: 1, alignment: .center)
                .backgroundColor(.rgb(17, 25, 42))
            }
        }
    }
}

private struct RebuiltScrollBenchmarkView: View {
    let text: Binding<String>

    var body: some View {
        VStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack {
                    ForEach(0..<4) { value in
                        Text("\(value)")
                    }
                }
            }
            .frame(height: 2)

            TextField("Input", text: text)
        }
    }
}

private struct RebuiltFocusedScrollBenchmarkView: View {
    enum Target: Hashable {
        case history
        case input
    }

    let focus: FocusState<Target?>
    let text: Binding<String>

    var body: some View {
        VStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack {
                    ForEach(0..<4) { value in
                        Text("\(value)")
                    }
                }
            }
            .frame(height: 2)
            .focused(focus.projectedValue, equals: .history)

            TextField("Input", text: text)
                .focused(focus.projectedValue, equals: .input)
        }
    }
}

private func benchmarkAverageNanoseconds(iterations: Int, _ operation: () -> Void) -> UInt64 {
    // 单次渲染很容易受到调度和计时器抖动影响，所以每个 round 内先循环多次，
    // 再取“本 round 平均值”。外层 benchmarkSamples 再用多个 round 给出 min/avg/max。
    let start = DispatchTime.now().uptimeNanoseconds
    for _ in 0..<iterations {
        operation()
    }
    let elapsed = DispatchTime.now().uptimeNanoseconds - start
    return elapsed / UInt64(iterations)
}

private struct BenchmarkSamples {
    let samples: [UInt64]

    var average: UInt64 {
        samples.reduce(0, +) / UInt64(samples.count)
    }

    var minimum: UInt64 {
        samples.min() ?? 0
    }

    var maximum: UInt64 {
        samples.max() ?? 0
    }

    var summary: String {
        // 打印最小/平均/最大，而不是只打印平均，可以看出当前机器上 benchmark 是否稳定。
        "最小 \(formatNanoseconds(minimum)) / 平均 \(formatNanoseconds(average)) / 最大 \(formatNanoseconds(maximum))"
    }
}

private func benchmarkSamples(
    rounds: Int,
    iterations: Int,
    _ operation: () -> Void
) -> BenchmarkSamples {
    BenchmarkSamples(
        samples: (0..<rounds).map { _ in
            benchmarkAverageNanoseconds(iterations: iterations, operation)
        }
    )
}

private func formatNanoseconds(_ nanoseconds: UInt64) -> String {
    String(format: "%.3f ms", Double(nanoseconds) / 1_000_000)
}

private func formatRatio(_ lhs: UInt64, _ rhs: UInt64) -> String {
    String(format: "%.2f%%", Double(lhs) / Double(rhs) * 100)
}

private func renderIncrementalBenchmarkCanvas(
    counter: Binding<Int>,
    to canvas: Canvas,
    cache: RenderCache? = nil
) {
    // benchmark 里统一通过这个入口生成布局树并渲染，确保“普通路径”和“缓存路径”
    // 使用的是同一个 View 结构，差异只来自是否传入 RenderCache。
    let node = IncrementalRefreshBenchmarkView(counter: counter)._makeLayoutNode()
    Render.render(
        node,
        in: Rect(x: 0, y: 0, w: canvas.width, h: canvas.height),
        to: canvas,
        cache: cache
    )
}

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

@Test func sheetAllowsTabToMoveFocusInsidePresentedContent() {
    var isPresented = true
    var first = ""
    var second = ""
    let app = TerminalApp(width: 24, height: 8) {
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
    let app = TerminalApp(width: 24, height: 8) {
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

@Test func onEventHandlesKeyPressThroughUnifiedDispatcher() {
    var received = false
    let app = TerminalApp(width: 20, height: 2) {
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
    let app = TerminalApp(width: 20, height: 2) {
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

@Test func incrementalRefreshBenchmarkReportsOutputSavings() {
    var counter = 0
    let app = TerminalApp(width: 108, height: 32) {
        IncrementalRefreshBenchmarkView(
            counter: Binding(get: { counter }, set: { counter = $0 })
        )
    }

    let colorSupport = TerminalColorSupport.ansi8
    let firstCanvas = app.render()
    counter += 1
    let secondCanvas = app.render()

    let fullOutput = secondCanvas.positionedOutput(colorSupport: colorSupport)
    let incrementalOutput = secondCanvas.positionedOutput(
        comparedTo: firstCanvas,
        colorSupport: colorSupport
    )
    let changedRows = zip(firstCanvas.grid, secondCanvas.grid).filter(!=).count
    let rounds = 8
    let outputIterations = 1_000
    let frameIterations = 50
    let fullOutputSamples = benchmarkSamples(rounds: rounds, iterations: outputIterations) {
        _ = secondCanvas.positionedOutput(colorSupport: colorSupport)
    }
    let incrementalOutputSamples = benchmarkSamples(rounds: rounds, iterations: outputIterations) {
        _ = secondCanvas.positionedOutput(comparedTo: firstCanvas, colorSupport: colorSupport)
    }

    counter = 0
    let fullFrameSamples = benchmarkSamples(rounds: rounds, iterations: frameIterations) {
        counter += 1
        let canvas = app.render()
        _ = canvas.positionedOutput(colorSupport: colorSupport)
    }
    counter = 0
    var previousCanvas: Canvas? = app.render()
    let incrementalFrameSamples = benchmarkSamples(rounds: rounds, iterations: frameIterations) {
        counter += 1
        let canvas = app.render()
        _ = canvas.positionedOutput(comparedTo: previousCanvas, colorSupport: colorSupport)
        previousCanvas = canvas
    }

    print(
        """
        增量刷新基准测试：
          全量输出字节数：\(fullOutput.utf8.count)
          增量输出字节数：\(incrementalOutput.utf8.count)
          变化行数：\(changedRows) / \(secondCanvas.height)
          输出体积比例：\(String(format: "%.2f%%", Double(incrementalOutput.utf8.count) / Double(fullOutput.utf8.count) * 100))
          输出生成（\(rounds) 轮 × \(outputIterations) 次）：
            全量输出：\(fullOutputSamples.summary)
            增量输出：\(incrementalOutputSamples.summary)
            增量/全量平均比例：\(formatRatio(incrementalOutputSamples.average, fullOutputSamples.average))
          帧生成（\(rounds) 轮 × \(frameIterations) 次）：
            渲染 + 全量输出：\(fullFrameSamples.summary)
            渲染 + 增量输出：\(incrementalFrameSamples.summary)
            增量/全量平均比例：\(formatRatio(incrementalFrameSamples.average, fullFrameSamples.average))
        """
    )

    #expect(changedRows < secondCanvas.height)
    #expect(incrementalOutput.utf8.count < fullOutput.utf8.count)
}

@Test func canvasDoubleBufferBenchmarkReportsFrameSavings() {
    let width = 108
    let height = 32
    let colorSupport = TerminalColorSupport.ansi8
    let rounds = 8
    let iterations = 50
    var counter = 0
    let counterBinding = Binding(get: { counter }, set: { counter = $0 })

    let correctnessPrevious = Canvas(width: width, height: height)
    renderIncrementalBenchmarkCanvas(counter: counterBinding, to: correctnessPrevious)
    counter = 1
    let correctnessCurrent = Canvas(width: width, height: height)
    renderIncrementalBenchmarkCanvas(counter: counterBinding, to: correctnessCurrent)
    let allocatedOutput = correctnessCurrent.positionedOutput(
        comparedTo: correctnessPrevious,
        colorSupport: colorSupport
    )
    counter = 0
    let correctnessBuffer = CanvasDoubleBuffer(width: width, height: height)
    _ = correctnessBuffer.renderOutput(colorSupport: colorSupport) { canvas in
        renderIncrementalBenchmarkCanvas(counter: counterBinding, to: canvas)
    }
    counter = 1
    let doubleBufferedOutput = correctnessBuffer.renderOutput(colorSupport: colorSupport) { canvas in
        renderIncrementalBenchmarkCanvas(counter: counterBinding, to: canvas)
    }

    #expect(doubleBufferedOutput == allocatedOutput)

    counter = 0
    let warmupCanvas = Canvas(width: width, height: height)
    renderIncrementalBenchmarkCanvas(counter: counterBinding, to: warmupCanvas)

    var previousAllocatedCanvas: Canvas? = warmupCanvas
    let allocatedFrameSamples = benchmarkSamples(rounds: rounds, iterations: iterations) {
        counter += 1
        let canvas = Canvas(width: width, height: height)
        renderIncrementalBenchmarkCanvas(counter: counterBinding, to: canvas)
        _ = canvas.positionedOutput(comparedTo: previousAllocatedCanvas, colorSupport: colorSupport)
        previousAllocatedCanvas = canvas
    }

    counter = 0
    let doubleBuffer = CanvasDoubleBuffer(width: width, height: height)
    _ = doubleBuffer.renderOutput(colorSupport: colorSupport) { canvas in
        renderIncrementalBenchmarkCanvas(counter: counterBinding, to: canvas)
    }
    let doubleBufferedFrameSamples = benchmarkSamples(rounds: rounds, iterations: iterations) {
        counter += 1
        _ = doubleBuffer.renderOutput(colorSupport: colorSupport) { canvas in
            renderIncrementalBenchmarkCanvas(counter: counterBinding, to: canvas)
        }
    }

    print(
        """
        Canvas 双缓冲基准测试（\(rounds) 轮 × \(iterations) 次）：
          每帧新建 Canvas + 增量输出：\(allocatedFrameSamples.summary)
          双缓冲复用 Canvas + 增量输出：\(doubleBufferedFrameSamples.summary)
          双缓冲/新建 Canvas 平均比例：\(formatRatio(doubleBufferedFrameSamples.average, allocatedFrameSamples.average))
        """
    )

    #expect(doubleBufferedFrameSamples.average > 0)
    #expect(allocatedFrameSamples.average > 0)
}

@Test func renderCacheBenchmarkReportsReusableLeafSavings() {
    let width = 108
    let height = 32
    let colorSupport = TerminalColorSupport.ansi8
    let rounds = 8
    let iterations = 50
    var counter = 0
    let counterBinding = Binding(get: { counter }, set: { counter = $0 })

    let plainPrevious = Canvas(width: width, height: height)
    renderIncrementalBenchmarkCanvas(counter: counterBinding, to: plainPrevious)
    counter = 1
    let plainCurrent = Canvas(width: width, height: height)
    renderIncrementalBenchmarkCanvas(counter: counterBinding, to: plainCurrent)

    counter = 0
    let cachedPrevious = Canvas(width: width, height: height)
    let correctnessCache = RenderCache()
    renderIncrementalBenchmarkCanvas(counter: counterBinding, to: cachedPrevious, cache: correctnessCache)
    counter = 1
    let cachedCurrent = Canvas(width: width, height: height)
    renderIncrementalBenchmarkCanvas(counter: counterBinding, to: cachedCurrent, cache: correctnessCache)

    #expect(cachedCurrent.grid == plainCurrent.grid)

    counter = 0
    var previousPlainCanvas: Canvas? = nil
    let plainSamples = benchmarkSamples(rounds: rounds, iterations: iterations) {
        counter += 1
        let canvas = Canvas(width: width, height: height)
        renderIncrementalBenchmarkCanvas(counter: counterBinding, to: canvas)
        _ = canvas.positionedOutput(comparedTo: previousPlainCanvas, colorSupport: colorSupport)
        previousPlainCanvas = canvas
    }

    counter = 0
    let renderCache = RenderCache()
    var previousCachedCanvas: Canvas? = nil
    let cachedSamples = benchmarkSamples(rounds: rounds, iterations: iterations) {
        counter += 1
        let canvas = Canvas(width: width, height: height)
        renderIncrementalBenchmarkCanvas(counter: counterBinding, to: canvas, cache: renderCache)
        _ = canvas.positionedOutput(comparedTo: previousCachedCanvas, colorSupport: colorSupport)
        previousCachedCanvas = canvas
    }
    let stats = renderCache.stats

    print(
        """
        RenderCache 可复用叶子节点基准测试（\(rounds) 轮 × \(iterations) 次）：
          普通渲染 + 按行 diff：\(plainSamples.summary)
          缓存渲染 + 按行 diff：\(cachedSamples.summary)
          缓存/普通平均比例：\(formatRatio(cachedSamples.average, plainSamples.average))
          缓存节点统计：
            可绘制节点总数：\(stats.totalRenderableNodes)
            可复用节点：\(stats.reusableNodes)
            已复用节点：\(stats.reusedNodes)
            脏的可复用节点：\(stats.dirtyReusableNodes)
            未缓存节点：\(stats.uncachedNodes)
        """
    )

    #expect(stats.reusableNodes > 0)
    #expect(stats.reusedNodes > 0)
}

@Test func currentFrameRenderingBenchmarkReportsIntegratedPath() {
    let width = 108
    let height = 32
    let colorSupport = TerminalColorSupport.ansi8
    let rounds = 8
    let iterations = 50
    var counter = 0
    let counterBinding = Binding(get: { counter }, set: { counter = $0 })

    let legacyPrevious = Canvas(width: width, height: height)
    renderIncrementalBenchmarkCanvas(counter: counterBinding, to: legacyPrevious)
    counter = 1
    let legacyCurrent = Canvas(width: width, height: height)
    renderIncrementalBenchmarkCanvas(counter: counterBinding, to: legacyCurrent)
    let legacySecondFrameOutput = legacyCurrent.positionedOutput(
        comparedTo: legacyPrevious,
        colorSupport: colorSupport
    )

    counter = 0
    let currentBuffer = CanvasDoubleBuffer(width: width, height: height)
    let currentCache = RenderCache()
    _ = currentBuffer.renderOutput(colorSupport: colorSupport) { canvas in
        renderIncrementalBenchmarkCanvas(counter: counterBinding, to: canvas, cache: currentCache)
    }
    counter = 1
    let currentSecondFrameOutput = currentBuffer.renderOutput(colorSupport: colorSupport) { canvas in
        renderIncrementalBenchmarkCanvas(counter: counterBinding, to: canvas, cache: currentCache)
    }

    #expect(currentSecondFrameOutput == legacySecondFrameOutput)

    counter = 0
    var previousLegacyCanvas: Canvas?
    let legacySamples = benchmarkSamples(rounds: rounds, iterations: iterations) {
        counter += 1
        let canvas = Canvas(width: width, height: height)
        renderIncrementalBenchmarkCanvas(counter: counterBinding, to: canvas)
        _ = canvas.positionedOutput(comparedTo: previousLegacyCanvas, colorSupport: colorSupport)
        previousLegacyCanvas = canvas
    }

    counter = 0
    let integratedBuffer = CanvasDoubleBuffer(width: width, height: height)
    let integratedCache = RenderCache()
    let integratedSamples = benchmarkSamples(rounds: rounds, iterations: iterations) {
        counter += 1
        _ = integratedBuffer.renderOutput(colorSupport: colorSupport) { canvas in
            renderIncrementalBenchmarkCanvas(counter: counterBinding, to: canvas, cache: integratedCache)
        }
    }
    let stats = integratedCache.stats

    print(
        """
        当前帧渲染完整路径基准测试（\(rounds) 轮 × \(iterations) 次）：
          旧路径：新建 Canvas 渲染 + 按行 diff：\(legacySamples.summary)
          当前路径：双缓冲 + RenderCache + 按行 diff：\(integratedSamples.summary)
          当前路径/旧路径平均比例：\(formatRatio(integratedSamples.average, legacySamples.average))
          第二帧输出字节数：\(currentSecondFrameOutput.utf8.count)
          缓存节点统计：
            可绘制节点总数：\(stats.totalRenderableNodes)
            可复用节点：\(stats.reusableNodes)
            已复用节点：\(stats.reusedNodes)
            脏的可复用节点：\(stats.dirtyReusableNodes)
            未缓存节点：\(stats.uncachedNodes)
        """
    )

    #expect(currentSecondFrameOutput.utf8.count > 0)
    #expect(stats.reusedNodes > 0)
}

@Test func frameRenderingPhaseBenchmarkReportsDetailedBreakdown() {
    let width = 108
    let height = 32
    let bounds = Rect(x: 0, y: 0, w: width, h: height)
    let rounds = 8
    let iterations = 50
    var counter = 0
    let counterBinding = Binding(get: { counter }, set: { counter = $0 })

    // 单独测 View body 展开和 LayoutNode 创建。这里不 layout、不 draw，只看
    // result builder 展开和 `_makeLayoutNode()` 本身的成本。
    let buildSamples = benchmarkSamples(rounds: rounds, iterations: iterations) {
        _ = IncrementalRefreshBenchmarkView(counter: counterBinding)._makeLayoutNode()
    }

    // 单独测 layout。复用同一棵 layout tree，可以把 body 展开和节点分配成本排除掉，
    // 更接近“已有节点执行 measure/layout”这一阶段的纯成本。
    let layoutNode = IncrementalRefreshBenchmarkView(counter: counterBinding)._makeLayoutNode()
    let layoutSamples = benchmarkSamples(rounds: rounds, iterations: iterations) {
        layoutNode.layout(in: bounds)
    }

    func drawSamples(cache: RenderCache?) -> BenchmarkSamples {
        // draw 阶段要求节点已经完成 layout。这里每次创建 canvas，是为了避免上一轮
        // cell 内容影响当前 draw；计时从 `Render.drawLaidOut` 开始，只包含绘制遍历。
        BenchmarkSamples(
            samples: (0..<rounds).map { _ in
                var total: UInt64 = 0
                for _ in 0..<iterations {
                    counter += 1
                    let node = IncrementalRefreshBenchmarkView(counter: counterBinding)._makeLayoutNode()
                    node.layout(in: bounds)
                    let canvas = Canvas(width: width, height: height)
                    let start = DispatchTime.now().uptimeNanoseconds
                    Render.drawLaidOut(node, to: canvas, cache: cache)
                    total += DispatchTime.now().uptimeNanoseconds - start
                }
                return total / UInt64(iterations)
            }
        )
    }

    counter = 0
    let plainDrawSamples = drawSamples(cache: nil)

    counter = 0
    // 打开 collectsTimings 后，RenderCache 会把缓存路径内部成本继续拆开统计。
    // 这个模式只用于 benchmark；正式运行默认关闭，避免 DispatchTime 计时开销。
    let timedCache = RenderCache(collectsTimings: true)
    var accumulatedStats = RenderCacheStats()
    var cachedDrawSamples = [UInt64]()
    for _ in 0..<rounds {
        var total: UInt64 = 0
        for _ in 0..<iterations {
            counter += 1
            let node = IncrementalRefreshBenchmarkView(counter: counterBinding)._makeLayoutNode()
            node.layout(in: bounds)
            let canvas = Canvas(width: width, height: height)
            let start = DispatchTime.now().uptimeNanoseconds
            Render.drawLaidOut(node, to: canvas, cache: timedCache)
            total += DispatchTime.now().uptimeNanoseconds - start

            // RenderCache.stats 每帧都会在 beginFrame 时重置，所以需要在本帧 draw 后
            // 立刻累加。最后除以总帧数，得到“平均每帧”的节点数和耗时。
            let stats = timedCache.stats
            accumulatedStats.totalRenderableNodes += stats.totalRenderableNodes
            accumulatedStats.reusableNodes += stats.reusableNodes
            accumulatedStats.reusedNodes += stats.reusedNodes
            accumulatedStats.dirtyReusableNodes += stats.dirtyReusableNodes
            accumulatedStats.uncachedNodes += stats.uncachedNodes
            accumulatedStats.identityNanoseconds += stats.identityNanoseconds
            accumulatedStats.fingerprintNanoseconds += stats.fingerprintNanoseconds
            accumulatedStats.cacheLookupNanoseconds += stats.cacheLookupNanoseconds
            accumulatedStats.pasteNanoseconds += stats.pasteNanoseconds
            accumulatedStats.reusableDrawNanoseconds += stats.reusableDrawNanoseconds
            accumulatedStats.snapshotNanoseconds += stats.snapshotNanoseconds
            accumulatedStats.uncachedDrawNanoseconds += stats.uncachedDrawNanoseconds
        }
        cachedDrawSamples.append(total / UInt64(iterations))
    }
    let cachedSamples = BenchmarkSamples(samples: cachedDrawSamples)
    let frames = UInt64(rounds * iterations)

    func averageStat(_ value: UInt64) -> String {
        formatNanoseconds(value / frames)
    }

    print(
        """
        帧渲染阶段分解基准测试（\(rounds) 轮 × \(iterations) 次）：
          视图 body 展开 + 布局节点创建：\(buildSamples.summary)
          已有布局树测量/布局：\(layoutSamples.summary)
          无缓存 Render 绘制遍历：\(plainDrawSamples.summary)
          带缓存 Render 绘制遍历（含内部计时）：\(cachedSamples.summary)
          缓存绘制/普通绘制平均比例：\(formatRatio(cachedSamples.average, plainDrawSamples.average))
          每帧缓存节点统计：
            可绘制节点总数：\(Double(accumulatedStats.totalRenderableNodes) / Double(frames))
            可复用节点：\(Double(accumulatedStats.reusableNodes) / Double(frames))
            已复用节点：\(Double(accumulatedStats.reusedNodes) / Double(frames))
            脏的可复用节点：\(Double(accumulatedStats.dirtyReusableNodes) / Double(frames))
            未缓存节点：\(Double(accumulatedStats.uncachedNodes) / Double(frames))
          每帧缓存内部耗时：
            身份/类型 key 生成：\(averageStat(accumulatedStats.identityNanoseconds))
            绘制指纹计算：\(averageStat(accumulatedStats.fingerprintNanoseconds))
            缓存查表：\(averageStat(accumulatedStats.cacheLookupNanoseconds))
            贴回复用单元格：\(averageStat(accumulatedStats.pasteNanoseconds))
            脏可复用节点绘制：\(averageStat(accumulatedStats.reusableDrawNanoseconds))
            脏可复用节点快照：\(averageStat(accumulatedStats.snapshotNanoseconds))
            未缓存节点绘制：\(averageStat(accumulatedStats.uncachedDrawNanoseconds))
        """
    )

    #expect(buildSamples.average > 0)
    #expect(layoutSamples.average > 0)
    #expect(plainDrawSamples.average > 0)
    #expect(cachedSamples.average > 0)
    #expect(accumulatedStats.reusedNodes > 0)
}

@Test func currentFrameGenerationBenchmarkReportsStepBreakdown() {
    let width = 108
    let height = 32
    let bounds = Rect(x: 0, y: 0, w: width, h: height)
    let colorSupport = TerminalColorSupport.ansi8
    let rounds = 8
    let iterations = 50
    var counter = 0
    let counterBinding = Binding(get: { counter }, set: { counter = $0 })
    var presented = Canvas(width: width, height: height)
    var drawing = Canvas(width: width, height: height)
    let renderCache = RenderCache(collectsTimings: true)

    // 预热一帧，让 RenderCache 拥有 previous 快照，也让 presented 保存上一帧画面。
    // 这样后面的计时代表稳定状态下的“增量帧”，而不是首帧全量绘制/全量输出。
    _ = drawing.positionedOutput(colorSupport: colorSupport)
    drawing.clean()
    let warmupNode = IncrementalRefreshBenchmarkView(counter: counterBinding)._makeLayoutNode()
    warmupNode.layout(in: bounds)
    Render.drawLaidOut(warmupNode, to: drawing, cache: renderCache)
    _ = drawing.positionedOutput(comparedTo: nil, colorSupport: colorSupport)
    swap(&presented, &drawing)

    var cleanSamples = [UInt64]()
    var buildSamples = [UInt64]()
    var layoutSamples = [UInt64]()
    var drawSamples = [UInt64]()
    var outputSamples = [UInt64]()
    var totalSamples = [UInt64]()
    var outputBytes = [Int]()
    var accumulatedStats = RenderCacheStats()

    for _ in 0..<rounds {
        // 每个 round 都累计 iterations 次完整帧生成，再记录这个 round 的平均值。
        // 这样输出的 min/avg/max 是跨 round 的稳定性，而不是单帧尖峰。
        var cleanTotal: UInt64 = 0
        var buildTotal: UInt64 = 0
        var layoutTotal: UInt64 = 0
        var drawTotal: UInt64 = 0
        var outputTotal: UInt64 = 0
        var totalTotal: UInt64 = 0
        var byteTotal = 0

        for _ in 0..<iterations {
            counter += 1
            let frameStart = DispatchTime.now().uptimeNanoseconds

            // 1. 清空 drawing buffer。双缓冲会复用 Canvas 对象，但每帧仍要把旧 cell
            // 置空，保证本帧没有绘制到的位置不会残留上一帧内容。
            var start = DispatchTime.now().uptimeNanoseconds
            drawing.clean()
            cleanTotal += DispatchTime.now().uptimeNanoseconds - start

            // 2. View body 展开 + LayoutNode 创建。这里代表 SwiftUI 风格声明式 View
            // 每帧重新展开结构时的成本。
            start = DispatchTime.now().uptimeNanoseconds
            let node = IncrementalRefreshBenchmarkView(counter: counterBinding)._makeLayoutNode()
            buildTotal += DispatchTime.now().uptimeNanoseconds - start

            // 3. measure/layout。当前第一版优化不跳过 layout，所以它仍然是完整帧生成
            // 的主要成本之一；这项单独列出来方便后续做 layout 级缓存对比。
            start = DispatchTime.now().uptimeNanoseconds
            node.layout(in: bounds)
            layoutTotal += DispatchTime.now().uptimeNanoseconds - start

            // 4. 已完成 layout 后的 Render 遍历。传入 RenderCache 后，可复用叶子节点
            // 命中时会 paste 上帧 snapshot，脏节点才真正 draw。
            start = DispatchTime.now().uptimeNanoseconds
            Render.drawLaidOut(node, to: drawing, cache: renderCache)
            drawTotal += DispatchTime.now().uptimeNanoseconds - start

            // 记录这一帧缓存内部的细分统计：key、fingerprint、查表、paste、脏节点
            // draw、snapshot 和未缓存 draw。它们之和是 cached Render draw traversal
            // 的一部分，剩余时间主要是遍历、类型判断和函数调用开销。
            let stats = renderCache.stats
            accumulatedStats.totalRenderableNodes += stats.totalRenderableNodes
            accumulatedStats.reusableNodes += stats.reusableNodes
            accumulatedStats.reusedNodes += stats.reusedNodes
            accumulatedStats.dirtyReusableNodes += stats.dirtyReusableNodes
            accumulatedStats.uncachedNodes += stats.uncachedNodes
            accumulatedStats.identityNanoseconds += stats.identityNanoseconds
            accumulatedStats.fingerprintNanoseconds += stats.fingerprintNanoseconds
            accumulatedStats.cacheLookupNanoseconds += stats.cacheLookupNanoseconds
            accumulatedStats.pasteNanoseconds += stats.pasteNanoseconds
            accumulatedStats.reusableDrawNanoseconds += stats.reusableDrawNanoseconds
            accumulatedStats.snapshotNanoseconds += stats.snapshotNanoseconds
            accumulatedStats.uncachedDrawNanoseconds += stats.uncachedDrawNanoseconds

            // 5. 按行 diff 生成终端输出。这里不直接写 stdout，只统计字符串生成成本
            // 和输出字节数；真实交互里还会叠加终端 I/O 成本。
            start = DispatchTime.now().uptimeNanoseconds
            let output = drawing.positionedOutput(comparedTo: presented, colorSupport: colorSupport)
            outputTotal += DispatchTime.now().uptimeNanoseconds - start
            byteTotal += output.utf8.count

            // 当前 drawing 已经代表最新展示画面，交换后下一帧就能拿它做 diff 基准。
            swap(&presented, &drawing)
            totalTotal += DispatchTime.now().uptimeNanoseconds - frameStart
        }

        cleanSamples.append(cleanTotal / UInt64(iterations))
        buildSamples.append(buildTotal / UInt64(iterations))
        layoutSamples.append(layoutTotal / UInt64(iterations))
        drawSamples.append(drawTotal / UInt64(iterations))
        outputSamples.append(outputTotal / UInt64(iterations))
        totalSamples.append(totalTotal / UInt64(iterations))
        outputBytes.append(byteTotal / iterations)
    }

    let frames = UInt64(rounds * iterations)
    func averageStat(_ value: UInt64) -> String {
        // RenderCache 的细项是跨所有帧累加的纳秒数，这里统一换成平均每帧耗时。
        formatNanoseconds(value / frames)
    }
    let averageBytes = outputBytes.reduce(0, +) / outputBytes.count

    let clean = BenchmarkSamples(samples: cleanSamples)
    let build = BenchmarkSamples(samples: buildSamples)
    let layout = BenchmarkSamples(samples: layoutSamples)
    let draw = BenchmarkSamples(samples: drawSamples)
    let output = BenchmarkSamples(samples: outputSamples)
    let total = BenchmarkSamples(samples: totalSamples)

    print(
        """
        当前帧生成步骤分解基准测试（\(rounds) 轮 × \(iterations) 次）：
          完整帧生成总耗时：\(total.summary)
          清空绘制画布：\(clean.summary)
          视图 body 展开 + 布局节点创建：\(build.summary)
          测量/布局：\(layout.summary)
          带缓存 Render 绘制遍历：\(draw.summary)
          按行 diff 输出生成：\(output.summary)
          平均每帧输出字节数：\(averageBytes)
          每帧缓存节点统计：
            可绘制节点总数：\(Double(accumulatedStats.totalRenderableNodes) / Double(frames))
            可复用节点：\(Double(accumulatedStats.reusableNodes) / Double(frames))
            已复用节点：\(Double(accumulatedStats.reusedNodes) / Double(frames))
            脏的可复用节点：\(Double(accumulatedStats.dirtyReusableNodes) / Double(frames))
            未缓存节点：\(Double(accumulatedStats.uncachedNodes) / Double(frames))
          每帧缓存内部耗时：
            身份/类型 key 生成：\(averageStat(accumulatedStats.identityNanoseconds))
            绘制指纹计算：\(averageStat(accumulatedStats.fingerprintNanoseconds))
            缓存查表：\(averageStat(accumulatedStats.cacheLookupNanoseconds))
            贴回复用单元格：\(averageStat(accumulatedStats.pasteNanoseconds))
            脏可复用节点绘制：\(averageStat(accumulatedStats.reusableDrawNanoseconds))
            脏可复用节点快照：\(averageStat(accumulatedStats.snapshotNanoseconds))
            未缓存节点绘制：\(averageStat(accumulatedStats.uncachedDrawNanoseconds))
        """
    )

    #expect(total.average > 0)
    #expect(draw.average > 0)
    #expect(output.average > 0)
    #expect(accumulatedStats.reusedNodes > 0)
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

@Test func unmanagedScrollViewReceivesArrowKeysBubbledFromFocusedTextField() {
    let text = State(wrappedValue: "")
    let app = TerminalApp(width: 5, height: 3) {
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
    let app = TerminalApp(width: 5, height: 3) {
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
    let app = TerminalApp(width: 5, height: 3) {
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
    let app = TerminalApp(width: 9, height: 6) {
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
    let app = TerminalApp(width: 18, height: 8) {
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
    let app = TerminalApp(width: 54, height: 14) {
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
    let app = TerminalApp(width: 5, height: 1) {
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

@Test func accentColorDrivesFocusedBorderAndTextFieldCursor() {
    let borderedValue = State(wrappedValue: "A")
    let bordered = TerminalApp(width: 5, height: 3) {
        TextField("Value", text: borderedValue.projectedValue)
            .bordered(.gray)
            .accentColor(.brightMagenta)
    }
    #expect(bordered.render().grid[0][0].style.foregroundColor == .brightMagenta)

    let cursorValue = State(wrappedValue: "")
    let cursor = TerminalApp(width: 6, height: 1) {
        TextField("Value", text: cursorValue.projectedValue)
            .accentColor(.brightGreen)
    }
    let focused = cursor.render()
    #expect(focused.grid[0][0].char == "▏")
    #expect(focused.grid[0][0].style.foregroundColor == .brightGreen)
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

    #expect(String(placeholder.grid[0].map(\.char)) == "▏Nam")
    #expect(placeholder.grid[0][0].style.foregroundColor == .brightCyan)
    #expect(placeholder.grid[0][0].style.backgroundColor == .black)
    #expect(placeholder.grid[0][1].style.foregroundColor == .gray)
    #expect(placeholder.grid[0][1].style.backgroundColor == .black)

    let long = State(wrappedValue: "ABCDE")
    let scrollingApp = TerminalApp(width: 3, height: 1) {
        TextField("值", text: long.projectedValue)
    }
    #expect(String(scrollingApp.render().grid[0].map(\.char)) == "DE▏")
}

@Test func textFieldShowsInsertionCursorAfterTheLastCharacter() {
    let value = State(wrappedValue: "Alice")
    let app = TerminalApp(width: 8, height: 1) {
        TextField("姓名", text: value.projectedValue)
    }

    let canvas = app.render()

    #expect(String(canvas.grid[0].map(\.char)) == "Alice▏  ")
}

@Test func textFieldUsesAColoredInsertionCursorToShowFocus() {
    let first = State(wrappedValue: "A")
    let second = State(wrappedValue: "B")
    let app = TerminalApp(width: 4, height: 2) {
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
    let app = TerminalApp(width: 34, height: 3) {
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
