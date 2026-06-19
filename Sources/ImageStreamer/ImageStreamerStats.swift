import Foundation

// MARK: - Stats Model

/// Snapshot of current streamer statistics
public struct ImageStreamerStats: Sendable, Equatable {
    public let cacheHits: Int
    public let networkRequests: Int
    public let coalescedRequests: Int
    public let cancelledTasks: Int

    public static let zero = ImageStreamerStats(cacheHits: 0, networkRequests: 0, coalescedRequests: 0, cancelledTasks: 0)

    public init(cacheHits: Int, networkRequests: Int, coalescedRequests: Int, cancelledTasks: Int = 0) {
        self.cacheHits = cacheHits
        self.networkRequests = networkRequests
        self.coalescedRequests = coalescedRequests
        self.cancelledTasks = cancelledTasks
    }
}

// MARK: - Instrumentation Protocol

/// Protocol defining the interface for collecting ImageStreamer statistics.
public protocol ImageStreamerInstrumentation: Actor {
    /// Notifies that a cache hit occurred.
    func notifyCacheHit()
    /// Notifies that a network request was started.
    func notifyNetworkRequest()
    /// Notifies that a request was coalesced with an existing task.
    func notifyCoalescedRequest()
    /// Notifies that a task was cancelled, saving network resources.
    func notifyCancelledTask()
    
    /// A stream of statistics updates.
    var statsStream: AsyncStream<ImageStreamerStats> { get }
    
    /// Resets the statistics to zero.
    func reset()
}

// MARK: - Default Implementation

/// A standard implementation of `ImageStreamerInstrumentation` that tracks stats in memory
/// and broadcasts updates via an AsyncStream.
public actor StandardImageStreamerInstrumentation: ImageStreamerInstrumentation {
    
    private var cacheHits = 0
    private var networkRequests = 0
    private var coalescedRequests = 0
    private var cancelledTasks = 0
    
    /// Active continuations for stats observers
    private var statsContinuations: [UUID: AsyncStream<ImageStreamerStats>.Continuation] = [:]

    /// Whether a throttled broadcast is already scheduled. Updates within the throttle
    /// window coalesce into the single pending flush.
    private var flushScheduled = false

    public init() {}

    public var currentStats: ImageStreamerStats {
        ImageStreamerStats(
            cacheHits: cacheHits,
            networkRequests: networkRequests,
            coalescedRequests: coalescedRequests,
            cancelledTasks: cancelledTasks
        )
    }

    /// Returns an `AsyncStream` that emits stats updates whenever they change.
    /// The stream automatically terminates when the consuming task is cancelled.
    /// Observers only care about the latest snapshot, so older buffered values are dropped.
    public var statsStream: AsyncStream<ImageStreamerStats> {
        let (stream, continuation) = AsyncStream.makeStream(
            of: ImageStreamerStats.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        let id = UUID()

        // Emit the current stats immediately
        continuation.yield(currentStats)

        // Store the continuation so we can yield future updates
        statsContinuations[id] = continuation

        // Clean up when the stream is terminated
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeStatsContinuation(id: id) }
        }

        return stream
    }

    private func removeStatsContinuation(id: UUID) {
        statsContinuations.removeValue(forKey: id)
    }

    /// Schedules a throttled broadcast (at most one in flight) to prevent excessive UI updates.
    private func scheduleFlush() {
        guard !flushScheduled else { return }
        flushScheduled = true

        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(100)) // 10Hz throttle
            await self?.performScheduledFlush()
        }
    }

    private func performScheduledFlush() {
        flushScheduled = false
        flushStats()
    }

    /// Broadcasts the current stats to all active observers
    private func flushStats() {
        let stats = currentStats
        for continuation in statsContinuations.values {
            continuation.yield(stats)
        }
    }

    public func notifyCacheHit() {
        cacheHits += 1
        scheduleFlush()
    }

    public func notifyNetworkRequest() {
        networkRequests += 1
        scheduleFlush()
    }

    public func notifyCoalescedRequest() {
        coalescedRequests += 1
        scheduleFlush()
    }

    public func notifyCancelledTask() {
        cancelledTasks += 1
        scheduleFlush()
    }

    public func reset() {
        cacheHits = 0
        networkRequests = 0
        coalescedRequests = 0
        cancelledTasks = 0
        // Flush immediately on reset for responsiveness
        flushStats()
    }
}
