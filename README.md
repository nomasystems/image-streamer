# ImageStreamer

![iOS 17.0+](https://img.shields.io/badge/iOS-17.0%2B-blue)
![macOS 14.0+](https://img.shields.io/badge/macOS-14.0%2B-blue)
![tvOS 17.0+](https://img.shields.io/badge/tvOS-17.0%2B-blue)
![watchOS 10.0+](https://img.shields.io/badge/watchOS-10.0%2B-blue)
![visionOS 1.0+](https://img.shields.io/badge/visionOS-1.0%2B-blue)
![Swift 6.0](https://img.shields.io/badge/Swift-6.2-orange)
![License MIT](https://img.shields.io/badge/License-MIT-green)

**ImageStreamer** is a lightweight, high-efficiency image loading library, built entirely with Swift Concurrency (`async`/`await`).

## Why ImageStreamer?

For high-demanding UI scenarios where you need to fetch many images at the same time, and keep feeding your UI, live, and as fast as possible. For example, building a smooth, infinite-scrolling image grid is harder than it looks. A naive implementation often suffers from:
*   **Scroll Hitching**: Decoding large images on the main thread causes dropped frames.
*   **Memory Spikes**: Loading full-resolution images for thumbnails leads to Out-Of-Memory crashes.
*   **Data Races**: Managing callbacks and state across multiple threads is error-prone.
*   **Redundant Requests**: Requesting the same URL multiple times wastes bandwidth.

**ImageStreamer solves these problems by design.**

It offloads decoding to background threads, automatically downsamples images to save memory, coalesces duplicate requests, and leverages Swift Actors to guarantee thread safety. It's designed to be the robust "engine" behind your image-heavy UI, letting you focus on building beautiful interfaces.

## Features

-   **Native Async/Await**: Clean, readable, and safe code.
-   **Task Coalescing**: Merges duplicate requests for the same URL automatically.
-   **Background Decoding & Downsampling**: smooth scrolling and lesser memory usage.
-   **Smart Caching**: Multi-layer caching including size-aware cache keys.
-   **SwiftUI Ready**: Seamless integration via `EnvironmentValues`.

## Documentation

*   [**Usage Guide**](Documentation/USAGE.md): Setup, Basic Usage, ViewModels, and Error Handling.
*   [**Advanced Topics**](Documentation/ADVANCED.md): Architecture, Performance details, Instrumentation, and Testing.
*   [**Showcase App Walkthrough**](Documentation/SHOWCASE.md): See how to build a production-quality grid with prefetching and cancellation.
*   **Try the Playground App**: (Quit Xcode first!) Go to the `Example` folder and open `ImageStreamerSampleApp.swifpm` on Xcode. You'll find a code implementation of `ImageStreamer` with production-like examples that you can preview, build, and run.

## Installation

### Swift Package Manager

Add `ImageStreamer` to your project via Swift Package Manager:

1.  Open your project in Xcode.
2.  Go to **File > Add Package Dependencies...**
3.  Enter the repository URL.
4.  Select the version you want to use.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
