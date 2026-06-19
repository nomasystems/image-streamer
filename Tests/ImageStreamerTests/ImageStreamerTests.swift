import Testing
import Foundation
@testable import ImageStreamer

// MARK: - ImageStreamer Core Tests

@Suite("ImageStreamer Core Functionality")
struct ImageStreamerCoreTests {

    @Test("Loads and returns a valid image")
    func loadsValidImage() async throws {
        let url = URL(string: "https://example.com/test.png")!
        let imageData = MockImageData.validPNGData()
        let response = MockImageData.successResponse(for: url)

        let (streamer, _) = makeStreamer(result: .success((imageData, response)))

        let image = try await streamer.image(for: url)

        #expect(extractCGImage(from: image) != nil)
    }

    @Test("Loads and downsamples image to specified point size")
    func loadsDownsampledImage() async throws {
        let url = URL(string: "https://example.com/large.png")!
        let sourceDimension = 512
        let imageData = MockImageData.largePNGData(dimension: sourceDimension)
        let response = MockImageData.successResponse(for: url)

        let (streamer, _) = makeStreamer(result: .success((imageData, response)))

        let image = try await streamer.image(for: url, pointSize: CGSize(width: 100, height: 100))

        // The downsample path must actually shrink the 512x512 source - a result still
        // at the source size would mean downsampling silently did nothing.
        let cgImage = try #require(extractCGImage(from: image))
        #expect(
            max(cgImage.width, cgImage.height) < sourceDimension,
            "Downsampled image should be smaller than the \(sourceDimension)px source, got \(cgImage.width)x\(cgImage.height)"
        )
        #expect(cgImage.width > 0 && cgImage.height > 0)
    }

    @Test("Throws invalidImageData error for corrupt data")
    func throwsErrorForInvalidImageData() async throws {
        let url = URL(string: "https://example.com/test.png")!
        let invalidData = MockImageData.invalidData()
        let response = MockImageData.successResponse(for: url)

        let (streamer, _) = makeStreamer(result: .success((invalidData, response)))

        await #expect(throws: ImageStreamerError.invalidImageData) {
            _ = try await streamer.image(for: url)
        }
    }

    @Test("Throws URLError for non-2xx HTTP status codes")
    func throwsErrorForBadServerResponse() async throws {
        let url = URL(string: "https://example.com/test.png")!
        let imageData = MockImageData.validPNGData()
        let response = MockImageData.successResponse(for: url, statusCode: 404)

        let (streamer, _) = makeStreamer(result: .success((imageData, response)))

        let error = await #expect(throws: URLError.self) {
            _ = try await streamer.image(for: url)
        }
        #expect(error?.code == .badServerResponse)
    }

    @Test("Propagates network errors from the session")
    func propagatesNetworkErrors() async throws {
        let url = URL(string: "https://example.com/test.png")!
        let networkError = URLError(.notConnectedToInternet)

        let (streamer, _) = makeStreamer(result: .failure(networkError))

        let error = await #expect(throws: URLError.self) {
            _ = try await streamer.image(for: url)
        }
        #expect(error?.code == .notConnectedToInternet)
    }
}

// MARK: - Caching Tests

@Suite("ImageStreamer Caching")
struct ImageStreamerCachingTests {

    @Test("Returns cached image without additional network request")
    func returnsCachedImageWithoutNetworkRequest() async throws {
        let url = URL(string: "https://example.com/cached.png")!
        let imageData = MockImageData.validPNGData()
        let response = MockImageData.successResponse(for: url)

        let requestTracker = RequestTracker()
        let (streamer, _) = makeStreamer(
            result: .success((imageData, response)),
            requestTracker: requestTracker
        )

        // First request - should hit network
        _ = try await streamer.image(for: url)

        let firstRequestCount = await requestTracker.requestCount(for: url)
        #expect(firstRequestCount == 1)

        // Second request - should return from cache
        _ = try await streamer.image(for: url)

        let secondRequestCount = await requestTracker.requestCount(for: url)
        #expect(secondRequestCount == 1, "Should not make additional network request for cached image")
    }


    @Test("Does not cache image when fetch fails")
    func doesNotCacheOnFailure() async throws {
        let url = URL(string: "https://example.com/failing.png")!
        let invalidData = MockImageData.invalidData()
        let response = MockImageData.successResponse(for: url)

        let requestTracker = RequestTracker()
        let (streamer, cache) = makeStreamer(
            result: .success((invalidData, response)),
            requestTracker: requestTracker
        )

        let cacheKey = ImageCacheKey(url: url, pointSize: nil)

        // First attempt - should fail
        await #expect(throws: ImageStreamerError.invalidImageData) {
            _ = try await streamer.image(for: url)
        }

        // Verify nothing was cached
        #expect(cache.object(forKey: cacheKey) == nil)

        let firstRequestCount = await requestTracker.requestCount(for: url)
        #expect(firstRequestCount == 1)

