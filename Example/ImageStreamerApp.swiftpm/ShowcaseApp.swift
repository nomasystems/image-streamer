import SwiftUI
import ImageStreamer

@main
struct ShowcaseApp: App {
    // Create instrumentation for stats tracking
    private let instrumentation: StandardImageStreamerInstrumentation

    // A single, long-lived instance shared by the entire app.
    // Stored (not computed) so the cache and task coalescing survive body re-evaluations.
    private let imageStreamer: ImageStreamer

    init() {
        let instrumentation = StandardImageStreamerInstrumentation()
        self.instrumentation = instrumentation
        self.imageStreamer = ImageStreamer(
            session: URLSession.shared,
            instrumentation: instrumentation
        )
    }


    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.imageStreamer, imageStreamer)
                .environment(\.instrumentation, instrumentation)
        }
    }
}
