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

@Test func incrementalRefreshBenchmarkReportsOutputSavings() {
    var counter = 0
    let app = _TerminalAppHost(width: 108, height: 32) {
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