        // Second attempt - should still hit network since nothing was cached
        await #expect(throws: ImageStreamerError.invalidImageData) {
            _ = try await streamer.image(for: url)
        }

        let secondRequestCount = await requestTracker.requestCount(for: url)
        #expect(secondRequestCount == 2, "Failed images should not be cached, so second request should hit network")
    }

    @Test("Caches different point sizes separately")
    func cachesDifferentSizesSeparately() async throws {
        let url = URL(string: "https://example.com/responsive.png")!
        let imageData = MockImageData.validPNGData()
        let response = MockImageData.successResponse(for: url)

        let requestTracker = RequestTracker()
        let (streamer, cache) = makeStreamer(
            result: .success((imageData, response)),
            requestTracker: requestTracker
        )

        let originalKey = ImageCacheKey(url: url, pointSize: nil)
        let thumbnailKey = ImageCacheKey(url: url, pointSize: CGSize(width: 100, height: 100))

        // Fetch original size
        _ = try await streamer.image(for: url)
        #expect(cache.object(forKey: originalKey) != nil, "Original size should be cached")
        #expect(cache.object(forKey: thumbnailKey) == nil, "Thumbnail should not be cached yet")

        // Fetch thumbnail size
        _ = try await streamer.image(for: url, pointSize: CGSize(width: 100, height: 100))
        #expect(cache.object(forKey: originalKey) != nil, "Original size should still be cached")
        #expect(cache.object(forKey: thumbnailKey) != nil, "Thumbnail should now be cached")

        // Verify 2 network requests were made (one per size)
        let requestCount = await requestTracker.requestCount(for: url)
        #expect(requestCount == 2, "Should make separate network requests for different sizes")
    }

    @Test("Uses separate cache entries for different URLs")
    func usesSeparateCacheEntriesForDifferentURLs() async throws {
        let url1 = URL(string: "https://example.com/image1.png")!
        let url2 = URL(string: "https://example.com/image2.png")!
        let imageData = MockImageData.validPNGData()

        let responses: [URL: Result<(Data, URLResponse), Error>] = [
            url1: .success((imageData, MockImageData.successResponse(for: url1))),
            url2: .success((imageData, MockImageData.successResponse(for: url2)))
        ]

        let (streamer, cache) = makeStreamer(responses: responses)

        let key1 = ImageCacheKey(url: url1, pointSize: nil)
        let key2 = ImageCacheKey(url: url2, pointSize: nil)

        // Fetch first image
        _ = try await streamer.image(for: url1)
        #expect(cache.object(forKey: key1) != nil)
        #expect(cache.object(forKey: key2) == nil)

        // Fetch second image
        _ = try await streamer.image(for: url2)
        #expect(cache.object(forKey: key1) != nil)
        #expect(cache.object(forKey: key2) != nil)
    }
}

// MARK: - Task Coalescing Tests

@Suite("ImageStreamer Task Coalescing")
struct ImageStreamerCoalescingTests {

    @Test("Coalesces concurrent requests for same URL into single network call")
    func coalescesConcurrentRequests() async throws {
        let url = URL(string: "https://example.com/coalesce.png")!
        let imageData = MockImageData.validPNGData()
        let response = MockImageData.successResponse(for: url)

        let requestTracker = RequestTracker()
        let instrumentation = StandardImageStreamerInstrumentation()
        let (streamer, gate, _) = makeGatedStreamer(
            result: .success((imageData, response)),
            requestTracker: requestTracker,
            instrumentation: instrumentation
        )

        // Start multiple concurrent requests; the primary blocks on the gate
        let tasks = (0..<3).map { _ in
            Task { try await streamer.image(for: url) }
        }

        // Wait until both secondary requests have actually joined the primary,
        // then release the fetch
        try await waitForStats(instrumentation) { stats in
            stats.networkRequests == 1 && stats.coalescedRequests == 2
        }
        await gate.open()

        // All should complete without throwing
        for task in tasks {
            _ = try await task.value
        }

        // But only one network request should have been made
        let totalRequests = await requestTracker.requestCount(for: url)
        #expect(totalRequests == 1, "Should coalesce concurrent requests into a single network call")
    }


    @Test("Does not coalesce requests for same URL with different point sizes")
    func doesNotCoalesceDifferentSizes() async throws {
        let url = URL(string: "https://example.com/image.png")!
        let imageData = MockImageData.validPNGData()
        let response = MockImageData.successResponse(for: url)

        let requestTracker = RequestTracker()
        // No delay needed: these requests have distinct cache keys (different point
        // sizes), so they can never coalesce regardless of timing.
        let (streamer, _) = makeStreamer(
            result: .success((imageData, response)),
            requestTracker: requestTracker
        )

        // Start concurrent requests for same URL but different sizes
        async let original = streamer.image(for: url, pointSize: nil)
        async let thumbnail = streamer.image(for: url, pointSize: CGSize(width: 50, height: 50))
        async let medium = streamer.image(for: url, pointSize: CGSize(width: 200, height: 200))

        _ = try await (original, thumbnail, medium)

        // All three should trigger separate requests
        let totalRequests = await requestTracker.requestCount(for: url)
        #expect(totalRequests == 3, "Different sizes should not be coalesced")
    }

