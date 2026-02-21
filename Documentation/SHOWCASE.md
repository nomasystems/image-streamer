# Showcase App Walkthrough

The `ImageStreamer` repository includes a fully-functional Swift Playground app (`Example/ImageStreamerApp.swiftpm`) that demonstrates the library's capabilities in a real-world scenario.

This app features a grid with an infinite scrolling feed of images, live performance statistics, and simulated high-speed scrolling conditions.

## App Architecture

The Showcase App is structured around a few key components:
- **`ContentView.swift`**: The main view that houses the grid and the stats overlay.
- **`ImageGridView.swift`**: A `LazyVGrid` implementation handling batch loading and pagination.
- **`RemoteImageCell.swift`**: The individual view responsible for fetching formatting each image.
- **`StatsView.swift`**: A real-time data visualizer over the grid.

## The Grid: `ImageGridView`

The `ImageGridView` handles displaying many images at once and fetching more as the user scrolls.

### Infinite Scrolling and Prefetching

1. **Lazy Loading**: `LazyVGrid` ensures cells are only constructed when they are about to become visible.
2. **Batch Generation**: The app generates arrays of integers to be appended to `imageIDs`, which then mapped to URLs.
3. **Triggering the Load**: At the end of the `LazyVGrid`, the `.onAppear` modifier checks if the current item is near the end of the array, and triggers `loadMoreImages()` to append the next batch.
4. **Prefetching**: When the grid first appears, it initiates fire-and-forget prefetch requests. It uses a `withTaskGroup` block, instructing `ImageStreamer` to pull images in bulk. These tasks simply drop the result to pre-warm the internal `NSCache` so when cells ultimately request these images, they will render instantly.

## The Cell: `RemoteImageCell`

This view is where the core magic of `ImageStreamer`'s API shines through.

```swift
.task(id: url) {
    await loadImage()
}
```

The `loadImage` function calls the central streamer requesting a `pointSize(width: 150, height: 150)`. 

### Automatic Cancellation in Action

When a user scrolls fast, `LazyVGrid` will create and destroy `RemoteImageCell` instances rapidly. The `.task(id: url)` automatically stops the execution context when the cell moves off-screen. `ImageStreamer` listens for this task cancellation. It will stop the active network fetch instantly unless another on-screen view is also waiting for the identical URL and point size.

You can observe this by scrolling very quickly through the app while watching the **"Cancelled Networks"** counter tick upward in the `StatsView`.

## Monitoring Performance: `StatsView`

The application initializes its environment with a `StandardImageStreamerInstrumentation` object. `ContentView` subscribes to the `statsStream` continuously in a `.task` and binds the latest structural snapshot to a `@State` variable `stats`.

This lightweight, non-blocking UI passes the state downstream to a small floating overlay.

### Metrics Explained
- **Cache Hits**: Images served instantly without crossing the actor boundary to the network logic.
- **Network Requests**: Original fetching calls executed against the `URLSession` tier.
- **Coalesced Savings**: Shows when two or more cells requested the same image simultaneously, combining into single network fetch.
- **Cancelled Networks**: Shows how much data and CPU power you saved entirely because the user scrolled past an image before the fetch could complete.
