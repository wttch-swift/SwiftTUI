import Foundation
import TerminalUIRender
import TerminalUIView

/// Runtime metrics for the most recently completed terminal frame.
public struct TerminalDebugMetrics: Equatable, Sendable {
    public var frameCount: UInt64
    public var renderNanoseconds: UInt64
    public var outputNanoseconds: UInt64
    public var totalNanoseconds: UInt64
    public var averageTotalNanoseconds: UInt64
    public var outputBytes: Int
    public var cache: TerminalRenderCacheMetrics

    public static let empty = TerminalDebugMetrics(
        frameCount: 0,
        renderNanoseconds: 0,
        outputNanoseconds: 0,
        totalNanoseconds: 0,
        averageTotalNanoseconds: 0,
        outputBytes: 0,
        cache: .empty
    )

    public var framesPerSecond: Double {
        guard totalNanoseconds > 0 else { return 0 }
        return 1_000_000_000 / Double(totalNanoseconds)
    }

    public var averageFramesPerSecond: Double {
        guard averageTotalNanoseconds > 0 else { return 0 }
        return 1_000_000_000 / Double(averageTotalNanoseconds)
    }
}

/// RenderCache counters and timings captured for a completed frame.
public struct TerminalRenderCacheMetrics: Equatable, Sendable {
    public var totalRenderableNodes: Int
    public var reusableNodes: Int
    public var reusedNodes: Int
    public var dirtyReusableNodes: Int
    public var uncachedNodes: Int
    public var identityNanoseconds: UInt64
    public var fingerprintNanoseconds: UInt64
    public var cacheLookupNanoseconds: UInt64
    public var pasteNanoseconds: UInt64
    public var reusableDrawNanoseconds: UInt64
    public var snapshotNanoseconds: UInt64
    public var uncachedDrawNanoseconds: UInt64

    public static let empty = TerminalRenderCacheMetrics(
        totalRenderableNodes: 0,
        reusableNodes: 0,
        reusedNodes: 0,
        dirtyReusableNodes: 0,
        uncachedNodes: 0,
        identityNanoseconds: 0,
        fingerprintNanoseconds: 0,
        cacheLookupNanoseconds: 0,
        pasteNanoseconds: 0,
        reusableDrawNanoseconds: 0,
        snapshotNanoseconds: 0,
        uncachedDrawNanoseconds: 0
    )

    fileprivate init(_ stats: RenderCacheStats) {
        self.totalRenderableNodes = stats.totalRenderableNodes
        self.reusableNodes = stats.reusableNodes
        self.reusedNodes = stats.reusedNodes
        self.dirtyReusableNodes = stats.dirtyReusableNodes
        self.uncachedNodes = stats.uncachedNodes
        self.identityNanoseconds = stats.identityNanoseconds
        self.fingerprintNanoseconds = stats.fingerprintNanoseconds
        self.cacheLookupNanoseconds = stats.cacheLookupNanoseconds
        self.pasteNanoseconds = stats.pasteNanoseconds
        self.reusableDrawNanoseconds = stats.reusableDrawNanoseconds
        self.snapshotNanoseconds = stats.snapshotNanoseconds
        self.uncachedDrawNanoseconds = stats.uncachedDrawNanoseconds
    }

    private init(
        totalRenderableNodes: Int,
        reusableNodes: Int,
        reusedNodes: Int,
        dirtyReusableNodes: Int,
        uncachedNodes: Int,
        identityNanoseconds: UInt64,
        fingerprintNanoseconds: UInt64,
        cacheLookupNanoseconds: UInt64,
        pasteNanoseconds: UInt64,
        reusableDrawNanoseconds: UInt64,
        snapshotNanoseconds: UInt64,
        uncachedDrawNanoseconds: UInt64
    ) {
        self.totalRenderableNodes = totalRenderableNodes
        self.reusableNodes = reusableNodes
        self.reusedNodes = reusedNodes
        self.dirtyReusableNodes = dirtyReusableNodes
        self.uncachedNodes = uncachedNodes
        self.identityNanoseconds = identityNanoseconds
        self.fingerprintNanoseconds = fingerprintNanoseconds
        self.cacheLookupNanoseconds = cacheLookupNanoseconds
        self.pasteNanoseconds = pasteNanoseconds
        self.reusableDrawNanoseconds = reusableDrawNanoseconds
        self.snapshotNanoseconds = snapshotNanoseconds
        self.uncachedDrawNanoseconds = uncachedDrawNanoseconds
    }
}

/// Reads the latest completed frame metrics without requesting another render.
public struct DebugMetricsReader<Content: View>: View {
    private let content: (TerminalDebugMetrics) -> Content

    public init(@ViewBuilder content: @escaping (TerminalDebugMetrics) -> Content) {
        TerminalDebugRuntime.enableCollection()
        self.content = content
    }

    public var body: Content {
        content(TerminalDebugRuntime.snapshot)
    }
}

package enum TerminalDebugRuntime {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var isEnabled = false
    nonisolated(unsafe) private static var current = TerminalDebugMetrics.empty
    nonisolated(unsafe) private static var accumulatedTotalNanoseconds: UInt64 = 0

    package static var collectsMetrics: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isEnabled
    }

    public static var snapshot: TerminalDebugMetrics {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    package static func enableCollection() {
        lock.lock()
        isEnabled = true
        lock.unlock()
    }

    package static func recordFrame(
        renderNanoseconds: UInt64,
        outputNanoseconds: UInt64,
        totalNanoseconds: UInt64,
        outputBytes: Int,
        cacheStats: RenderCacheStats
    ) {
        lock.lock()
        defer { lock.unlock() }
        guard isEnabled else { return }

        let frameCount = current.frameCount + 1
        accumulatedTotalNanoseconds &+= totalNanoseconds
        current = TerminalDebugMetrics(
            frameCount: frameCount,
            renderNanoseconds: renderNanoseconds,
            outputNanoseconds: outputNanoseconds,
            totalNanoseconds: totalNanoseconds,
            averageTotalNanoseconds: accumulatedTotalNanoseconds / frameCount,
            outputBytes: outputBytes,
            cache: TerminalRenderCacheMetrics(cacheStats)
        )
    }
}
