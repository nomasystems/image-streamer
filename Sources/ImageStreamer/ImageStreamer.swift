import Foundation
import ImageIO
import SwiftUI

#if canImport(UIKit)
import UIKit
public typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
public typealias PlatformImage = NSImage
#else
    #error("Unsupported platform")
#endif

/// Protocol to abstract the actual network fetching.
/// This allows us to inject mock loaders for unit testing.
public protocol ImageFetching: Sendable {
    func data(from url: URL) async throws -> (Data, URLResponse)
}

/// Default implementation using URLSession
extension URLSession: ImageFetching {}

public enum ImageStreamerError: Error {
    case invalidImageData
    case invalidURL

    var identifier: String {
        switch self {
        case .invalidImageData: return "invalidImageData"
        case .invalidURL: return "invalidURL"
        }
    }
}

/// Protocol defining the image loading interface.
public protocol ImageStreamerProtocol: Sendable {
    /// Fetches an image for the provided `URL`.
    /// - Parameters:
    ///   - url: The URL of the image to fetch.
    ///   - pointSize: The desired size in points. If provided, the image is downsampled to this size to save memory.
    /// - Returns: The PlatformImage if successful. Throws errors on network or decoding failure.
    func image(for url: URL, pointSize: CGSize?) async throws -> PlatformImage
}

// Default implementation for convenience
public extension ImageStreamerProtocol {
    func image(for url: URL) async throws -> PlatformImage {
        try await image(for: url, pointSize: nil)
    }
}

/// Tracks an active task along with how many callers are waiting on it.
private struct CoalescedTask {
    let task: Task<PlatformImage, Error>
    var waiterCount: Int
}

