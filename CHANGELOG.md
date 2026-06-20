# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed
- **Background Decoding Guarantee**: `downsample` and `fetchRemoteImage` are now marked `@concurrent`, ensuring image decoding always runs on the cooperative thread pool even when the `NonisolatedNonsendingByDefault` language mode is active.
- **Coalescing Race**: Cleanup and cancellation bookkeeping now verify task identity before touching the active-task table, preventing a stale cancellation handler from cancelling a newer, unrelated request for the same URL.
- **Cancellation Error Normalization**: Cancelled requests now consistently throw `CancellationError`, even when the underlying `URLSession` surfaces `URLError(.cancelled)`.
- **Idle Instrumentation Wakeups**: `StandardImageStreamerInstrumentation` no longer runs a permanent 10Hz polling task; broadcasts are scheduled on demand (still throttled to ~10Hz under load).
- **Environment Defaults**: The `\.imageStreamer` and `\.instrumentation` environment defaults now share stable instances wired to each other, instead of constructing disconnected instances on each fallback access.

### Changed
- **BREAKING — Cache Type**: `ImageStreamer.init` now takes an `ImageCache` (a thread-safe wrapper the library owns) instead of `NSCache<ImageCacheKey, PlatformImage>`. The retroactive `@unchecked Sendable` conformance on `NSCache`, which applied process-wide, has been removed.
- **Test Determinism**: Coalescing tests now use a gated mock fetcher instead of fixed delays, removing timing dependence.

## [1.0.1] - 2026-03-01

### Added
- **Comprehensive Image Format Testing**: Added unit tests for JPEG, PNG, HEIC, WebP, GIF, SVG, and PDF to ensure platform-specific decoding reliability.
- **Detailed Format Support Documentation**: Added a "Supported Formats" matrix to the README and expanded the Advanced Documentation with platform-specific insights.

### Fixed
- **watchOS Simulator Compatibility**: Addressed `invalidImageData` errors on watchOS simulators by improving how the library handles image decoders and providing clearer guidance on platform limitations.
- **Test Stability**: Fixed invalid HEIC mock data that was causing false negatives in some test environments.

### Changed
- Reorganized README for better readability of installation and features.

## [1.0.0] - 2026-02-27

### Added
- **Core ImageStreamer Engine**: Initial stable release with Task Coalescing, Reference-Counted Cancellation, and Background Decoding.
- **Smart Caching**: `NSCache` integration for thread-safe, auto-pruning in-memory storage.
- **Instrumentation**: Real-time performance statistics stream via `AsyncStream`.
- **Platform Support**: iOS 17+, macOS 14+, tvOS 17+, watchOS 10+, visionOS 1+.
- **Comprehensive Documentation**: Added Usage, Advanced, and Showcase walkthroughs.

[1.0.1]: https://github.com/nomasystems/image-streamer/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/nomasystems/image-streamer/releases/tag/v1.0.0
