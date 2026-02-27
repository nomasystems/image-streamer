import Foundation
import CoreGraphics

/// A cache key that uniquely identifies an image request by its URL and target size.
///
/// This allows the `ImageStreamer` to cache different downsampled versions of the same image
/// separately (e.g., a thumbnail vs. a full-screen view).
///
/// - Note: Conforms to `NSCopying` so it can be used as a key in `NSCache` which matches
/// the Cocoa patterns for key-based storage. Since the class is `final` and immutable,
/// copying simply returns `self`.
public final class ImageCacheKey: NSObject, NSCopying, @unchecked Sendable {
    public let url: URL
    public let pointSize: CGSize?

    public init(url: URL, pointSize: CGSize? = nil) {
        self.url = url
        self.pointSize = pointSize
    }

    public override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? ImageCacheKey else { return false }
        return url == other.url && pointSize == other.pointSize
    }

    public override var hash: Int {
        var hasher = Hasher()
        hasher.combine(url)
        if let pointSize = pointSize {
            hasher.combine(pointSize.width)
            hasher.combine(pointSize.height)
        }
        return hasher.finalize()
    }

    // MARK: - NSCopying

    public func copy(with zone: NSZone? = nil) -> Any {
        // Since this class is immutable and final, we can safely return self.
        return self
    }

    // MARK: - CustomDebugStringConvertible

    public override var debugDescription: String {
        if let size = pointSize {
            return "ImageCacheKey(url: \(url), pointSize: \(Int(size.width))x\(Int(size.height)))"
        } else {
            return "ImageCacheKey(url: \(url), pointSize: original)"
        }
    }
}