    @Test("Propagates error to all coalesced requests")
    func propagatesErrorToCoalescedRequests() async throws {
        let url = URL(string: "https://example.com/failing.png")!
        let invalidData = MockImageData.invalidData()
        let response = MockImageData.successResponse(for: url)

        let requestTracker = RequestTracker()
        let instrumentation = StandardImageStreamerInstrumentation()
        let (streamer, gate, _) = makeGatedStreamer(
            result: .success((invalidData, response)),
            requestTracker: requestTracker,
            instrumentation: instrumentation
        )

        // Start multiple concurrent requests that will all fail
        let task1 = Task { try await streamer.image(for: url) }
        let task2 = Task { try await streamer.image(for: url) }
        let task3 = Task { try await streamer.image(for: url) }

        // Wait until both secondary requests have joined the primary before failing it
        try await waitForStats(instrumentation) { stats in
            stats.networkRequests == 1 && stats.coalescedRequests == 2
        }
        await gate.open()

        // All should throw the same error
        await #expect(throws: ImageStreamerError.invalidImageData) {
            _ = try await task1.value
        }
        await #expect(throws: ImageStreamerError.invalidImageData) {
            _ = try await task2.value
        }
        await #expect(throws: ImageStreamerError.invalidImageData) {
            _ = try await task3.value
        }

        // But only one network request should have been made
        let totalRequests = await requestTracker.requestCount(for: url)
        #expect(totalRequests == 1, "Should coalesce requests even when they fail")
    }

    @Test("Multiple secondary waiters all receive the same result")
    func multipleSecondaryWaitersReceiveSameResult() async throws {
        let url = URL(string: "https://example.com/shared.png")!
        let imageData = MockImageData.validPNGData()
        let response = MockImageData.successResponse(for: url)

        let instrumentation = StandardImageStreamerInstrumentation()
        let requestTracker = RequestTracker()
        let (streamer, gate, _) = makeGatedStreamer(
            result: .success((imageData, response)),
            requestTracker: requestTracker,
            instrumentation: instrumentation
        )

        // Start 5 concurrent requests - 1 primary + 4 secondary waiters
        let tasks = (0..<5).map { _ in
            Task { try await streamer.image(for: url) }
        }

        // Wait until all 4 secondary requests have joined the primary, then release it
        try await waitForStats(instrumentation) { stats in
            stats.networkRequests == 1 && stats.coalescedRequests == 4
        }
        await gate.open()

        // Every waiter must receive the exact same image instance produced by the
        // single shared fetch - that is the whole point of coalescing.
        var images: [PlatformImage] = []
        for task in tasks {
            images.append(try await task.value)
        }
        let first = try #require(images.first)
        for image in images.dropFirst() {
            #expect(image === first, "All coalesced waiters should receive the same image instance")
        }

        // Only one network request
        let totalRequests = await requestTracker.requestCount(for: url)
        #expect(totalRequests == 1)
    }

    @Test("Subsequent request after coalesced batch completes triggers new network request")
    func subsequentRequestAfterCoalescedBatchTriggersNewRequest() async throws {
        let url = URL(string: "https://example.com/sequential.png")!
        let imageData = MockImageData.validPNGData()
        let response = MockImageData.successResponse(for: url)

        let requestTracker = RequestTracker()
        let (streamer, cache) = makeStreamer(
            result: .success((imageData, response)),
            delay: .milliseconds(100),
            requestTracker: requestTracker
        )

        // First batch of coalesced requests
        async let image1 = streamer.image(for: url)
        async let image2 = streamer.image(for: url)
        _ = try await (image1, image2)

        // Clear the cache to force a new network request
        cache.removeAllObjects()

        // New request after batch completes should trigger a new network request
        _ = try await streamer.image(for: url)

        let totalRequests = await requestTracker.requestCount(for: url)
        #expect(totalRequests == 2, "Should make a new network request after cache is cleared")
    }
}

// MARK: - Cancellation Tests

@Suite("ImageStreamer Cancellation")
struct ImageStreamerCancellationTests {

    @Test("Throws CancellationError when task is cancelled during fetch")
    func throwsCancellationErrorWhenCancelled() async throws {
        let url = URL(string: "https://example.com/slow.png")!
        let imageData = MockImageData.validPNGData()
        let response = MockImageData.successResponse(for: url)

        let instrumentation = StandardImageStreamerInstrumentation()
        let (streamer, gate, _) = makeGatedStreamer(
            result: .success((imageData, response)),
            instrumentation: instrumentation
        )

        let task = Task {
            try await streamer.image(for: url)
        }

        // Wait until the fetch is genuinely in flight (parked on the gate) before cancelling
        try await waitForStats(instrumentation) { $0.networkRequests == 1 }
        task.cancel()

        // The sole waiter cancelling must tear down the underlying network task
        try await waitForStats(instrumentation) { $0.cancelledTasks == 1 }

        // Release the gate so the cancelled fetch can unwind
        await gate.open()

        // Should throw CancellationError
        do {
            _ = try await task.value
            Issue.record("Expected CancellationError to be thrown")
        } catch is CancellationError {
            // Expected
        } catch {
            Issue.record("Expected CancellationError but got \(type(of: error)): \(error)")
        }
    }

    @Test("Throws CancellationError when all coalesced tasks are cancelled during fetch")
    func throwsCancellationErrorWhenAllCoalescedTasksCancelled() async throws {
        let url = URL(string: "https://example.com/coalesced-cancel.png")!
        let imageData = MockImageData.validPNGData()
        let response = MockImageData.successResponse(for: url)

        let requestTracker = RequestTracker()
        let instrumentation = StandardImageStreamerInstrumentation()
        let (streamer, gate, _) = makeGatedStreamer(
            result: .success((imageData, response)),
            requestTracker: requestTracker,
            instrumentation: instrumentation
        )

        // Start multiple concurrent requests that will be coalesced
        let task1 = Task {
            try await streamer.image(for: url)
        }
        let task2 = Task {
            try await streamer.image(for: url)
        }
        let task3 = Task {
            try await streamer.image(for: url)
        }

        // Wait until both secondaries have joined the primary, then cancel all of them
        try await waitForStats(instrumentation) { $0.networkRequests == 1 && $0.coalescedRequests == 2 }
        task1.cancel()
        task2.cancel()
        task3.cancel()

        // Once every waiter is gone, the underlying network task must be cancelled
        try await waitForStats(instrumentation) { $0.cancelledTasks == 1 }
        await gate.open()

        // All should throw CancellationError
        for (index, task) in [task1, task2, task3].enumerated() {
            do {
                _ = try await task.value
                Issue.record("Expected CancellationError for task \(index + 1)")
            } catch is CancellationError {
                // Expected
            } catch {
                Issue.record("Expected CancellationError for task \(index + 1) but got \(type(of: error)): \(error)")
            }
        }

        // Verify only one network request was initiated (coalesced)
        let totalRequests = await requestTracker.requestCount(for: url)
        #expect(totalRequests == 1, "Should have made only one coalesced network request")
    }

