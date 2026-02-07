import SwiftUI
import ImageStreamer

/// Main view demonstrating ImageStreamer in a scrolling grid.
///
/// This showcase demonstrates:
/// - Efficient image loading with automatic task cancellation
/// - Memory-efficient downsampling via `pointSize`
/// - Cache performance monitoring
///
/// See `ImageGridView` for the grid implementation and
/// `RemoteImageCell` for individual cell loading logic.
struct ContentView: View {
    @Environment(\.instrumentation) private var instrumentation
    @State private var stats: ImageStreamerStats?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ImageGridView()
                StatsView(stats: stats)
            }
            .navigationTitle("ImageStreamer Demo")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Reset Stats") {
                        Task {
                            await instrumentation?.reset()
                        }
                    }
                }
            }
            .task {
                guard let instrumentation else { return }
                for await newStats in await instrumentation.statsStream {
                    stats = newStats
                }
            }
        }
    }
}

#Preview {
    ContentView()
        .environment(\.imageStreamer, ImageStreamer(
            session: URLSession.shared,
            cache: NSCache(),
            instrumentation: StandardImageStreamerInstrumentation()
        ))
}
