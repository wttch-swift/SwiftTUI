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

enum TestTab: Hashable {
    case home
    case settings
}

struct IncrementalRefreshBenchmarkView: View {
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

struct RebuiltScrollBenchmarkView: View {
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

struct RebuiltFocusedScrollBenchmarkView: View {
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

func benchmarkAverageNanoseconds(iterations: Int, _ operation: () -> Void) -> UInt64 {
    // 单次渲染很容易受到调度和计时器抖动影响，所以每个 round 内先循环多次，
    // 再取“本 round 平均值”。外层 benchmarkSamples 再用多个 round 给出 min/avg/max。
    let start = DispatchTime.now().uptimeNanoseconds
    for _ in 0..<iterations {
        operation()
    }
    let elapsed = DispatchTime.now().uptimeNanoseconds - start
    return elapsed / UInt64(iterations)
}

struct BenchmarkSamples {
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

func benchmarkSamples(
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

func formatNanoseconds(_ nanoseconds: UInt64) -> String {
    String(format: "%.3f ms", Double(nanoseconds) / 1_000_000)
}

func formatRatio(_ lhs: UInt64, _ rhs: UInt64) -> String {
    String(format: "%.2f%%", Double(lhs) / Double(rhs) * 100)
}

func renderIncrementalBenchmarkCanvas(
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
