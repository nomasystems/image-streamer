import SwiftUI
import ImageStreamer

@main
struct ShowcaseApp: App {
    // Create instrumentation for stats tracking
    private let instrumentation = StandardImageStreamerInstrumentation()
    
    // Create a shared, long-lived instance for the entire app
    // This enables effective caching and task coalescing
    private var imageStreamer: ImageStreamer {
        ImageStreamer(
            session: URLSession.shared,
            cache: NSCache(),
            instrumentation: instrumentation
        )
    }
    
    var body: some Scene {
        WindowGroup {
            TabView {
                ContentView()
                    .tabItem {
                        Label("Grid", systemImage: "square.grid.3x3")
                    }
                
                CoalescingDemoView()
                    .tabItem {
                        Label("Coalescing", systemImage: "arrow.triangle.merge")
                    }
            }
            .environment(\.imageStreamer, imageStreamer)
            .environment(\.instrumentation, instrumentation)
        }
    }
}
