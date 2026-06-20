import ImageStreamer
import Foundation

// MARK: - Request Gate

/// An async gate that suspends callers until the test explicitly opens it.
///
/// Used to make coalescing deterministic: requests block inside the fetcher until
/// the test has verified that all expected waiters joined, then the gate is opened.
actor RequestGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    /// Suspends until `open()` is called. Returns immediately if already open.
    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    /// Releases all current and future waiters.
    func open() {
        isOpen = true
        for waiter in waiters {
            waiter.resume()
        }
        waiters.removeAll()
    }
}

// MARK: - Gated Mock Fetcher

/// A mock fetcher whose requests block on a `RequestGate` until the test releases them.
///
/// Unlike a fixed `delay`, this guarantees the primary request is still in flight while
/// secondary requests join it, so coalescing assertions don't depend on scheduler timing.
struct GatedMockFetcher: ImageFetching {
    let result: Result<(Data, URLResponse), Error>
    let gate: RequestGate
    let requestTracker: RequestTracker?

    func data(from url: URL) async throws -> (Data, URLResponse) {
        await requestTracker?.recordRequest(for: url)

        await gate.wait()

        switch result {
        case .success(let tuple):
            return tuple
        case .failure(let error):
            throw error
        }
    }
}
