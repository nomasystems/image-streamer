import SwiftUI
import ImageStreamer

/// Displays ImageStreamer statistics in a compact footer bar.
///
/// Shows cache hits, network requests, coalesced requests,
/// and cancelled tasks to help visualize the library's efficiency.
struct StatsView: View {
    let stats: ImageStreamerStats?
    
    var body: some View {
        HStack(spacing: 24) {
            StatItem(title: "Cache Hits", value: "\(stats?.cacheHits ?? 0)", color: .green)
            Spacer()
            StatItem(title: "Network", value: "\(stats?.networkRequests ?? 0)", color: .blue)
            Spacer()
            StatItem(title: "Coalesced", value: "\(stats?.coalescedRequests ?? 0)", color: .orange)
            Spacer()
            StatItem(title: "Cancelled", value: "\(stats?.cancelledTasks ?? 0)", color: .red)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }
}

/// A single statistic display with a colored value and label.
struct StatItem: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2.bold())
                .foregroundStyle(color)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    VStack {
        Spacer()
        StatsView(stats: ImageStreamerStats(
            cacheHits: 42,
            networkRequests: 15,
            coalescedRequests: 8,
            cancelledTasks: 3
        ))
    }
}