    @Test("Does not cache image when request is cancelled")
    func doesNotCacheWhenCancelled() async throws {
        let url = URL(string: "https://example.com/cancelled.png")!
        let imageData = MockImageData.validPNGData()
        let response = MockImageData.successResponse(for: url)

        let instrumentation = StandardImageStreamerInstrumentation()
        let (streamer, gate, cache) = makeGatedStreamer(
            result: .success((imageData, response)),
            instrumentation: instrumentation
        )

        let cacheKey = ImageCacheKey(url: url, pointSize: nil)

        let task = Task {
            try await streamer.image(for: url)
        }

        // Hold the fetch on the gate, then cancel and wait for the underlying task to be cancelled
        // *before* opening the gate, so the fetch sees the cancellation and never reaches the cache write.
        try await waitForStats(instrumentation) { $0.networkRequests == 1 }
        task.cancel()
        try await waitForStats(instrumentation) { $0.cancelledTasks == 1 }
        await gate.open()

        // Wait for cancellation to complete
        _ = try? await task.value

        // Nothing should be cached
        #expect(cache.object(forKey: cacheKey) == nil, "Cancelled request should not cache anything")
    }

    @Test("Cancellation of one coalesced request does not affect others")
    func cancellationDoesNotAffectOtherCoalescedRequests() async throws {
        let url = URL(string: "https://example.com/shared.png")!
        let imageData = MockImageData.validPNGData()
        let response = MockImageData.successResponse(for: url)

        let instrumentation = StandardImageStreamerInstrumentation()
        let (streamer, gate, _) = makeGatedStreamer(
            result: .success((imageData, response)),
            instrumentation: instrumentation
        )

        // task1 becomes the primary and parks on the gate
        let task1 = Task {
            try await streamer.image(for: url)
        }
        try await waitForStats(instrumentation) { $0.networkRequests == 1 }

        // task2 joins as a secondary waiter
        let task2 = Task {
            try await streamer.image(for: url)
        }
        try await waitForStats(instrumentation) { $0.coalescedRequests == 1 }

        // Cancel only the first task; task2 keeps the shared fetch alive
        task1.cancel()
        await gate.open()

        // The second task should still complete successfully
        _ = try await task2.value
    }


    @Test("Does not track cancellation when other callers remain")
    func doesNotTrackCancellationWhenOthersRemain() async throws {
        let url = URL(string: "https://example.com/shared.png")!
        let imageData = MockImageData.validPNGData()
        let response = MockImageData.successResponse(for: url)

        let instrumentation = StandardImageStreamerInstrumentation()
        let (streamer, gate, _) = makeGatedStreamer(
            result: .success((imageData, response)),
            instrumentation: instrumentation
        )

        // task1 becomes the primary and parks on the gate
        let task1 = Task {
            try await streamer.image(for: url)
        }
        try await waitForStats(instrumentation) { $0.networkRequests == 1 }

        // task2 joins as a secondary waiter
        let task2 = Task {
            try await streamer.image(for: url)
        }
        try await waitForStats(instrumentation) { $0.coalescedRequests == 1 }

        // Cancel only the first task; task2 keeps the request alive
        task1.cancel()
        await gate.open()

        // Wait for cancellation to propagate (ignoring error)
        _ = try? await task1.value

        // The second task should still complete successfully
        _ = try await task2.value

        // No cancelled tasks should be recorded since task2 kept the request alive
        let stats = await instrumentation.currentStats
        #expect(stats.cancelledTasks == 0, "Task should not be counted as cancelled when other callers remain")
    }


    @Test("Cancelling primary task while secondary waiters remain")
    func cancellingPrimaryTaskWhileSecondaryWaitersRemain() async throws {
        let url = URL(string: "https://example.com/primary-cancel.png")!
        let imageData = MockImageData.validPNGData()
        let response = MockImageData.successResponse(for: url)

        let instrumentation = StandardImageStreamerInstrumentation()
        let (streamer, gate, _) = makeGatedStreamer(
            result: .success((imageData, response)),
            instrumentation: instrumentation
        )

        // Start primary task and wait until it owns the in-flight fetch
        let primaryTask = Task { try await streamer.image(for: url) }
        try await waitForStats(instrumentation) { $0.networkRequests == 1 }

        // Start secondary waiters and wait until both have joined the primary
        let secondaryTask1 = Task { try await streamer.image(for: url) }
        let secondaryTask2 = Task { try await streamer.image(for: url) }
        try await waitForStats(instrumentation) { $0.coalescedRequests == 2 }

        // Cancel the primary task; the two secondaries keep the fetch alive
        primaryTask.cancel()
        await gate.open()

        // Secondary tasks should still complete successfully
        _ = try await secondaryTask1.value
        _ = try await secondaryTask2.value

        // No cancellation should be tracked since secondary tasks kept request alive
        let stats = await instrumentation.currentStats
        #expect(stats.cancelledTasks == 0, "No cancellation should be tracked when secondary tasks remain")
    }

    @Test("Cancellation is tracked only when all waiters are cancelled")
    func cancellationTrackedOnlyWhenAllWaitersCancelled() async throws {
        let url = URL(string: "https://example.com/all-cancel.png")!
        let imageData = MockImageData.validPNGData()
        let response = MockImageData.successResponse(for: url)

        let instrumentation = StandardImageStreamerInstrumentation()
        let (streamer, gate, _) = makeGatedStreamer(
            result: .success((imageData, response)),
            instrumentation: instrumentation
        )

        // Start multiple concurrent requests
        let tasks = (0..<5).map { _ in
            Task { try await streamer.image(for: url) }
        }

        // Wait until 1 primary + 4 coalesced waiters are all established
        try await waitForStats(instrumentation) { $0.networkRequests == 1 && $0.coalescedRequests == 4 }

        // Cancel all tasks
        for task in tasks {
            task.cancel()
        }

        // Should have exactly 1 cancelled task tracked (the underlying network request)
        try await waitForStats(instrumentation) { stats in
            stats.cancelledTasks == 1
        }

        // Release the gate so the cancelled fetch can unwind
        await gate.open()
        for task in tasks {
            _ = try? await task.value
        }
    }

