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
public protocol ImageStreamerInstrumentation: Sendable, Actor {
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
    
    /// Throttling logic
    private var needsBroadcast = false
    
    public init() {
        // Start a throttling loop to prevent excessive UI updates
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100)) // 10Hz throttle
                guard let self else { return }
                await self.flushStats()
            }
        }
    }
    
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
    public var statsStream: AsyncStream<ImageStreamerStats> {
        AsyncStream { continuation in
            let id = UUID()
            
            // Emit the current stats immediately
            continuation.yield(self.currentStats)
            
            // Store the continuation so we can yield future updates
            self.statsContinuations[id] = continuation
            
            // Clean up when the stream is terminated
            continuation.onTermination = { @Sendable _ in
                Task { await self.removeStatsContinuation(id: id) }
            }
        }
    }
    
    private func removeStatsContinuation(id: UUID) {
        statsContinuations.removeValue(forKey: id)
    }
    
    /// Broadcasts the current stats to all active observers if pending updates exist
    private func flushStats() {
        guard needsBroadcast else { return }
        
        let stats = currentStats
        for continuation in statsContinuations.values {
            continuation.yield(stats)
        }
        
        needsBroadcast = false
    }
    
    public func notifyCacheHit() {
        cacheHits += 1
        needsBroadcast = true
    }
    
    public func notifyNetworkRequest() {
        networkRequests += 1
        needsBroadcast = true
    }
    
    public func notifyCoalescedRequest() {
        coalescedRequests += 1
        needsBroadcast = true
    }
    
    public func notifyCancelledTask() {
        cancelledTasks += 1
        needsBroadcast = true
    }

    public func reset() {
        cacheHits = 0
        networkRequests = 0
        coalescedRequests = 0
        cancelledTasks = 0
        needsBroadcast = true
        // Force flush immediately on reset for responsiveness
        flushStats()
    }
}
