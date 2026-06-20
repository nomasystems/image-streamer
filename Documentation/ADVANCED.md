# Advanced Topics

When building high-performance or complex UIs, standard image loading strategies often fall short. Grid views load dozens of images concurrently, users scroll rapidly dropping unfinished requests, and identical images may be requested by different views simultaneously. 

`ImageStreamer` provides a robust, thread-safe, and highly-concurrent architecture to handle these challenges effortlessly.

## Concurrency Architecture

The library is built around a central `actor` that acts as the coordinator for all fetching requests. Actors guarantee isolated state, which eliminates race conditions around reading and writing to underlying storage arrays without requiring explicit locks or queues.

### Task Coalescing

When multiple views request the exact same image (URL and point size) concurrently, `ImageStreamer` ensures only a single network request is made. 

1. **Initial Request**: The first caller triggers a primary `Task` that goes out to the network.
2. **Secondary Waiters**: If another caller requests the same image before the primary task finishes, the `ImageStreamer` actor adds them as a "waiter" and serves the result of the primary task once it completes.

This mechanism drastically reduces redundant network traffic and server load.

### Pre-emptive Task Cancellation & Reference Counting

In infinite scroll scenarios, views frequently move off-screen before their images finish loading. Swift Concurrency's `.task` automatically signals cancellation. `ImageStreamer` leverages a reference-counting mechanism integrated with `withTaskCancellationHandler`:

- Each coalesced request increments a "waiter count".
- When a view's task is cancelled, the actor decrements its waiter count.
- If (and only if) the waiter count reaches 0, the underling primary `Task` is explicitly cancelled, saving bandwidth and CPU cycles.

## Caching Strategy

`ImageStreamer` uses an `ImageCache`, a lightweight thread-safe wrapper around `NSCache`. This offers key advantages:
- Thread-safe access.
- Automatic, system-level pruning when memory is low (preventing OOM crashes).
- Cost-based eviction (calculated based on the image's pixel count or size in memory).

### Caching Point Sizes Independently

Because downsampling is a core feature, a thumbnail and a full-size version of the same remote image are treated as distinct assets. They are stored under a combined `ImageCacheKey` (consisting of the URL and the target `pointSize`). Requesting a thumbnail will not inadvertently serve a giant image to a small UI element.

## Performance Monitoring (Instrumentation)

You can monitor the efficiency of the streamer by observing real-time statistics. This is incredibly useful during debugging or optimization phases.

The `ImageStreamer` conforming to `Instrumentable` exposes an `AsyncStream<ImageStreamerStats>`. To use this:

1. Initialize `ImageStreamer` with an instrumentation object (e.g., `StandardImageStreamerInstrumentation()`).
2. Read from `statsStream` continuously in a global or high-level `.task`.

```swift
.task {
    guard let instrumentation = imageStreamer.instrumentation else { return }
    for await currentStats in await instrumentation.statsStream {
        print("Cache Hits: \(currentStats.cacheHits)")
        print("Network Requests: \(currentStats.networkRequests)")
        print("Coalesced Savings: \(currentStats.coalescedRequests)")
        print("Cancelled Networks: \(currentStats.cancelledTasks)")
    }
}
```

*Note: The `StandardImageStreamerInstrumentation` throttles UI updates to ~10Hz, so observing these stats directly in SwiftUI state variables will not block your main thread.*

## Customization and Dependency Injection

The entire `ImageStreamer` sits behind protocols (`ImageStreamerProtocol`, `ImageFetching`), which makes it simple to provide your own caches or mock networks for unit testing.

```swift
public init(
    session: ImageFetching = URLSession.shared,
    cache: ImageCache = ImageCache(),
    instrumentation: ImageStreamerInstrumentation? = nil
)
```

For instance, you might want to create an `ImageFetching` layer that attaches Auth tokens, applies custom retry logic, or pulls from a local disk cache before hitting `URLSession`.

## Image Decoding & Format Support

`ImageStreamer` relies on native system decoders. The level of support varies depending on whether the image is downsampled.

### Decoding Paths

1.  **Downsampling Path (`pointSize` provided)**:
    Uses `CGImageSourceCreateThumbnailAtIndex` (`ImageIO`). This is the most memory-efficient way to load large images into small thumbnails but is strictly limited to raster formats.
    -   **Raster**: Fully supported (JPEG, PNG, HEIC, WebP, etc.).
    -   **GIFs**: Decodes the **first frame only**.
    -   **Vector (SVG/PDF)**: Not supported in this path. `ImageIO` cannot rasterize raw vector data during downsampling.

2.  **Full-Size Path (`pointSize` is `nil`)**:
    Uses platform-native initializers like `UIImage(data:)` or `NSImage(data:)`.
    -   **Raster**: Broadly supported.
    -   **Vector (SVG/PDF)**: Support is OS-dependent. While modern versions of iOS/macOS have added native SVG support, downloading raw SVG/PDF data and initializing a `PlatformImage` directly can be inconsistent compared to using Asset Catalogs.

### Recommendations

-   **WebP/AVIF**: These are excellent choices for modern Apple platforms (iOS 14+/16+ respectively) due to their high compression efficiency.
-   **SVGs**: If your app relies heavily on SVGs from remote URLs, consider a specialized SVG library or ensuring they are handled without `pointSize` constraints, though native results may vary.
