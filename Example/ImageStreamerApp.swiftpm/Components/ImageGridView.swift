import SwiftUI
import ImageStreamer

/// A scrolling grid that demonstrates efficient image loading.
///
/// Key features demonstrated:
/// - **Infinite scrolling**: Loads more images as you scroll
/// - **Prefetching**: Warms the cache for the initial batch
/// - **Lazy loading**: Uses `LazyVGrid` so images load on demand
///
/// Each cell uses `.task(id:)` which automatically cancels
/// when the view scrolls off-screen, preventing wasted bandwidth.
struct ImageGridView: View {
    @Environment(\.imageStreamer) private var imageStreamer
    
    @State private var imageIDs: [Int] = Array(1...50)
    @State private var isLoadingMore = false
    
    private let batchSize = 50

    private let columns = [
        GridItem(.adaptive(minimum: 100, maximum: 150), spacing: 4)
    ]
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(imageIDs, id: \.self) { id in
                    let url = URL(string: "https://picsum.photos/seed/\(id)/400/400")!
                    RemoteImageCell(url: url, index: id)
                        .onAppear {
                            // Trigger load more when near the end
                            if id == imageIDs[imageIDs.count - 20] {
                                loadMoreImages()
                            }
                        }
                }
                
                if isLoadingMore {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding()
                }
            }
            .padding(4)
        }
        .task {
            // Prefetch first batch for instant display
            let prefetchURLs = imageIDs.prefix(batchSize).compactMap { id in
                URL(string: "https://picsum.photos/seed/\(id)/400/400")
            }
            await prefetchImages(urls: prefetchURLs)
        }
    }
    
    private func loadMoreImages() {
        guard !isLoadingMore else { return }
        
        isLoadingMore = true

        Task {
            let nextStart = imageIDs.count + 1
            let newIDs = Array(nextStart...(nextStart + batchSize - 1))
            imageIDs.append(contentsOf: newIDs)
            
            isLoadingMore = false
        }
    }
    
    /// Prefetches images without blocking - warms the cache.
    private func prefetchImages(urls: [URL]) async {
        await withTaskGroup(of: Void.self) { group in
            for url in urls {
                group.addTask {
                    // Fire-and-forget prefetch
                    _ = try? await imageStreamer.image(for: url, pointSize: CGSize(width: 150, height: 150))
                }
            }
        }
    }
}

#Preview {
    ImageGridView()
        .environment(\.imageStreamer, ImageStreamer(
            instrumentation: StandardImageStreamerInstrumentation()
        ))
}