    @Test("Late joiner after some cancellations still receives result")
    func lateJoinerAfterSomeCancellationsStillReceivesResult() async throws {
        let url = URL(string: "https://example.com/late-join.png")!
        let imageData = MockImageData.validPNGData()
        let response = MockImageData.successResponse(for: url)

        let instrumentation = StandardImageStreamerInstrumentation()
        let (streamer, gate, _) = makeGatedStreamer(
            result: .success((imageData, response)),
            instrumentation: instrumentation
        )

        // task1 becomes the primary; task2 joins it
        let task1 = Task { try await streamer.image(for: url) }
        try await waitForStats(instrumentation) { $0.networkRequests == 1 }
        let task2 = Task { try await streamer.image(for: url) }
        try await waitForStats(instrumentation) { $0.coalescedRequests == 1 }

        // Cancel task1; task2 keeps the shared fetch alive
        task1.cancel()

        // A late joiner arrives while task2 is still waiting and coalesces onto the same fetch
        let lateJoiner = Task { try await streamer.image(for: url) }
        try await waitForStats(instrumentation) { $0.coalescedRequests == 2 }

        // Release the fetch; both remaining waiters should complete successfully
        await gate.open()
        _ = try await task2.value
        _ = try await lateJoiner.value
    }

    @Test("A cancelled primary's cleanup does not tear down a replacement entry for the same key")
    func cancelledPrimaryDoesNotRemoveReplacementEntry() async throws {
        let url = URL(string: "https://example.com/replace.png")!
        let imageData = MockImageData.validPNGData()
        let response = MockImageData.successResponse(for: url)

        let requestTracker = RequestTracker()
        let instrumentation = StandardImageStreamerInstrumentation()
        let (streamer, gate, _) = makeGatedStreamer(
            result: .success((imageData, response)),
            requestTracker: requestTracker,
            instrumentation: instrumentation
        )

        // Request A becomes the primary and parks on the gate
        let requestA = Task { try await streamer.image(for: url) }
        try await waitForStats(instrumentation) { $0.networkRequests == 1 }

        // Cancelling the sole waiter tears down A's entry and cancels its underlying task,
        // but the orphaned fetch is still parked on the (shared) gate.
        requestA.cancel()
        try await waitForStats(instrumentation) { $0.cancelledTasks == 1 }

        // Request B installs a brand-new primary entry under the same key
        let requestB = Task { try await streamer.image(for: url) }
        try await waitForStats(instrumentation) { $0.networkRequests == 2 }

        // A late joiner must coalesce onto B's entry - proving B's entry is intact and was
        // not removed by A's (cancelled) cleanup running later under the same key.
        let requestC = Task { try await streamer.image(for: url) }
        try await waitForStats(instrumentation) { $0.coalescedRequests == 1 }

        // Release everything: A unwinds as cancelled, B and C share the second fetch
        await gate.open()
        _ = try? await requestA.value
        _ = try await requestB.value
        _ = try await requestC.value

        // Exactly two underlying fetches: A (cancelled) and B (shared by C, not a third fetch)
        let total = await requestTracker.requestCount(for: url)
        #expect(total == 2, "Late joiner should coalesce onto the replacement entry, not start a third fetch")
    }
}

// MARK: - Convenience API Tests

@Suite("ImageStreamer Convenience API")
struct ImageStreamerConvenienceTests {

    @Test("Loads image from valid URL string")
    func loadsImageFromValidURLString() async throws {
        let urlString = "https://example.com/test.png"
        let url = URL(string: urlString)!
        let imageData = MockImageData.validPNGData()
        let response = MockImageData.successResponse(for: url)

        let (streamer, _) = makeStreamer(result: .success((imageData, response)))

        let image = try await streamer.image(for: urlString)
        #expect(extractCGImage(from: image) != nil)
    }

    @Test("Throws invalidURL for bad URL strings", arguments: [
            "",                              // empty string
            "not a valid url with spaces"    // malformed URL
        ]
    )
    func throwsInvalidURLForBadStrings(input: String) async throws {
        let (streamer, _) = makeStreamer(result: .success((Data(), URLResponse())))

        await #expect(throws: ImageStreamerError.invalidURL) {
            _ = try await streamer.image(for: input)
        }
    }

    @Test("Loads image from URL with special characters")
    func loadsImageFromURLWithSpecialCharacters() async throws {
        let urlString = "https://example.com/path/image%20name.png"
        let url = URL(string: urlString)!
        let imageData = MockImageData.validPNGData()
        let response = MockImageData.successResponse(for: url)

        let (streamer, _) = makeStreamer(result: .success((imageData, response)))

        let image = try await streamer.image(for: urlString)
        #expect(extractCGImage(from: image) != nil)
    }
}

// MARK: - HTTP Status Code Tests

@Suite("ImageStreamer HTTP Status Codes")
struct ImageStreamerHTTPStatusTests {

    @Test("Accepts 2xx status codes", arguments: [200, 201, 202, 204, 206, 299])
    func accepts2xxStatusCodes(statusCode: Int) async throws {
        let url = URL(string: "https://example.com/test.png")!
        let imageData = MockImageData.validPNGData()
        let response = MockImageData.successResponse(for: url, statusCode: statusCode)

        let (streamer, _) = makeStreamer(result: .success((imageData, response)))

        // Should not throw for 2xx status codes, and should return a usable image
        let image = try await streamer.image(for: url)
        #expect(extractCGImage(from: image) != nil)
    }

