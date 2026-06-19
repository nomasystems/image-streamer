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
    private nonisolated let cache: ImageCache

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
        cache: ImageCache = ImageCache(),
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
            if let inst = instrumentation {
                Task { await inst.notifyCacheHit() }
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
            if let inst = instrumentation {
                Task { await inst.notifyCacheHit() }
            }
            return cachedImage
        }

        // Check for active tasks - join as a secondary waiter
        if var existingTaskInfo = activeTasks[key] {
            // Increment waiter count first to avoid reentrancy race during await
            existingTaskInfo.waiterCount += 1
            activeTasks[key] = existingTaskInfo

            if let inst = instrumentation {
                Task { await inst.notifyCoalescedRequest() }
            }

            let taskToAwait = existingTaskInfo.task

            return try await withTaskCancellationHandler {
                do {
                    let result = try await taskToAwait.value
                    try Task.checkCancellation()
                    return result
                } catch {
                    // Surface this caller's cancellation as CancellationError rather than
                    // whatever the underlying fetch threw (e.g. URLError(.cancelled)).
                    try Task.checkCancellation()
                    throw error
                }
            } onCancel: { [weak self] in
                Task {
                    await self?.handleCancellation(for: key, task: taskToAwait)
                }
            }
        }

        // No existing task - create the primary task
        if let inst = instrumentation {
            Task { await inst.notifyNetworkRequest() }
        }

        let task = Task { [weak self] () -> PlatformImage in
            guard let self else { throw CancellationError() }
            return try await self.fetchRemoteImage(url: url, pointSize: pointSize)
        }

        activeTasks[key] = CoalescedTask(task: task, waiterCount: 1)

        return try await withTaskCancellationHandler {
            do {
                let result = try await task.value
                try Task.checkCancellation()
                // Primary task completed successfully - clean up.
                // The entry may have been replaced by a newer request for the same key
                // while we were suspended, so only remove it if it is still ours.
                if activeTasks[key]?.task == task {
                    activeTasks[key] = nil
                }
                return result
            } catch {
                // Clean up on error, again only if the entry is still ours
                if activeTasks[key]?.task == task {
                    activeTasks[key] = nil
                }
                // Surface this caller's cancellation as CancellationError rather than
                // whatever the underlying fetch threw (e.g. URLError(.cancelled)).
                try Task.checkCancellation()
                throw error
            }
        } onCancel: { [weak self] in
            Task {
                await self?.handleCancellation(for: key, task: task)
            }
        }
    }



    private func handleCancellation(for key: ImageCacheKey, task: Task<PlatformImage, Error>) {
        // This runs from an unstructured task at an arbitrary later time. The entry for
        // this key may already belong to a newer request, so only act on the entry the
        // cancelled caller was actually waiting on.
        guard var coalescedTask = activeTasks[key], coalescedTask.task == task else { return }

        // Decrement the waiter count
        coalescedTask.waiterCount -= 1

        if coalescedTask.waiterCount <= 0 {
            // No more waiters, cancel the underlying task and remove it
            coalescedTask.task.cancel()
            activeTasks[key] = nil

            // Only track as cancelled when we actually cancel the network request
            if let inst = instrumentation {
                Task { await inst.notifyCancelledTask() }
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
            #if canImport(UIKit) && !os(watchOS)
            if #available(iOS 15.0, tvOS 15.0, *) {
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
        scale = 3.0 // Using highest typical scale statically
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

public protocol Instrumentable: Actor {

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

/// Shared instances backing the environment defaults. `@Entry` expands its default
/// expression into a computed property that is re-evaluated on every fallback access,
/// so the defaults must reference stable shared instances instead of constructing new
/// ones inline. Sharing also keeps the default streamer wired to the default
/// instrumentation, so stats observers see its activity.
private enum ImageStreamerDefaults {
    static let instrumentation = StandardImageStreamerInstrumentation()
    static let streamer = ImageStreamer(instrumentation: instrumentation)
}

public extension EnvironmentValues {
    @Entry var imageStreamer: ImageStreamerProtocol = ImageStreamerDefaults.streamer
    @Entry var instrumentation: ImageStreamerInstrumentation? = ImageStreamerDefaults.instrumentation
}

// MARK: - Image Cache

/// A thread-safe in-memory image cache backed by `NSCache`.
///
/// Owning this wrapper lets the library vouch for its sendability (`NSCache` is
/// documented thread-safe) without declaring a retroactive `Sendable` conformance
/// on `NSCache` itself, which would apply process-wide to every module.
public final class ImageCache: @unchecked Sendable {

    private let storage = NSCache<ImageCacheKey, PlatformImage>()

    public init() {}

    /// The maximum total cost the cache can hold before it starts evicting objects.
    public var totalCostLimit: Int {
        get { storage.totalCostLimit }
        set { storage.totalCostLimit = newValue }
    }

    /// The maximum number of images the cache should hold.
    public var countLimit: Int {
        get { storage.countLimit }
        set { storage.countLimit = newValue }
    }

    public func object(forKey key: ImageCacheKey) -> PlatformImage? {
        storage.object(forKey: key)
    }

    public func setObject(_ image: PlatformImage, forKey key: ImageCacheKey, cost: Int) {
        storage.setObject(image, forKey: key, cost: cost)
    }

    public func removeObject(forKey key: ImageCacheKey) {
        storage.removeObject(forKey: key)
    }

    public func removeAllObjects() {
        storage.removeAllObjects()
    }
}
