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

        #expect(image.cgImage != nil)
    }

    @Test("Loads and downsamples image to specified point size")
    func loadsDownsampledImage() async throws {
        let url = URL(string: "https://example.com/large.png")!
        let imageData = MockImageData.validPNGData()
        let response = MockImageData.successResponse(for: url)

        let (streamer, _) = makeStreamer(result: .success((imageData, response)))

        let image = try await streamer.image(for: url, pointSize: CGSize(width: 100, height: 100))

        #expect(image.cgImage != nil)
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

        await #expect(throws: URLError.self) {
            _ = try await streamer.image(for: url)
        }
    }

    @Test("Propagates network errors from the session")
    func propagatesNetworkErrors() async throws {
        let url = URL(string: "https://example.com/test.png")!
        let networkError = URLError(.notConnectedToInternet)

        let (streamer, _) = makeStreamer(result: .failure(networkError))

        await #expect(throws: URLError.self) {
            _ = try await streamer.image(for: url)
        }
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
        let (streamer, gate) = makeGatedStreamer(
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
        let (streamer, _) = makeStreamer(
            result: .success((imageData, response)),
            delay: .milliseconds(100),
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
        let (streamer, gate) = makeGatedStreamer(
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
        let (streamer, gate) = makeGatedStreamer(
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

        // All should complete successfully without throwing
        for task in tasks {
            _ = try await task.value
        }

        // Only one network request
        let totalRequests = await requestTracker.requestCount(for: url)
        #expect(totalRequests == 1)

        // Should have 1 network request + 4 coalesced requests
        try await waitForStats(instrumentation) { stats in
            stats.networkRequests == 1 && stats.coalescedRequests == 4
        }
    }

    @Test("Subsequent request after coalesced batch completes triggers new network request")
    func subsequentRequestAfterCoalescedBatchTriggersNewRequest() async throws {
        let url = URL(string: "https://example.com/sequential.png")!
        let imageData = MockImageData.validPNGData()
        let response = MockImageData.successResponse(for: url)

        let requestTracker = RequestTracker()
        let instrumentation = StandardImageStreamerInstrumentation()
        let (streamer, cache) = makeStreamer(
            result: .success((imageData, response)),
            delay: .milliseconds(100),
            requestTracker: requestTracker,
            instrumentation: instrumentation
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

        let (streamer, _) = makeStreamer(
            result: .success((imageData, response)),
            delay: .seconds(10) // Long delay to ensure we can cancel
        )

        let task = Task {
            try await streamer.image(for: url)
        }

        // Give the task time to start
        try await Task.sleep(for: .milliseconds(50))

        // Cancel the task
        task.cancel()

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
        let (streamer, _) = makeStreamer(
            result: .success((imageData, response)),
            delay: .seconds(10), // Long delay to ensure we can cancel
            requestTracker: requestTracker
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

        // Give tasks time to start and coalesce
        try await Task.sleep(for: .milliseconds(50))

        // Cancel all tasks
        task1.cancel()
        task2.cancel()
        task3.cancel()

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

        let (streamer, cache) = makeStreamer(
            result: .success((imageData, response)),
            delay: .seconds(10)
        )

        let cacheKey = ImageCacheKey(url: url, pointSize: nil)

        let task = Task {
            try await streamer.image(for: url)
        }

        try await Task.sleep(for: .milliseconds(50))
        task.cancel()

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

        let (streamer, _) = makeStreamer(
            result: .success((imageData, response)),
            delay: .milliseconds(200)
        )

        // Start two concurrent requests
        let task1 = Task {
            try await streamer.image(for: url)
        }
        let task2 = Task {
            try await streamer.image(for: url)
        }

        // Give tasks time to coalesce
        try await Task.sleep(for: .milliseconds(50))

        // Cancel only the first task
        task1.cancel()

        // The second task should still complete successfully
        _ = try await task2.value
    }


    @Test("Does not track cancellation when other callers remain")
    func doesNotTrackCancellationWhenOthersRemain() async throws {
        let url = URL(string: "https://example.com/shared.png")!
        let imageData = MockImageData.validPNGData()
        let response = MockImageData.successResponse(for: url)

        let instrumentation = StandardImageStreamerInstrumentation()
        let (streamer, _) = makeStreamer(
            result: .success((imageData, response)),
            delay: .milliseconds(300),
            instrumentation: instrumentation
        )

        // Start two concurrent requests
        let task1 = Task {
            try await streamer.image(for: url)
        }
        let task2 = Task {
            try await streamer.image(for: url)
        }

        // Give tasks time to coalesce
        try await Task.sleep(for: .milliseconds(50))

        // Cancel only the first task
        task1.cancel()

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
        let (streamer, _) = makeStreamer(
            result: .success((imageData, response)),
            delay: .milliseconds(300),
            instrumentation: instrumentation
        )

        // Start primary task
        let primaryTask = Task { try await streamer.image(for: url) }
        
        // Small delay to ensure primaryTask becomes the primary
        try await Task.sleep(for: .milliseconds(20))
        
        // Start secondary waiters
        let secondaryTask1 = Task { try await streamer.image(for: url) }
        let secondaryTask2 = Task { try await streamer.image(for: url) }

        // Give all tasks time to coalesce
        try await Task.sleep(for: .milliseconds(50))

        // Cancel the primary task
        primaryTask.cancel()

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
        let (streamer, _) = makeStreamer(
            result: .success((imageData, response)),
            delay: .seconds(10), // Long delay to ensure we can cancel all
            instrumentation: instrumentation
        )

        // Start multiple concurrent requests
        let tasks = (0..<5).map { _ in
            Task { try await streamer.image(for: url) }
        }

        // Give all tasks time to coalesce
        try await Task.sleep(for: .milliseconds(100))

        // Cancel all tasks
        for task in tasks {
            task.cancel()
        }

        // Wait for all cancellations to propagate
        for task in tasks {
            _ = try? await task.value
        }

        // Should have exactly 1 cancelled task tracked (the underlying network request)
        try await waitForStats(instrumentation) { stats in
            stats.cancelledTasks == 1
        }
    }

    @Test("Late joiner after some cancellations still receives result")
    func lateJoinerAfterSomeCancellationsStillReceivesResult() async throws {
        let url = URL(string: "https://example.com/late-join.png")!
        let imageData = MockImageData.validPNGData()
        let response = MockImageData.successResponse(for: url)

        let (streamer, _) = makeStreamer(
            result: .success((imageData, response)),
            delay: .milliseconds(300)
        )

        // Start initial tasks
        let task1 = Task { try await streamer.image(for: url) }
        let task2 = Task { try await streamer.image(for: url) }

        // Give tasks time to coalesce
        try await Task.sleep(for: .milliseconds(50))

        // Cancel one task
        task1.cancel()
        _ = try? await task1.value

        // Start a late joiner while task2 is still waiting
        let lateJoiner = Task { try await streamer.image(for: url) }

        // Both remaining tasks should complete successfully
        _ = try await task2.value
        _ = try await lateJoiner.value
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

        _ = try await streamer.image(for: urlString)
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

        _ = try await streamer.image(for: urlString)
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

        // Should not throw for 2xx status codes
        _ = try await streamer.image(for: url)
    }

    @Test("Rejects 4xx client error status codes", arguments: [400, 401, 403, 404, 405, 408, 429])
    func rejects4xxStatusCodes(statusCode: Int) async throws {
        let url = URL(string: "https://example.com/test.png")!
        let imageData = MockImageData.validPNGData()
        let response = MockImageData.successResponse(for: url, statusCode: statusCode)

        let (streamer, _) = makeStreamer(result: .success((imageData, response)))

        await #expect(throws: URLError.self) {
            _ = try await streamer.image(for: url)
        }
    }

    @Test("Rejects 5xx server error status codes", arguments: [500, 501, 502, 503, 504])
    func rejects5xxStatusCodes(statusCode: Int) async throws {
        let url = URL(string: "https://example.com/test.png")!
        let imageData = MockImageData.validPNGData()
        let response = MockImageData.successResponse(for: url, statusCode: statusCode)

        let (streamer, _) = makeStreamer(result: .success((imageData, response)))

        await #expect(throws: URLError.self) {
            _ = try await streamer.image(for: url)
        }
    }

    @Test("Rejects 3xx redirect status codes", arguments: [301, 302, 303, 307, 308])
    func rejects3xxStatusCodes(statusCode: Int) async throws {
        let url = URL(string: "https://example.com/test.png")!
        let imageData = MockImageData.validPNGData()
        let response = MockImageData.successResponse(for: url, statusCode: statusCode)

        let (streamer, _) = makeStreamer(result: .success((imageData, response)))

        await #expect(throws: URLError.self) {
            _ = try await streamer.image(for: url)
        }
    }

    @Test("Rejects 1xx informational status codes", arguments: [100, 101, 102])
    func rejects1xxStatusCodes(statusCode: Int) async throws {
        let url = URL(string: "https://example.com/test.png")!
        let imageData = MockImageData.validPNGData()
        let response = MockImageData.successResponse(for: url, statusCode: statusCode)

        let (streamer, _) = makeStreamer(result: .success((imageData, response)))

        await #expect(throws: URLError.self) {
            _ = try await streamer.image(for: url)
        }
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
        let (streamer, gate) = makeGatedStreamer(
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
        let imageData = MockImageData.validPNGData()
        let response = MockImageData.successResponse(for: url)

        let (streamer, _) = makeStreamer(result: .success((imageData, response)))

        _ = try await streamer.image(for: url, pointSize: pointSize)
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
        _ = try await streamer.image(for: url)
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
) -> (streamer: ImageStreamer, gate: RequestGate) {
    let gate = RequestGate()
    let mockFetcher = GatedMockFetcher(
        result: result,
        gate: gate,
        requestTracker: requestTracker
    )
    let streamer = ImageStreamer(
        session: mockFetcher,
        cache: ImageCache(),
        instrumentation: instrumentation
    )
    return (streamer, gate)
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
