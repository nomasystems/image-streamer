# ImageStreamer

![Version](https://img.shields.io/github/v/tag/nomasystems/image-streamer?label=version)
![iOS 17.0+](https://img.shields.io/badge/iOS-17.0%2B-blue)
![macOS 14.0+](https://img.shields.io/badge/macOS-14.0%2B-blue)
![tvOS 17.0+](https://img.shields.io/badge/tvOS-17.0%2B-blue)
![watchOS 10.0+](https://img.shields.io/badge/watchOS-10.0%2B-blue)
![visionOS 1.0+](https://img.shields.io/badge/visionOS-1.0%2B-blue)
![Swift 6.0](https://img.shields.io/badge/Swift-6.2-orange)
![License MIT](https://img.shields.io/badge/License-MIT-green)

**ImageStreamer** is a lightweight, high-efficiency image loading library, built entirely with Swift Concurrency (`async`/`await`).

## Features

-   **Task Coalescing**: Merges duplicate requests for the same URL automatically.
-   **Task Cancellation**: Cancel requests when they're no longer needed.
-   **Background Decoding & Downsampling**: smooth scrolling and lesser memory usage.
-   **Smart Caching**: `NSCache`, light, thread-safe, and gracefully prunes itself —It won't crash your app with an Out-of-Memory (OOM) error
-   **Native Async/Await**: Clean, readable, and safe code.
-   **SwiftUI Ready**: Seamless integration via `EnvironmentValues`.

## Supported Formats

ImageStreamer leverages native system decoders. Support depends on whether you are using **downsampling** (`pointSize` parameter).

| Format | Downsampled | Full-Size |
| :--- | :--- | :--- |
| **Raster** (JPEG, PNG, HEIC, WebP) | ✅ Full Support | ✅ Full Support |
| **GIF** | ⚠️ First frame only | ✅ Full Support |
| **Vector** (SVG, PDF) | ❌ Not Supported | ⚠️ OS-Dependent |

For more technical details, see the [Advanced Topics](Documentation/ADVANCED.md#image-decoding--format-support) section.

## Documentation

*   [**Usage Guide**](Documentation/USAGE.md): Setup and basic usage.
*   [**Advanced Topics**](Documentation/ADVANCED.md): Architecture, Performance details, Instrumentation, and Testing.
*   [**Showcase App Walkthrough**](Documentation/SHOWCASE.md): Packed as a Swift Playground app `.swiftpm`. A grid of images with infinite scrolling.

## Installation

Add `ImageStreamer` to the `dependencies` value of your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/nomasystems/image-streamer.git", from: "1.0.1")
]

```

Then, add the package product to your target's dependencies:

```swift
targets: [
    .target(
        name: "YourApp",
        dependencies: ["ImageStreamer"]
    )
]
```

---

### Via Xcode

1. Open your project in Xcode.
2. Go to **File > Add Package Dependencies...**
3. Enter the repository URL: `https://github.com/nomasystems/image-streamer.git`
4. Set the **Dependency Rule** to **Up to Next Major Version** and enter `1.0.1`.
5. Select the project target where you want to use the library.

---

### Customization and Dependency Injection

The entire `ImageStreamer` sits behind protocols (`ImageStreamerProtocol`, `ImageFetching`), which makes it simple to provide your own caches or mock networks for unit testing.

```swift
public init(
    session: ImageFetching = URLSession.shared,
    cache: NSCache<ImageCacheKey, PlatformImage> = NSCache(),
    instrumentation: ImageStreamerInstrumentation? = nil
)
```

For instance, you might want to create an `ImageFetching` layer that attaches Auth tokens, applies custom retry logic, or pulls from a local disk cache before hitting `URLSession`.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