    @Test("Rejects 4xx client error status codes", arguments: [400, 401, 403, 404, 405, 408, 429])
    func rejects4xxStatusCodes(statusCode: Int) async throws {
        let url = URL(string: "https://example.com/test.png")!
        let imageData = MockImageData.validPNGData()
        let response = MockImageData.successResponse(for: url, statusCode: statusCode)

        let (streamer, _) = makeStreamer(result: .success((imageData, response)))

        let error = await #expect(throws: URLError.self) {
            _ = try await streamer.image(for: url)
        }
        #expect(error?.code == .badServerResponse)
    }

    @Test("Rejects 5xx server error status codes", arguments: [500, 501, 502, 503, 504])
    func rejects5xxStatusCodes(statusCode: Int) async throws {
        let url = URL(string: "https://example.com/test.png")!
        let imageData = MockImageData.validPNGData()
        let response = MockImageData.successResponse(for: url, statusCode: statusCode)

        let (streamer, _) = makeStreamer(result: .success((imageData, response)))

        let error = await #expect(throws: URLError.self) {
            _ = try await streamer.image(for: url)
        }
        #expect(error?.code == .badServerResponse)
    }

    @Test("Rejects 3xx redirect status codes", arguments: [301, 302, 303, 307, 308])
    func rejects3xxStatusCodes(statusCode: Int) async throws {
        let url = URL(string: "https://example.com/test.png")!
        let imageData = MockImageData.validPNGData()
        let response = MockImageData.successResponse(for: url, statusCode: statusCode)

        let (streamer, _) = makeStreamer(result: .success((imageData, response)))

        let error = await #expect(throws: URLError.self) {
            _ = try await streamer.image(for: url)
        }
        #expect(error?.code == .badServerResponse)
    }

    @Test("Rejects 1xx informational status codes", arguments: [100, 101, 102])
    func rejects1xxStatusCodes(statusCode: Int) async throws {
        let url = URL(string: "https://example.com/test.png")!
        let imageData = MockImageData.validPNGData()
        let response = MockImageData.successResponse(for: url, statusCode: statusCode)

        let (streamer, _) = makeStreamer(result: .success((imageData, response)))

        let error = await #expect(throws: URLError.self) {
            _ = try await streamer.image(for: url)
        }
        #expect(error?.code == .badServerResponse)
    }
}

// MARK: - Statistics Tests

@Suite("ImageStreamer Statistics")
struct ImageStreamerStatsTests {

    @Test("Tracks cache hits correctly")
    func tracksCacheHits() async throws {
        let url = URL(string: "https://example.com/test.png")!
        let imageData = MockImageData.validPNGData()
        let response = MockImageData.successResponse(for: url)

        let instrumentation = StandardImageStreamerInstrumentation()
        let (streamer, _) = makeStreamer(
            result: .success((imageData, response)),
            instrumentation: instrumentation
        )

        // First load (network)
        _ = try await streamer.image(for: url)

        try await waitForStats(instrumentation) { stats in
            stats.networkRequests == 1 && stats.cacheHits == 0
        }

        // Second load (cache hit)
        _ = try await streamer.image(for: url)

        try await waitForStats(instrumentation) { stats in
            stats.cacheHits == 1 && stats.networkRequests == 1
        }

        // Third load (another cache hit)
        _ = try await streamer.image(for: url)

        try await waitForStats(instrumentation) { stats in
            stats.cacheHits == 2 && stats.networkRequests == 1
        }
    }


    @Test("Tracks coalesced requests correctly")
    func tracksCoalescedRequests() async throws {
        let url = URL(string: "https://example.com/coalesce.png")!
        let imageData = MockImageData.validPNGData()
        let response = MockImageData.successResponse(for: url)

        let instrumentation = StandardImageStreamerInstrumentation()
        let (streamer, gate, _) = makeGatedStreamer(
            result: .success((imageData, response)),
            instrumentation: instrumentation
        )

        // Start multiple concurrent requests; the primary blocks on the gate
        let tasks = (0..<3).map { _ in
            Task { try await streamer.image(for: url) }
        }

        // One network request, two coalesced requests
        try await waitForStats(instrumentation) { stats in
            stats.networkRequests == 1 && stats.coalescedRequests == 2
        }
        await gate.open()

        for task in tasks {
            _ = try await task.value
        }
    }

    @Test("Resets statistics to zero")
    func resetsStatistics() async throws {
        let url = URL(string: "https://example.com/test.png")!
        let imageData = MockImageData.validPNGData()
        let response = MockImageData.successResponse(for: url)

        let instrumentation = StandardImageStreamerInstrumentation()
        let (streamer, _) = makeStreamer(
            result: .success((imageData, response)),
            instrumentation: instrumentation
        )

        // Generate some stats
        _ = try await streamer.image(for: url)
        _ = try await streamer.image(for: url)

        try await waitForStats(instrumentation) { stats in
            stats.networkRequests == 1 && stats.cacheHits == 1
        }

        // Reset stats
        await streamer.resetStats()

        // Verify stats are zero
        let statsAfterReset = await instrumentation.currentStats
        #expect(statsAfterReset == ImageStreamerStats.zero)
    }

    @Test("Does not increment stats on failure")
    func doesNotIncrementCacheHitsOnFailure() async throws {
        let url = URL(string: "https://example.com/failing.png")!
        let invalidData = MockImageData.invalidData()
        let response = MockImageData.successResponse(for: url)

        let instrumentation = StandardImageStreamerInstrumentation()
        let (streamer, _) = makeStreamer(
            result: .success((invalidData, response)),
            instrumentation: instrumentation
        )

        // Attempt to load (will fail)
        _ = try? await streamer.image(for: url)

        try await waitForStats(instrumentation) { stats in
            stats.networkRequests == 1
        }

        // Attempt again (should still be a network request, not a cache hit)
        _ = try? await streamer.image(for: url)

        try await waitForStats(instrumentation) { stats in
            stats.networkRequests == 2 && stats.cacheHits == 0
        }
    }
}

