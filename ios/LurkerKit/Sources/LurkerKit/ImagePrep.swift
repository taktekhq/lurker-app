// Turns a shared photo into the one JPEG shape `POST /v1/shares` accepts
// (SPEC.md: image/jpeg, max 5 MB per photo): orientation baked into the
// pixels, long edge capped at 1600 px, quality 0.8 -- re-encoding this way
// drops EXIF, GPS included, which is the point: nothing a maker shares
// should carry their photo's location along with it.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// `ImagePrep.prepare` couldn't decode or re-encode the photo.
public enum ImagePrepError: Error, Sendable, Equatable {
    /// The input bytes aren't a decodable image.
    case decodeFailed
    /// `ImageIO` could not produce JPEG data from the decoded image.
    case encodeFailed
}

/// Decodes and re-encodes a shared photo for upload. Stateless: the tunables
/// below are defaults on `prepare` itself, not stored properties.
public enum ImagePrep {
    /// The long side a prepared photo is downsized to, at most (SPEC.md).
    public static let defaultMaxDimension = 1600
    /// SPEC.md's fixed JPEG quality: no further stepping is needed, since a
    /// photo this size at this quality is well under the worker's 5 MB cap.
    public static let defaultQuality: CGFloat = 0.8

    /// Decodes `data`, bakes in its EXIF orientation (so the result needs no
    /// orientation tag to display correctly), downsizes so its long side is
    /// at most `maxDimension` px (never upscales a smaller photo), and
    /// encodes as JPEG at `quality`.
    public static func prepare(
        _ data: Data,
        maxDimension: Int = defaultMaxDimension,
        quality: CGFloat = defaultQuality
    ) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw ImagePrepError.decodeFailed
        }

        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
            throw ImagePrepError.decodeFailed
        }

        return try encodeJPEG(image, quality: quality)
    }

    private static func encodeJPEG(_ image: CGImage, quality: CGFloat) throws -> Data {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw ImagePrepError.encodeFailed
        }
        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ImagePrepError.encodeFailed
        }
        return output as Data
    }
}
