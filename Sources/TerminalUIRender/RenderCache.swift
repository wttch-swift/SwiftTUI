import Foundation
import TerminalUICore
import TerminalUIFoundation
import TerminalUILayout
import TerminalUIView

/// 一帧渲染缓存的统计信息。
///
/// 这些数字只用于 benchmark 和调试，不参与渲染决策。节点计数帮助确认当前
/// 画面里有多少可复用节点真正命中；纳秒字段则把缓存路径拆成更细的成本：
/// 生成身份 key、计算 fingerprint、查表、paste 旧快照、重画脏节点和 snapshot。
package struct RenderCacheStats: Equatable {
    package var totalRenderableNodes = 0
    package var reusableNodes = 0
    package var reusedNodes = 0
    package var dirtyReusableNodes = 0
    package var uncachedNodes = 0
    package var identityNanoseconds: UInt64 = 0
    package var fingerprintNanoseconds: UInt64 = 0
    package var cacheLookupNanoseconds: UInt64 = 0
    package var pasteNanoseconds: UInt64 = 0
    package var reusableDrawNanoseconds: UInt64 = 0
    package var snapshotNanoseconds: UInt64 = 0
    package var uncachedDrawNanoseconds: UInt64 = 0
}

package final class RenderCache {
    /// 缓存身份由“布局树路径 + 节点类型”组成。
    ///
    /// 第一版先不暴露 View.id，也不要求所有 View 都有稳定业务 id；同一棵
    /// result builder 展开的树里，结构路径足够表达“这是上帧同位置同类型节点”。
    /// 如果未来加入显式 id，可以把 id 接到这里，而不需要改绘制主流程。
    package struct Key: Hashable {
        var path: [Int]
        var typeName: String
    }

    /// 一个可复用节点上一帧绘制后的快照。
    ///
    /// fingerprint 表示影响绘制结果的输入；frame 表示绘制位置和尺寸；cells 是
    /// 已经画好的终端 cell。三者都匹配时，本帧可以直接 paste cells，跳过 draw。
    package struct Entry {
        var fingerprint: Int
        var frame: Rect
        var cells: [[_Cell]]
    }

    package var previous: [Key: Entry] = [:]
    package var current: [Key: Entry] = [:]
    package var stats = RenderCacheStats()
    package let collectsTimings: Bool

    package init(collectsTimings: Bool = false) {
        self.collectsTimings = collectsTimings
    }

    /// 开始一帧：清空本帧产物，并重置统计。
    ///
    /// `previous` 会保留上一帧缓存，用于本帧查表；`current` 重新收集本帧仍然
    /// 存活的节点，避免已经从树上消失的节点继续占用缓存。
    package func beginFrame() {
        current.removeAll(keepingCapacity: true)
        stats = RenderCacheStats()
    }

    /// 结束一帧：把本帧仍然有效的缓存变成下一帧的 previous。
    package func endFrame() {
        previous = current
    }

    /// 清空所有缓存。终端尺寸变化、渲染根切换等场景可以直接丢弃旧快照。
    package func reset() {
        previous.removeAll(keepingCapacity: true)
        current.removeAll(keepingCapacity: true)
        stats = RenderCacheStats()
    }

    /// 只在 benchmark 需要时记录某段缓存逻辑的耗时。
    ///
    /// 普通渲染路径默认 `collectsTimings == false`，这里会直接执行闭包，避免
    /// 每一帧都为 `DispatchTime.now()` 付出额外成本。
    package func measure<T>(
        _ keyPath: WritableKeyPath<RenderCacheStats, UInt64>,
        _ body: () -> T
    ) -> T {
        guard collectsTimings else { return body() }
        let start = DispatchTime.now().uptimeNanoseconds
        let result = body()
        stats[keyPath: keyPath] += DispatchTime.now().uptimeNanoseconds - start
        return result
    }
}
