# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

ImageStreamer is a single-product Swift Package: a concurrency-first image loading/caching library for Apple platforms (iOS 17+, macOS 14+, tvOS 17+, watchOS 10+, visionOS 1+). `swift-tools-version: 6.2`, strict concurrency. No third-party dependencies.

## Commands

Requires an Xcode 15+ / Swift 6.2 toolchain.

```bash
swift build                              # build the library
swift test                               # run the full test suite
swift test --filter ImageStreamerCoreTests        # run one @Suite
swift test --filter "Loads and returns a valid image"  # run one @Test by name
```

Tests use **swift-testing** (`@Suite`/`@Test`/`#expect`), not XCTest. `--filter` matches against suite and test display names (regex).

The example app (`Example/ImageStreamerApp.swiftpm`) is a Swift Playground app, **not** part of `swift build`/`swift test`. Open it in Xcode to run it; it depends on the library via a local `.package(path: "../..")`.

## Architecture

**`ImageStreamer` (actor)** — the coordinator. Its public `image(for:pointSize:)` is `nonisolated` on purpose: the cache lookup is a synchronous "fast path" that never touches actor-isolated state, so cache hits don't serialize through the actor. Only on a miss does it `await` into `fetchAndCoalesce`, which re-checks the cache (another caller may have populated it while suspended) before coalescing or starting a fetch.

**Task coalescing + reference counting** is the heart of the actor and the easiest place to introduce bugs. `activeTasks: [ImageCacheKey: CoalescedTask]` maps a key to one in-flight `Task` plus a `waiterCount`. Concurrent callers for the same key join the existing task instead of starting a new fetch; each increments `waiterCount`. Cancellation is per-caller via `withTaskCancellationHandler` → `handleCancellation`, which decrements `waiterCount` and only cancels the underlying network task when it reaches zero. Two invariants run through this code, guarded by `activeTasks[key]?.task == task` checks everywhere:
- A newer request for the same key may have **replaced** the entry while a task was suspended — never clean up or mutate an entry that isn't still "yours."
- `handleCancellation` runs from an unstructured `Task` at an arbitrary later time, so it must re-validate the entry identity before acting.
Cancelled callers re-throw `CancellationError` (via `Task.checkCancellation()`) rather than leaking the underlying `URLError(.cancelled)`.

**Dual decode path** in `fetchRemoteImage`/`downsample`: with a `pointSize`, ImageIO (`CGImageSourceCreateThumbnailAtIndex`) decodes + downsamples on a background thread, scaled by a per-platform device scale factor. Without one, the full image is decoded and (on UIKit) `byPreparingForDisplay()` is called. This is why format support differs between downsampled and full-size — thumbnail generation only yields the first frame of animated formats and doesn't rasterize vectors.

**`ImageCacheKey`** is `URL` + optional `pointSize`. The pointSize is part of the key so a thumbnail and the full-size image of the same URL are cached as **separate** entries. It's an `NSObject`/`NSCopying` (immutable, `final`, `copy` returns `self`) so it can key `NSCache`.

**`ImageCache`** wraps `NSCache` and is `@unchecked Sendable` (NSCache is documented thread-safe; wrapping avoids a process-wide retroactive `Sendable` conformance). Eviction cost is computed as pixel-area × 4 bytes.

**Instrumentation** is fully decoupled: `ImageStreamerInstrumentation` is its own `Actor` protocol, optional, injected at init. The streamer fires `notify*` calls in detached `Task`s so instrumentation never blocks the loading path. `StandardImageStreamerInstrumentation` broadcasts via per-observer `AsyncStream`s with a **100ms (10Hz) throttle** (`scheduleFlush`) to avoid flooding the UI; updates within a window coalesce into one flush. `reset()` flushes immediately.

**SwiftUI integration** lives at the bottom of `ImageStreamer.swift`: `EnvironmentValues.imageStreamer` and `.instrumentation` via `@Entry`. Because `@Entry` re-evaluates its default on every fallback access, the defaults reference **shared** instances in `ImageStreamerDefaults` (not freshly constructed ones) — this keeps the default streamer wired to the default instrumentation so stats observers see its activity. Don't change these defaults to inline constructors.

**`PlatformImage`** is a typealias bridging `UIImage`/`NSImage`; platform differences (display scale, `byPreparingForDisplay`, CGImage→image construction) are handled with `#if canImport(UIKit)/AppKit` and `os(...)` checks throughout.

## Conventions

- Pure Swift Concurrency — `async`/`await` and actors only. No completion handlers or explicit `DispatchQueue`.
- Everything crossing isolation boundaries is `Sendable`; the public surface sits behind protocols (`ImageStreamerProtocol`, `ImageFetching`, `ImageStreamerInstrumentation`) to keep it injectable/mockable.
- Tests mock the network via the `ImageFetching` protocol. Helpers in `ImageStreamerTests.swift`: `makeStreamer` (single or URL-mapped responses), `makeGatedStreamer` (fetches block on a `RequestGate` so tests can *guarantee* overlapping requests instead of relying on sleeps). Prefer gated mocks over fixed delays when asserting coalescing/cancellation behavior. Mocks live in `Tests/ImageStreamerTests/Mocks/`.
- When public APIs change, update the docs in `Documentation/` (`USAGE.md`, `ADVANCED.md`, `SHOWCASE.md`) and `README.md`.
