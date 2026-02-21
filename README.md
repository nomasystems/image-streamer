# ImageStreamer

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

## Documentation

*   [**Usage Guide**](Documentation/USAGE.md): Setup and basic usage.
*   [**Advanced Topics**](Documentation/ADVANCED.md): Architecture, Performance details, Instrumentation, and Testing.
*   [**Showcase App Walkthrough**](Documentation/SHOWCASE.md): Packed as a Swift Playground app `.swiftpm`. A grid of images with infinite scrolling.

## Installation

### Swift Package Manager

Add `ImageStreamer` to your project via Swift Package Manager:

1.  Open your project in Xcode.
2.  Go to **File > Add Package Dependencies...**
3.  Enter the repository URL: `https://github.com/nomasystems/ImageStreamer.git`
4.  Select the version you want to use.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
