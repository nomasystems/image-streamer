# Usage Guide

This guide covers the basic setup and usage of **ImageStreamer**, focusing on how to integrate it into your SwiftUI applications efficiently.

## Initialization & Injection

`ImageStreamer` provides a SwiftUI environment value for easy access throughout your app. By default, it initializes with a standard `URLSession` and an internal `NSCache`.

You can inject the default instance or configure your own at the root of your application:

```swift
import SwiftUI
import ImageStreamer

@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                // Inject the default ImageStreamer
                .environment(\.imageStreamer, ImageStreamer())
        }
    }
}
```

## Basic Usage in SwiftUI

The most common way to load an image is inside a `.task` modifier. This ensures the request is bound to the view's lifecycle and will be automatically cancelled if the view disappears before the load completes.

```swift
import SwiftUI
import ImageStreamer

struct RemoteImageView: View {
    let url: URL
    
    @Environment(\.imageStreamer) private var imageStreamer
    @State private var image: PlatformImage?
    
    var body: some View {
        Group {
            if let image {
                #if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
                Image(uiImage: image)
                    .resizable()
                #elseif os(macOS)
                Image(nsImage: image)
                    .resizable()
                #endif
            } else {
                ProgressView()
            }
        }
        // Attaching the task to the URL ensures the request is cancelled if the URL changes or the view goes away
        .task(id: url) {
            do {
                image = try await imageStreamer.image(for: url)
            } catch {
                print("Failed to load image: \(error)")
            }
        }
    }
}
```

## Downsampling for Memory Efficiency

When displaying large images in smaller views (like a grid of thumbnails), decoding the full-resolution image wastes memory. `ImageStreamer` supports on-the-fly downsampling using the `pointSize` parameter.

This decodes the image directly to the target size on a background thread, preventing UI stutters and keeping memory footprint low.

```swift
.task(id: url) {
    // Decode the image to a maximum of 150x150 points
    image = try? await imageStreamer.image(
        for: url, 
        pointSize: CGSize(width: 150, height: 150)
    )
}
```

*Note: The `pointSize` takes into account the device's screen scale internally, so you don't need to multiply by `@2x` or `@3x`.*

## Next Steps

- Want to understand how task coalescing or caching works under the hood? See [Advanced Topics](ADVANCED.md).
- Looking for a complete, scrolling grid implementation? Check out the [Showcase App Walkthrough](SHOWCASE.md).
