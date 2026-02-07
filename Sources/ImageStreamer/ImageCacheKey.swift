import Foundation
import CoreGraphics

/// A cache key that uniquely identifies an image request by its URL and target size.
///
/// This allows the `ImageStreamer` to cache different downsampled versions of the same image
/// separately (e.g., a thumbnail vs. a full-screen view).
public final class ImageCacheKey: NSObject, @unchecked Sendable {
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
}
