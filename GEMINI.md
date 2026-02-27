# ImageStreamer Project Context

## Project Overview
**ImageStreamer** is a lightweight, high-performance image loading and caching library for Apple platforms (iOS 17+, macOS 14+, tvOS 17+, watchOS 10+, visionOS 1+). It is built entirely with modern Swift Concurrency (`async`/`await`, `actors`) and is optimized for rapidly populating demanding UIs like grids and infinite lists.

### Key Features
- **Task Coalescing**: Automatically merges duplicate concurrent requests for the same URL and size into a single network task.
- **Reference-Counted Cancellation**: Cancels underlying network tasks only when all interested callers have cancelled their requests.
- **Background Decoding & Downsampling**: Uses `ImageIO` to decode and resize images on background threads before they reach the main thread, reducing memory footprint and preventing UI stutters.
- **Smart Caching**: Leverages `NSCache` for thread-safe, auto-pruning in-memory storage.
- **Instrumentation**: Provides a real-time stream of performance statistics (cache hits, network requests, coalesced savings, etc.).

### Architecture
- `ImageStreamer`: A central `actor` that coordinates fetching, coalescing, and caching.
- `ImageCacheKey`: Identifies cached assets by URL and `pointSize` (to cache thumbnails separately from full-size images).
- `ImageStreamerInstrumentation`: Protocol and default implementation for tracking and broadcasting stats via `AsyncStream`.
- `ImageFetching`: Protocol abstraction over `URLSession` to allow easy mocking in tests.

## Building and Running

### Prerequisites
- Xcode 15.0+ or Swift 6.0+ toolchain.
- Target platforms: iOS 17.0+, macOS 14.0+, tvOS 17.0+, watchOS 10.0+, visionOS 1.0+.

### Key Commands
- **Build**: `swift build`
- **Test**: `swift test`
- **Lint/Format**: (Inferred) The project follows standard Swift conventions. Use `swift format` if configured.

### Example Application
The repository includes a Showcase App located at `Example/ImageStreamerApp.swiftpm`. This is a Swift Playground app that demonstrates:
- Grid-based image loading.
- Infinite scrolling performance.
- Real-time instrumentation dashboard.

## Development Conventions

### Coding Style
- **Concurrency**: Exclusively uses `async`/`await` and `actors`. Avoid legacy completion handlers or explicit `DispatchQueue` calls.
- **Strict Typing**: Leverage Swift 6.0's strict concurrency checking. All public protocols and classes are `Sendable` where appropriate.
- **Platform Abstraction**: Uses `PlatformImage` typealias to bridge `UIImage` (UIKit) and `NSImage` (AppKit).

### Testing Practices
- **Framework**: Uses the modern `swift-testing` framework (not XCTest).
- **Mocks**: Dependencies like `ImageFetching` should be mocked using the provided protocols to ensure tests are fast and deterministic.
- **Suite Structure**: Tests are organized into Suites (e.g., `ImageStreamerCoreTests`, `ImageStreamerCachingTests`) using the `@Suite` and `@Test` macros.
- **Async Testing**: Tests are `async` and use `#expect` for assertions.

### Contribution Guidelines
- Ensure all new features are accompanied by unit tests in `Tests/ImageStreamerTests/`.
- Update documentation in the `Documentation/` folder if public APIs change.
- Verify platform compatibility across the supported Apple ecosystem.
