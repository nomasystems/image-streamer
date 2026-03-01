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

    /// Creates valid JPEG image data for testing.
    static func validJPEGData() -> Data {
        let base64 = "/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAP//////////////////////////////////////////////////////////////////////////////////////wgALCAABAAEBAREA/8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABPxA="
        return Data(base64Encoded: base64) ?? Data()
    }

    /// Creates valid GIF image data for testing.
    static func validGIFData() -> Data {
        let base64 = "R0lGODdhAgACAJEAAAAAAP8AAP///wAAACH5BAkAAAMALAAAAAACAAIAAAICjFMAOw=="
        return Data(base64Encoded: base64) ?? Data()
    }

    /// Creates valid HEIC image data for testing (minimal).
    static func validHEICData() -> Data {
        // Simple valid HEIC generated structure from mac
        let base64 = "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"
        return Data(base64Encoded: base64) ?? Data()
    }

    /// Creates valid WebP image data for testing.
    static func validWebPData() -> Data {
        let base64 = "UklGRiQAAABXRUJQVlA4IBgAAAAwAQCdASoBAAEAAwA0JaQAA3AA/vuUAAA="
        return Data(base64Encoded: base64) ?? Data()
    }

    /// Creates valid SVG image data for testing.
    static func validSVGData() -> Data {
        let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"1\" height=\"1\"></svg>"
        return Data(svg.utf8)
    }

    /// Creates valid PDF data for testing.
    static func validPDFData() -> Data {
        let pdf = "%PDF-1.4\n1 0 obj\n<<>>\nendobj\ntrailer\n<<\n/Root 1 0 R\n>>\n%%EOF"
        return Data(pdf.utf8)
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
    
    func image(for url: URL, pointSize: CGSize?) async throws -> PlatformImage {
        if let error = errorToThrow {
            throw error
        }
        guard let imageToReturn else {
            throw ImageStreamerError.invalidImageData
        }
        return imageToReturn
    }
}
