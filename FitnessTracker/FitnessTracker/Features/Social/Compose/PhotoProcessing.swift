import UIKit

/// Prepares a picked image for `POST /api/post-photos`: downscaled to at most
/// 2048 px on the long edge and re-encoded as JPEG (which also converts HEIC,
/// a `415` on the server), staying under the 4 MB limit (`413`).
nonisolated enum PhotoProcessing {
    static let maxLongEdge: CGFloat = 2048
    /// A little under the server's 4 MB, for multipart overhead.
    static let maxBytes = 3_900_000

    enum ProcessingError: Error {
        case unreadable
        case tooLarge
    }

    /// Decodes `data` (JPEG, PNG, HEIC, …), downscales and encodes as JPEG.
    /// CPU-heavy, so call it off the main actor.
    nonisolated static func jpegForUpload(from data: Data) throws -> (jpeg: Data, preview: UIImage) {
        guard let image = UIImage(data: data) else { throw ProcessingError.unreadable }
        let scaled = downscaled(image)
        for quality in [0.85, 0.75, 0.6, 0.45] as [CGFloat] {
            if let jpeg = scaled.jpegData(compressionQuality: quality), jpeg.count <= maxBytes {
                return (jpeg, scaled)
            }
        }
        throw ProcessingError.tooLarge
    }

    /// The size an image of `size` is drawn at: unchanged when it fits,
    /// otherwise scaled so the long edge is `maxLongEdge`.
    nonisolated static func targetSize(for size: CGSize) -> CGSize {
        let longEdge = max(size.width, size.height)
        guard longEdge > maxLongEdge, longEdge > 0 else { return size }
        let scale = maxLongEdge / longEdge
        return CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
    }

    /// Draws upright at 1× scale, which also applies the EXIF orientation.
    nonisolated private static func downscaled(_ image: UIImage) -> UIImage {
        let target = targetSize(for: image.size)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
