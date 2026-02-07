import ImageStreamer
import Foundation

// MARK: - Mock ImageFetcher for Testing

/// A configurable mock for `ImageFetching` that allows testing various scenarios.
struct MockImageFetcher: ImageFetching {
    
    /// The result to return when `data(from:)` is called.
    var result: Result<(Data, URLResponse), Error>
    
    /// Optional delay to simulate network latency.
    var delay: Duration?
    
    /// Tracks URLs that were requested (for verification in tests).
    /// Using an actor to ensure thread-safe access.
    private let requestTracker: RequestTracker?
    
    init(
        result: Result<(Data, URLResponse), Error>,
        delay: Duration? = nil,
        requestTracker: RequestTracker? = nil
    ) {
        self.result = result
        self.delay = delay
        self.requestTracker = requestTracker
    }
    
    func data(from url: URL) async throws -> (Data, URLResponse) {
        await requestTracker?.recordRequest(for: url)
        
        if let delay {
            try await Task.sleep(for: delay)
        }
        
        switch result {
        case .success(let tuple):
            return tuple
        case .failure(let error):
            throw error
        }
    }
}

// MARK: - Request Tracker

/// An actor to track network requests in a thread-safe manner.
actor RequestTracker {
    private(set) var requestedURLs: [URL] = []
    
    func recordRequest(for url: URL) {
        requestedURLs.append(url)
    }
    
    func requestCount(for url: URL) -> Int {
        requestedURLs.filter { $0 == url }.count
    }
    
    func reset() {
        requestedURLs.removeAll()
    }
}

// MARK: - Mock Image Data Helpers

enum MockImageData {
    /// Creates valid PNG image data for testing.
    static func validPNGData() -> Data {
        // Minimal valid 1x1 red PNG
        let pngData: [UInt8] = [
            0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG signature
            0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, // IHDR chunk
            0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
            0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53,
            0xDE, 0x00, 0x00, 0x00, 0x0C, 0x49, 0x44, 0x41,
            0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
            0x00, 0x00, 0x03, 0x00, 0x01, 0x00, 0x05, 0xFE,
            0xD4, 0xEF, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45,
            0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82
        ]
        return Data(pngData)
    }
    
    /// Creates invalid image data that cannot be decoded.
    static func invalidData() -> Data {
        return Data("not an image".utf8)
    }
    
    /// Creates a successful HTTP response.
    static func successResponse(for url: URL, statusCode: Int = 200) -> URLResponse {
        HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
    }
}

// MARK: - Mock Loader Protocol Implementation

/// A simple mock implementation of `ImageLoaderProtocol` for testing ViewModels.
struct MockImageLoader: ImageStreamerProtocol {
    var imageToReturn: PlatformImage?
    var errorToThrow: Error?
    
    func image(for url: URL, pointSize: CGSize?) async throws -> PlatformImage? {
        if let error = errorToThrow {
            throw error
        }
        return imageToReturn
    }
}