/// A high-efficiency image streamer designed for rapidly populating high demanding UIs.
/// Features: Task coalescing, NSCache integration.
public actor ImageStreamer: ImageStreamerProtocol, Instrumentable {

    public nonisolated let instrumentation: ImageStreamerInstrumentation?

    // MARK: - Dependencies
    private nonisolated let session: ImageFetching
    private nonisolated let cache: NSCache<ImageCacheKey, PlatformImage>

    private var activeTasks: [ImageCacheKey: CoalescedTask] = [:]

    // MARK: - Initialization

    /// Initializes the ImageStreamer service.
    ///
    /// - Parameters:
    ///   - session: The network session to use. Defaults to `URLSession.shared`.
    ///   - cache: The cache instance.
    ///   - instrumentation: Optional instrumentation for collecting statistics.
    public init(
        session: ImageFetching = URLSession.shared,
        cache: NSCache<ImageCacheKey, PlatformImage> = NSCache<ImageCacheKey, PlatformImage>(),
        instrumentation: ImageStreamerInstrumentation? = nil
    ) {
        self.session = session
        self.cache = cache
        self.instrumentation = instrumentation
    }

    // MARK: - ImageLoaderProtocol API

    public nonisolated func image(for url: URL, pointSize: CGSize?) async throws -> PlatformImage {
        let key = ImageCacheKey(url: url, pointSize: pointSize)

        // Fast path: Check cache without entering actor serialization
        if let cachedImage = self.cache.object(forKey: key) {
            Task { [weak self] in
                await self?.instrumentation?.notifyCacheHit()
            }
            return cachedImage
        }

        // Slow path: Enter actor to coalesce requests or fetch
        return try await fetchAndCoalesce(url: url, pointSize: pointSize, key: key)
    }

    // MARK: - Private Helpers

    private func fetchAndCoalesce(url: URL, pointSize: CGSize?, key: ImageCacheKey) async throws -> PlatformImage {

        // Double-check cache in case another task populated it while we were waiting to enter the actor
        if let cachedImage = self.cache.object(forKey: key) {
            await instrumentation?.notifyCacheHit()
            return cachedImage
        }

        // Check for active tasks - join as a secondary waiter
        if var existingTaskInfo = activeTasks[key] {
            // Increment waiter count first to avoid reentrancy race during await
            existingTaskInfo.waiterCount += 1
            activeTasks[key] = existingTaskInfo

            Task {
                await instrumentation?.notifyCoalescedRequest()
            }

            let taskToAwait = existingTaskInfo.task

            return try await withTaskCancellationHandler {
                let result = try await taskToAwait.value
                try Task.checkCancellation()
                return result
            } onCancel: { [weak self] in
                Task {
                    await self?.handleCancellation(for: key)
                }
            }
        }

        // No existing task - create the primary task
        Task {
            await instrumentation?.notifyNetworkRequest()
        }

        let task = Task.detached { [weak self] () -> PlatformImage in
            guard let self else { throw CancellationError() }
            return try await self.fetchRemoteImage(url: url, pointSize: pointSize)
        }

        activeTasks[key] = CoalescedTask(task: task, waiterCount: 1)

        return try await withTaskCancellationHandler {
            do {
                let result = try await task.value
                // Primary task completed successfully - clean up
                activeTasks[key] = nil
                return result
            } catch {
                // Clean up on error
                activeTasks[key] = nil
                throw error
            }
        } onCancel: { [weak self] in
            Task {
                await self?.handleCancellation(for: key)
            }
        }
    }



    private func handleCancellation(for key: ImageCacheKey) {
        guard var coalescedTask = activeTasks[key] else { return }

        // Decrement the waiter count
        coalescedTask.waiterCount -= 1

        if coalescedTask.waiterCount <= 0 {
            // No more waiters, cancel the underlying task and remove it
            coalescedTask.task.cancel()
            activeTasks[key] = nil
            
            // Only track as cancelled when we actually cancel the network request
            Task { [weak self] in
                await self?.instrumentation?.notifyCancelledTask()
            }
        } else {
            // Still have waiters, keep the task alive - don't count as cancelled
            activeTasks[key] = coalescedTask
        }
    }

    private nonisolated func fetchRemoteImage(url: URL, pointSize: CGSize?) async throws -> PlatformImage {

        try Task.checkCancellation()

        let (data, response) = try await session.data(from: url)

        // Basic HTTP status code check
        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            throw URLError(.badServerResponse)
        }

        try Task.checkCancellation()

        let image: PlatformImage?
        if let pointSize = pointSize {
            image = await downsample(imageData: data, to: pointSize)
        } else {
            let rawImage = PlatformImage(data: data)
            #if canImport(UIKit)
            if #available(iOS 15.0, tvOS 15.0, watchOS 8.0, *) {
                image = await rawImage?.byPreparingForDisplay() ?? rawImage
            } else {
                image = rawImage
            }
            #else
            image = rawImage
            #endif
        }

        if let image {
            #if canImport(UIKit)
            let scale = image.scale
            #else
            let scale: CGFloat = 1.0
            #endif
            let cost = Int((image.size.width * scale) * (image.size.height * scale) * 4)
            cache.setObject(image, forKey: ImageCacheKey(url: url, pointSize: pointSize), cost: cost)

            return image
        } else {
            throw ImageStreamerError.invalidImageData
        }
    }

    private nonisolated func downsample(imageData: Data, to pointSize: CGSize) async -> PlatformImage? {
        // Create an image source without decoding immediately
        let imageSourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let imageSource = CGImageSourceCreateWithData(imageData as CFData, imageSourceOptions) else {
            return nil
        }

        let scale: CGFloat
        #if os(watchOS)
        scale = 1.0
        #elseif os(visionOS)
        scale = 2.0
        #elseif canImport(UIKit)
        scale = 3.0 // Using highest typical scale statically to avoid MainActor hop
        #elseif canImport(AppKit)
        scale = 2.0
        #else
        scale = 1.0
        #endif

        // Calculate the max pixel size needed
        let maxDimensionInPixels = max(pointSize.width, pointSize.height) * scale

        let downsampleOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true, // Force decoding now, on background
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimensionInPixels
        ] as CFDictionary

        guard let downsampledCGImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, downsampleOptions) else {
            return nil
        }

        #if canImport(UIKit)
        return UIImage(cgImage: downsampledCGImage)
        #elseif canImport(AppKit)
        return NSImage(cgImage: downsampledCGImage, size: pointSize)
        #else
        return nil
        #endif
    }
}

// MARK: - Convenience API

public extension ImageStreamer {

    /// Convenience method to load an image from a URL string.
    /// Useful when resource identifiers are passed as strings (e.g., from JSON responses).
    func image(for urlString: String, pointSize: CGSize? = nil) async throws -> PlatformImage {
        guard let url = URL(string: urlString, encodingInvalidCharacters: false) else {
            let error = ImageStreamerError.invalidURL
            throw error
        }
        return try await self.image(for: url, pointSize: pointSize)
    }
}

// MARK: - Public instrumentation API

public protocol Instrumentable: Sendable, Actor {

    nonisolated var instrumentation: ImageStreamerInstrumentation? { get }

    /// A stream of statistics updates.
    /// If no instrumentation was provided during initialization, this stream yields nothing.
    var statsStream: AsyncStream<ImageStreamerStats> { get async }

    /// Resets the statistics to zero.
    func resetStats() async
}

extension Instrumentable {
    public var statsStream: AsyncStream<ImageStreamerStats> {
        get async {
            await instrumentation?.statsStream ?? AsyncStream { _ in }
        }
    }

    public func resetStats() async {
        await instrumentation?.reset()
    }
}

// MARK: - SwiftUI Environment Integration

public extension EnvironmentValues {
    @Entry var imageStreamer: ImageStreamerProtocol = ImageStreamer()
    @Entry var instrumentation: ImageStreamerInstrumentation? = StandardImageStreamerInstrumentation()
}

// Retroactive conformance to allow usage in nonisolated contexts.
// NSCache is thread-safe documentation-wise.
extension NSCache: @retroactive @unchecked Sendable {}
