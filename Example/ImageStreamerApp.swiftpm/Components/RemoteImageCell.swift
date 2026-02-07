import SwiftUI
import ImageStreamer

/// A single image cell that loads from a remote URL.
///
/// This demonstrates the core ImageStreamer usage pattern:
///
/// ```swift
/// .task(id: url) {
///     image = try? await imageStreamer.image(
///         for: url,
///         pointSize: CGSize(width: 150, height: 150)
///     )
/// }
/// ```
///
/// **Key behaviors:**
/// - `.task(id:)` automatically cancels when scrolling away
/// - `pointSize` enables memory-efficient downsampling
/// - Loading states provide visual feedback
struct RemoteImageCell: View {
    let url: URL
    let index: Int
    
    @Environment(\.imageStreamer) private var imageStreamer
    @State private var image: PlatformImage?
    @State private var loadState: LoadState = .idle
    
    enum LoadState {
        case idle
        case loading
        case loaded
        case failed
    }
    
    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.gray.opacity(0.2))
            
            switch loadState {
            case .idle, .loading:
                ProgressView()
                    .scaleEffect(0.8)
            case .loaded:
                if let image {
                    #if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                    #elseif os(macOS)
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                    #endif
                }
            case .failed:
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        // .task automatically cancels when view scrolls off-screen
        .task(id: url) {
            await loadImage()
        }
    }
    
    private func loadImage() async {
        loadState = .loading
        
        do {
            // Request with point size for efficient downsampling
            let loadedImage = try await imageStreamer.image(
                for: url,
                pointSize: CGSize(width: 150, height: 150)
            )
            
            // Check for cancellation before updating state
            try Task.checkCancellation()
            
            if let loadedImage {
                image = loadedImage
                loadState = .loaded
            } else {
                loadState = .failed
            }
        } catch is CancellationError {
            // Task was cancelled (view scrolled away)
            loadState = .idle
        } catch {
            loadState = .failed
        }
    }
}

#Preview {
    RemoteImageCell(
        url: URL(string: "https://picsum.photos/seed/preview/400/400")!,
        index: 1
    )
    .frame(width: 150, height: 150)
    .environment(\.imageStreamer, ImageStreamer())
}