// MARK: - Edge Case Tests

@Suite("ImageStreamer Edge Cases")
struct ImageStreamerEdgeCaseTests {

    @Test(
        "Handles various point sizes without throwing",
        arguments: [
            CGSize(width: 1, height: 1),         // very small
            CGSize(width: 10000, height: 10000), // larger than the source image
            CGSize(width: 200, height: 50)        // non-square
        ]
    )
    func handlesVariousPointSizes(pointSize: CGSize) async throws {
        let url = URL(string: "https://example.com/image.png")!
        let sourceDimension = 512
        let imageData = MockImageData.largePNGData(dimension: sourceDimension)
        let response = MockImageData.successResponse(for: url)

        let (streamer, _) = makeStreamer(result: .success((imageData, response)))

        let image = try await streamer.image(for: url, pointSize: pointSize)

        // Regardless of the requested size, downsampling must never upscale beyond the
        // source - even when the requested size (e.g. 10000x10000) exceeds it.
        let cgImage = try #require(extractCGImage(from: image))
        #expect(cgImage.width <= sourceDimension && cgImage.height <= sourceDimension)
        #expect(cgImage.width > 0 && cgImage.height > 0)
    }

    @Test("Same URL with different query parameters are cached separately")
    func differentQueryParametersCachedSeparately() async throws {
        let url1 = URL(string: "https://example.com/image.png?v=1")!
        let url2 = URL(string: "https://example.com/image.png?v=2")!
        let imageData = MockImageData.validPNGData()

        let responses: [URL: Result<(Data, URLResponse), Error>] = [
            url1: .success((imageData, MockImageData.successResponse(for: url1))),
            url2: .success((imageData, MockImageData.successResponse(for: url2)))
        ]

        let requestTracker = RequestTracker()
        let (streamer, cache) = makeStreamer(
            responses: responses,
            requestTracker: requestTracker
        )

        let key1 = ImageCacheKey(url: url1, pointSize: nil)
        let key2 = ImageCacheKey(url: url2, pointSize: nil)

        // Fetch first URL
        _ = try await streamer.image(for: url1)
        #expect(cache.object(forKey: key1) != nil)
        #expect(cache.object(forKey: key2) == nil)

        // Fetch second URL
        _ = try await streamer.image(for: url2)
        #expect(cache.object(forKey: key1) != nil)
        #expect(cache.object(forKey: key2) != nil)

        // Both should have made network requests
        let totalRequests = await requestTracker.requestedURLs.count
        #expect(totalRequests == 2)
    }

    @Test("Handles HTTP response without HTTPURLResponse type")
    func handlesNonHTTPResponse() async throws {
        let url = URL(string: "https://example.com/test.png")!
        let imageData = MockImageData.validPNGData()
        // Use base URLResponse instead of HTTPURLResponse
        let response = URLResponse(url: url, mimeType: "image/png", expectedContentLength: imageData.count, textEncodingName: nil)

        let (streamer, _) = makeStreamer(result: .success((imageData, response)))

        // Should still work since non-HTTP responses pass the status check
        let image = try await streamer.image(for: url)
        #expect(extractCGImage(from: image) != nil)
    }
}

// MARK: - ImageCacheKey Tests

@Suite("ImageCacheKey")
struct ImageCacheKeyTests {

    @Test("Keys with same URL and size are equal")
    func keysWithSameURLAndSizeAreEqual() {
        let url = URL(string: "https://example.com/image.png")!
        let size = CGSize(width: 100, height: 100)

        let key1 = ImageCacheKey(url: url, pointSize: size)
        let key2 = ImageCacheKey(url: url, pointSize: size)

        #expect(key1.isEqual(key2))
        #expect(key1.hash == key2.hash)
    }

    @Test("Keys with different URLs are not equal")
    func keysWithDifferentURLsAreNotEqual() {
        let url1 = URL(string: "https://example.com/image1.png")!
        let url2 = URL(string: "https://example.com/image2.png")!

        let key1 = ImageCacheKey(url: url1, pointSize: nil)
        let key2 = ImageCacheKey(url: url2, pointSize: nil)

        #expect(!key1.isEqual(key2))
    }

    @Test("Keys with different sizes are not equal")
    func keysWithDifferentSizesAreNotEqual() {
        let url = URL(string: "https://example.com/image.png")!

        let key1 = ImageCacheKey(url: url, pointSize: CGSize(width: 100, height: 100))
        let key2 = ImageCacheKey(url: url, pointSize: CGSize(width: 200, height: 200))

        #expect(!key1.isEqual(key2))
    }

    @Test("Key with nil size differs from key with zero size")
    func nilSizeDiffersFromZeroSize() {
        let url = URL(string: "https://example.com/image.png")!

        let keyNil = ImageCacheKey(url: url, pointSize: nil)
        let keyZero = ImageCacheKey(url: url, pointSize: CGSize(width: 0, height: 0))

        #expect(!keyNil.isEqual(keyZero))
    }

    // ImageCacheKey is used as the key type for NSCache, which relies on the
    // Objective-C `isEqual(_:)` / `hash` contract for key lookup. This test
    // guards that contract. If ImageCacheKey is ever replaced by a pure
    // Swift `Hashable` struct used with a `Dictionary`-backed cache, this
    // test can be removed.
    @Test("Key is not equal to non-ImageCacheKey object")
    func keyNotEqualToOtherTypes() {
        let url = URL(string: "https://example.com/image.png")!
        let key = ImageCacheKey(url: url, pointSize: nil)

        #expect(!key.isEqual("not a key"))
        #expect(!key.isEqual(nil))
        #expect(!key.isEqual(url))
    }
}

