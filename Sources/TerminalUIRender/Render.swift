/// 布局树的渲染协调器。
///
/// 渲染分为两个阶段：先从根节点向下分配 frame，再深度优先遍历节点执行绘制。
/// 环境节点在遍历途中派生新的 `EnvironmentValues`，并只影响其后代。
package enum Render {
    /// 在指定边界内布局并绘制整棵节点树。
    /// - Parameters:
    ///   - root: 已由 View 展开得到的布局树根节点。
    ///   - bounds: 根节点可使用的最终画布区域。
    ///   - canvas: 接收字符单元格的目标画布。
    package static func render(_ root: any _Layoutable, in bounds: Rect, to canvas: Canvas) {
        render(root, in: bounds, to: canvas, cache: nil)
    }

    /// 在指定边界内布局并绘制整棵节点树，可选使用 RenderCache 复用安全叶子快照。
    ///
    /// 这里仍然每帧执行 layout。当前优化只减少 draw 阶段的大面积重复写 cell；
    /// layout 是否可以进一步跳过，需要更强的布局依赖追踪，暂时不混进第一版。
    package static func render(
        _ root: any _Layoutable,
        in bounds: Rect,
        to canvas: Canvas,
        cache: RenderCache?
    ) {
        root.layout(in: bounds)
        drawLaidOut(root, to: canvas, cache: cache)
    }

    /// 绘制一棵已经完成 layout 的节点树。主要用于测试和分阶段性能统计。
    package static func drawLaidOut(
        _ root: any _Layoutable,
        to canvas: Canvas,
        cache: RenderCache?
    ) {
        cache?.beginFrame()
        var path: [Int] = []
        draw(root, to: canvas, environment: EnvironmentValues(), path: &path, cache: cache)
        cache?.endFrame()
    }

    /// 深度优先绘制节点，并沿当前分支传递解析后的环境值。
    private static func draw(
        _ node: any _Layoutable,
        to canvas: Canvas,
        environment: EnvironmentValues,
        path: inout [Int],
        cache: RenderCache?
    ) {
        // 环境修改必须先于当前节点绘制生效，并继续传给所有子节点。
        let resolved = (node as? any _EnvironmentLayoutNode)?.applyingEnvironment(to: environment)
            ?? environment

        // 将“节点自身 + 后代”作为一个绘制作用域供裁剪节点整体包裹。
        // 若只裁剪节点自身，ScrollView 的子内容仍会泄漏到视口之外。
        if let clipping = node as? _ClippingLayoutNode {
            // Canvas 会把这里的区域与所有祖先裁剪区继续求交。
            // The clip closure cannot capture an inout argument. Copying the
            // short path only at a clipping boundary is still far cheaper than
            // allocating `path + [index]` for every node in the tree.
            var clippedPath = path
            canvas.withClip(clipping.clipRect) {
                drawContents(
                    node,
                    to: canvas,
                    environment: resolved,
                    path: &clippedPath,
                    cache: cache
                )
            }
        } else {
            drawContents(node, to: canvas, environment: resolved, path: &path, cache: cache)
        }
    }

    private static func drawContents(
        _ node: any _Layoutable,
        to canvas: Canvas,
        environment: EnvironmentValues,
        path: inout [Int],
        cache: RenderCache?
    ) {
        // 零尺寸节点不应在 frame 起点写入字符，否则会覆盖相邻边框。
        if let renderable = node as? any _RenderableLayoutNode,
           renderable.frame.w > 0,
           renderable.frame.h > 0,
           canvas.intersectsCurrentClip(renderable.frame) {
            drawRenderable(renderable, to: canvas, environment: environment, path: path, cache: cache)
        }
        // 递归绘制子节点。ContainerLayoutable 负责暴露 children。
        if let container = node as? any _ContainerLayoutable {
            for (index, child) in container.children.enumerated() {
                path.append(index)
                draw(
                    child,
                    to: canvas,
                    environment: environment,
                    path: &path,
                    cache: cache
                )
                path.removeLast()
            }
        }
    }

    private static func drawRenderable(
        _ renderable: any _RenderableLayoutNode,
        to canvas: Canvas,
        environment: EnvironmentValues,
        path: [Int],
        cache: RenderCache?
    ) {
        guard let cache else {
            renderable.draw(to: canvas, environment: environment)
            return
        }

        cache.stats.totalRenderableNodes += 1
        // 只有显式声明“绘制结果可由 fingerprint 完整描述”的节点才进入缓存。
        // 其它节点可能依赖外部副作用、子树绘制顺序或暂未纳入 fingerprint 的状态，
        // 保守地走普通 draw，避免为了性能破坏画面正确性。
        guard let reusable = renderable as? any _RenderReusableLayoutNode else {
            cache.stats.uncachedNodes += 1
            cache.measure(\.uncachedDrawNanoseconds) {
                renderable.draw(to: canvas, environment: environment)
            }
            return
        }

        cache.stats.reusableNodes += 1
        // 身份 key 表示“同一棵布局树里同路径同类型的节点”。fingerprint 表示这个
        // 节点本帧会画成什么样。两者分开统计，方便确认缓存判断本身是否变成瓶颈。
        let key = cache.measure(\.identityNanoseconds) {
            RenderCache.Key(path: path, typeID: ObjectIdentifier(type(of: renderable)))
        }
        let fingerprint = cache.measure(\.fingerprintNanoseconds) {
            reusable.renderFingerprint(environment: environment)
        }
        let previous = cache.measure(\.cacheLookupNanoseconds) {
            cache.previous[key]
        }
        if let previous,
           previous.fingerprint == fingerprint,
           previous.frame == renderable.frame {
            // 命中条件要求 fingerprint 和 frame 都一致。frame 变化时即使内容相同，
            // 也必须重新 snapshot，因为缓存的 cells 对应的是旧矩形区域。
            cache.measure(\.pasteNanoseconds) {
                canvas.paste(previous.cells, in: renderable.frame)
            }
            cache.current[key] = previous
            cache.stats.reusedNodes += 1
            return
        }

        cache.stats.dirtyReusableNodes += 1
        // 没命中的可复用节点仍然正常 draw。draw 完后立即截取它的 frame，
        // 下一帧只要输入和 frame 不变，就可以直接 paste 这个快照。
        cache.measure(\.reusableDrawNanoseconds) {
            renderable.draw(to: canvas, environment: environment)
        }
        let cells = cache.measure(\.snapshotNanoseconds) {
            canvas.snapshot(in: renderable.frame)
        }
        cache.current[key] = RenderCache.Entry(
            fingerprint: fingerprint,
            frame: renderable.frame,
            cells: cells
        )
    }
}
