import ImageStreamer
import Foundation

/// A mock fetcher that returns different responses based on the requested URL.
struct URLMappingMockFetcher: ImageFetching {
    let responses: [URL: Result<(Data, URLResponse), Error>]
    let delay: Duration?
    let requestTracker: RequestTracker?

    func data(from url: URL) async throws -> (Data, URLResponse) {
        await requestTracker?.recordRequest(for: url)

        if let delay {
            try await Task.sleep(for: delay)
        }

        guard let result = responses[url] else {
            throw URLError(.fileDoesNotExist)
        }

        switch result {
        case .success(let tuple):
            return tuple
        case .failure(let error):
            throw error
        }
    }
}
