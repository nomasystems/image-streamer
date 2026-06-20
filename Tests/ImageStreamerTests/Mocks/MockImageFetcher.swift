import ImageStreamer
import Foundation
import CoreGraphics
import ImageIO

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Cross-platform helper to extract a `CGImage` from a `PlatformImage`.
///
/// `UIImage.cgImage` is a stored optional, but `NSImage` exposes a `cgImage(forProposedRect:context:hints:)`
/// method instead - so tests must not touch `image.cgImage` directly if they are to build on every platform.
func extractCGImage(from image: PlatformImage) -> CGImage? {
    #if canImport(UIKit)
    return image.cgImage
    #elseif canImport(AppKit)
    return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    #else
    return nil
    #endif
}

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

    /// Creates a solid-color PNG of the given square `dimension` (default 512×512).
    ///
    /// Unlike `validPNGData()` (a 1×1 pixel), this is large enough to actually be
    /// downsampled, so tests can assert that the downsample path produces a smaller
    /// image instead of just checking that *some* image came back.
    static func largePNGData(dimension: Int = 512) -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: dimension,
            height: dimension,
            bitsPerComponent: 8,
            bytesPerRow: dimension * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return Data()
        }

        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: dimension, height: dimension))

        guard let cgImage = context.makeImage() else { return Data() }

        let encoded = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            encoded, "public.png" as CFString, 1, nil
        ) else {
            return Data()
        }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else { return Data() }

        return encoded as Data
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

    /// Creates valid HEIC image data for testing.
    static func validHEICData() -> Data {
        // A fully valid 2x2 red pixel HEIC image (verified to round-trip via NSImage/UIImage)
        let base64 = "AAAAJGZ0eXBoZWljAAAAAG1pZjFNaVBybWlhZk1pSEJoZWljAAAJSG1ldGEAAAAAAAAAIWhkbHIAAAAAAAAAAHBpY3QAAAAAAAAAAAAAAAAAAAAAJGRpbmYAAAAcZHJlZgAAAAAAAAABAAAADHVybCAAAAABAAAADnBpdG0AAAAAAAEAAAAjaWluZgAAAAAAAQAAABVpbmZlAgAAAAABAABodmMxAAAACKhpcHJwAAAIh2lwY28AAAfUY29scnByb2YAAAfIYXBwbAIgAABtbnRyUkdCIFhZWiAH2QACABkACwAaAAthY3NwQVBQTAAAAABhcHBsAAAAAAAAAAAAAAAAAAAAAAAA9tYAAQAAAADTLWFwcGwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAtkZXNjAAABCAAAAG9kc2NtAAABeAAABYpjcHJ0AAAHBAAAADh3dHB0AAAHPAAAABRyWFlaAAAHUAAAABRnWFlaAAAHZAAAABRiWFlaAAAHeAAAABRyVFJDAAAHjAAAAA5jaGFkAAAHnAAAACxiVFJDAAAHjAAAAA5nVFJDAAAHjAAAAA5kZXNjAAAAAAAAABRHZW5lcmljIFJHQiBQcm9maWxlAAAAAAAAAAAAAAAUR2VuZXJpYyBSR0IgUHJvZmlsZQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAbWx1YwAAAAAAAAAfAAAADHNrU0sAAAAoAAABhGRhREsAAAAkAAABrGNhRVMAAAAkAAAB0HZpVk4AAAAkAAAB9HB0QlIAAAAmAAACGHVrVUEAAAAqAAACPmZyRlUAAAAoAAACaGh1SFUAAAAoAAACkHpoVFcAAAASAAACuGtvS1IAAAAWAAACym5iTk8AAAAmAAAC4GNzQ1oAAAAiAAADBmhlSUwAAAAeAAADKHJvUk8AAAAkAAADRmRlREUAAAAsAAADaml0SVQAAAAoAAADlnN2U0UAAAAmAAAC4HpoQ04AAAASAAADvmphSlAAAAAaAAAD0GVsR1IAAAAiAAAD6nB0UE8AAAAmAAAEDG5sTkwAAAAoAAAEMmVzRVMAAAAmAAAEDHRoVEgAAAAkAAAEWnRyVFIAAAAiAAAEfmZpRkkAAAAoAAAEoGhySFIAAAAoAAAEyHBsUEwAAAAsAAAE8HJ1UlUAAAAiAAAFHGVuVVMAAAAmAAAFPmFyRUcAAAAmAAAFZABWAWEAZQBvAGIAZQBjAG4A/QAgAFIARwBCACAAcAByAG8AZgBpAGwARwBlAG4AZQByAGUAbAAgAFIARwBCAC0AcAByAG8AZgBpAGwAUABlAHIAZgBpAGwAIABSAEcAQgAgAGcAZQBuAOgAcgBpAGMAQx6lAHUAIABoAOwAbgBoACAAUgBHAEIAIABDAGgAdQBuAGcAUABlAHIAZgBpAGwAIABSAEcAQgAgAEcAZQBuAOkAcgBpAGMAbwQXBDAEMwQwBDsETAQ9BDgEOQAgBD8EQAQ+BEQEMAQ5BDsAIABSAEcAQgBQAHIAbwBmAGkAbAAgAGcA6QBuAOkAcgBpAHEAdQBlACAAUgBWAEIAwQBsAHQAYQBsAOEAbgBvAHMAIABSAEcAQgAgAHAAcgBvAGYAaQBskBp1KABSAEcAQoJyX2ljz4/wx3y8GAAgAFIARwBCACDVBLhc0wzHfABHAGUAbgBlAHIAaQBzAGsAIABSAEcAQgAtAHAAcgBvAGYAaQBsAE8AYgBlAGMAbgD9ACAAUgBHAEIAIABwAHIAbwBmAGkAbAXkBegF1QXkBdkF3AAgAFIARwBCACAF2wXcBdwF2QBQAHIAbwBmAGkAbAAgAFIARwBCACAAZwBlAG4AZQByAGkAYwBBAGwAbABnAGUAbQBlAGkAbgBlAHMAIABSAEcAQgAtAFAAcgBvAGYAaQBsAFAAcgBvAGYAaQBsAG8AIABSAEcAQgAgAGcAZQBuAGUAcgBpAGMAb2ZukBoAUgBHAEJjz4/wZYdO9k4AgiwAIABSAEcAQgAgMNcw7TDVMKEwpDDrA5MDtQO9A7kDugPMACADwAPBA78DxgOvA7sAIABSAEcAQgBQAGUAcgBmAGkAbAAgAFIARwBCACAAZwBlAG4A6QByAGkAYwBvAEEAbABnAGUAbQBlAGUAbgAgAFIARwBCAC0AcAByAG8AZgBpAGUAbA5CDhsOIw5EDh8OJQ5MACAAUgBHAEIAIA4XDjEOSA4nDkQOGwBHAGUAbgBlAGwAIABSAEcAQgAgAFAAcgBvAGYAaQBsAGkAWQBsAGUAaQBuAGUAbgAgAFIARwBCAC0AcAByAG8AZgBpAGkAbABpAEcAZQBuAGUAcgBpAQ0AawBpACAAUgBHAEIAIABwAHIAbwBmAGkAbABVAG4AaQB3AGUAcgBzAGEAbABuAHkAIABwAHIAbwBmAGkAbAAgAFIARwBCBB4EMQRJBDgEOQAgBD8EQAQ+BEQEOAQ7BEwAIABSAEcAQgBHAGUAbgBlAHIAaQBjACAAUgBHAEIAIABQAHIAbwBmAGkAbABlBkUGRAZBACAGKgY5BjEGSgZBACAAUgBHAEIAIAYnBkQGOQYnBkUAAHRleHQAAAAAQ29weXJpZ2h0IDIwMDcgQXBwbGUgSW5jLiwgYWxsIHJpZ2h0cyByZXNlcnZlZC4AWFlaIAAAAAAAAPNSAAEAAAABFs9YWVogAAAAAAAAdE0AAD3uAAAD0FhZWiAAAAAAAABadQAArHMAABc0WFlaIAAAAAAAACgaAAAVnwAAuDZjdXJ2AAAAAAAAAAEBzQAAc2YzMgAAAAAAAQxCAAAF3v//8yYAAAeSAAD9kf//+6L///2jAAAD3AAAwGwAAAAMY2xsaQDLAEAAAAAUaXNwZQAAAAAAAAACAAAAAgAAAAlpcm90AAAAABBwaXhpAAAAAAMICAgAAAByaHZjQwEDcAAAALAAAAAAAB7wAPz9+PgAAAsDoAABABdAAQwB//8DcAAAAwCwAAADAAADAB5wJKEAAQAkQgEBA3AAAAMAsAAAAwAAAwAeoBQgQcChBBiHuRZVNwICBgCAogABAAlEAcBhcshEU2QAAAAZaXBtYQAAAAAAAAABAAEGgQIDBYaEAAAAHmlsb2MAAAAARAAAAQABAAAAAQAACXwAAAA/AAAAAW1kYXQAAAAAAAAATwAAADsoAa+i+kaBfP/92s//9lT7L851/Vf/tCfI+VgC/6Nc90yyZ/og+cI53hzw5O9v9pzCL2FfgrcISbIrgA=="
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
