import SwiftUI
import ImageStreamer

/// Demonstrates task coalescing by requesting the same image multiple times.
///
/// When multiple views request the same URL simultaneously,
/// ImageStreamer makes only ONE network request and shares
/// the result with all waiting consumers.
///
/// Watch the stats: Network should stay at 1 while Coalesced increases!
struct CoalescingDemoView: View {
    @Environment(\.imageStreamer) private var imageStreamer
    @Environment(\.instrumentation) private var instrumentation
    @State private var isLoading = false
    @State private var stats: ImageStreamerStats?
    
    private let sharedURL = URL(string: "https://picsum.photos/seed/shared/600/600")!
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Task Coalescing Demo")
                    .font(.headline)
                
                Text("All 4 views request the same image simultaneously.\nOnly ONE network request is made.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                
                if let stats {
                    HStack(spacing: 16) {
                        StatItem(title: "Network", value: "\(stats.networkRequests)", color: .blue)
                        StatItem(title: "Coalesced", value: "\(stats.coalescedRequests)", color: .orange)
                    }
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial))
                }
                
                LazyVGrid(columns: [GridItem(), GridItem()], spacing: 8) {
                    ForEach(0..<4, id: \.self) { index in
                        CoalescedImageView(url: sharedURL, consumerID: index, isLoading: $isLoading)
                    }
                }
                
                Button("Reload All (Watch Coalescing)") {
                    Task {
                        await instrumentation?.reset()
                        isLoading = true
                    }
                }
                .buttonStyle(.borderedProminent)
                
                Spacer()
            }
            .padding()
            .navigationTitle("Coalescing")
            .task {
                guard let instrumentation else { return }
                for await newStats in await instrumentation.statsStream {
                    stats = newStats
                }
            }
        }
    }
}

/// A single consumer view that participates in coalesced loading.
struct CoalescedImageView: View {
    let url: URL
    let consumerID: Int
    @Binding var isLoading: Bool
    
    @Environment(\.imageStreamer) private var imageStreamer
    @State private var image: PlatformImage?
    @State private var taskID = UUID()
    
    var body: some View {
        VStack {
            ZStack {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                
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
                } else {
                    ProgressView()
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            
            Text("Consumer \(consumerID)")
                .font(.caption2)
        }
        .task(id: taskID) {
            // All 4 views call this simultaneously
            // ImageStreamer coalesces into single network request
            image = try? await imageStreamer.image(for: url, pointSize: nil)
        }
        .onChange(of: isLoading) { _, newValue in
            if newValue {
                image = nil
                taskID = UUID() // Trigger reload
                isLoading = false
            }
        }
    }
}

#Preview {
    CoalescingDemoView()
        .environment(\.imageStreamer, ImageStreamer(
            instrumentation: StandardImageStreamerInstrumentation()
        ))
}