// MARK: - ImageCache Tests

@Suite("ImageCache")
struct ImageCacheTests {

    private func makeImage() throws -> PlatformImage {
        try #require(PlatformImage(data: MockImageData.validPNGData()))
    }

    @Test("Stores and retrieves an image by key")
    func storesAndRetrievesImage() throws {
        let cache = ImageCache()
        let key = ImageCacheKey(url: URL(string: "https://example.com/a.png")!, pointSize: nil)
        let image = try makeImage()

        cache.setObject(image, forKey: key, cost: 1)

        #expect(cache.object(forKey: key) === image)
    }

    @Test("Returns nil for an unknown key")
    func returnsNilForUnknownKey() {
        let cache = ImageCache()
        let key = ImageCacheKey(url: URL(string: "https://example.com/missing.png")!, pointSize: nil)

        #expect(cache.object(forKey: key) == nil)
    }

    @Test("Removes a single entry")
    func removesSingleEntry() throws {
        let cache = ImageCache()
        let key = ImageCacheKey(url: URL(string: "https://example.com/a.png")!, pointSize: nil)
        cache.setObject(try makeImage(), forKey: key, cost: 1)

        cache.removeObject(forKey: key)

        #expect(cache.object(forKey: key) == nil)
    }

    @Test("Removes all entries")
    func removesAllEntries() throws {
        let cache = ImageCache()
        let key1 = ImageCacheKey(url: URL(string: "https://example.com/a.png")!, pointSize: nil)
        let key2 = ImageCacheKey(url: URL(string: "https://example.com/b.png")!, pointSize: nil)
        let image = try makeImage()
        cache.setObject(image, forKey: key1, cost: 1)
        cache.setObject(image, forKey: key2, cost: 1)

        cache.removeAllObjects()

        #expect(cache.object(forKey: key1) == nil)
        #expect(cache.object(forKey: key2) == nil)
    }

    // The wrapper forwards these limits to NSCache. We only assert the values round-trip:
    // NSCache treats both as advisory ("not a strict limit"), so it may evict immediately,
    // later, or never - asserting actual eviction here would be inherently flaky.
    @Test("Cost and count limits round-trip through the wrapper")
    func limitsRoundTrip() {
        let cache = ImageCache()

        cache.totalCostLimit = 5_000_000
        cache.countLimit = 42

        #expect(cache.totalCostLimit == 5_000_000)
        #expect(cache.countLimit == 42)
    }
}

// MARK: - Test Helpers

/// Creates a configured ImageStreamer with its dependencies for testing.
func makeStreamer(
    result: Result<(Data, URLResponse), Error>,
    delay: Duration? = nil,
    requestTracker: RequestTracker? = nil,
    instrumentation: ImageStreamerInstrumentation? = nil
) -> (streamer: ImageStreamer, cache: ImageCache) {
    let mockFetcher = MockImageFetcher(
        result: result,
        delay: delay,
        requestTracker: requestTracker
    )
    let cache = ImageCache()
    let streamer = ImageStreamer(
        session: mockFetcher,
        cache: cache,
        instrumentation: instrumentation
    )
    return (streamer, cache)
}

/// Creates a configured ImageStreamer with URL-based response mapping.
func makeStreamer(
    responses: [URL: Result<(Data, URLResponse), Error>],
    delay: Duration? = nil,
    requestTracker: RequestTracker? = nil,
    instrumentation: ImageStreamerInstrumentation? = nil
) -> (streamer: ImageStreamer, cache: ImageCache) {
    let mockFetcher = URLMappingMockFetcher(
        responses: responses,
        delay: delay,
        requestTracker: requestTracker
    )
    let cache = ImageCache()
    let streamer = ImageStreamer(
        session: mockFetcher,
        cache: cache,
        instrumentation: instrumentation
    )
    return (streamer, cache)
}

/// Creates a configured ImageStreamer whose fetches block until the returned gate is opened.
/// Use this (instead of fixed delays) when a test must guarantee that requests overlap.
func makeGatedStreamer(
    result: Result<(Data, URLResponse), Error>,
    requestTracker: RequestTracker? = nil,
    instrumentation: ImageStreamerInstrumentation? = nil
) -> (streamer: ImageStreamer, gate: RequestGate, cache: ImageCache) {
    let gate = RequestGate()
    let cache = ImageCache()
    let mockFetcher = GatedMockFetcher(
        result: result,
        gate: gate,
        requestTracker: requestTracker
    )
    let streamer = ImageStreamer(
        session: mockFetcher,
        cache: cache,
        instrumentation: instrumentation
    )
    return (streamer, gate, cache)
}

/// Helper to wait for async stats updates with timeout.
private func waitForStats(
    _ instrumentation: StandardImageStreamerInstrumentation,
    timeout: Duration = .seconds(2),
    condition: @escaping (ImageStreamerStats) -> Bool
) async throws {
    let startTime = ContinuousClock.now
    while ContinuousClock.now - startTime < timeout {
        let stats = await instrumentation.currentStats
        if condition(stats) {
            return
        }
        try await Task.sleep(for: .milliseconds(50))
    }
    let finalStats = await instrumentation.currentStats
    #expect(condition(finalStats), "Timeout waiting for stats condition. Final stats: cacheHits=\(finalStats.cacheHits), networkRequests=\(finalStats.networkRequests), coalescedRequests=\(finalStats.coalescedRequests), cancelledTasks=\(finalStats.cancelledTasks)")
}
