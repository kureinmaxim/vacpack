import Foundation
import ImageIO

enum ImageMetadataCopier {
    /// Copies EXIF/IPTC/XMP from `metadata` onto the encoded file without re-encoding its pixels
    /// (ImageIO's lossless path for JPEG, PNG and TIFF). Orientation is reset to 1 because the
    /// engine already applied it to the pixels.
    static func copy(_ metadata: CGImageMetadata, onto file: URL, format: ConcreteImageFormat) throws {
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil),
            let tree = CGImageMetadataCreateMutableCopy(metadata)
        else { throw ImageEncodeError.writeFailed(format.rawValue) }
        // kCGImageDestinationOrientation cannot be combined with kCGImageDestinationMetadata,
        // so the orientation is reset inside the copied tree instead.
        CGImageMetadataSetValueMatchingImageProperty(
            tree, kCGImagePropertyTIFFDictionary, kCGImagePropertyOrientation, 1 as CFNumber)
        let target = file.deletingLastPathComponent().appending(path: "with-metadata.\(format.fileExtension)")
        guard
            let destination = CGImageDestinationCreateWithURL(
                target as CFURL, format.utType.identifier as CFString, 1, nil)
        else { throw ImageEncodeError.writeFailed(format.rawValue) }
        let options: [CFString: Any] = [
            kCGImageDestinationMetadata: tree,
            kCGImageDestinationMergeMetadata: true,
        ]
        var error: Unmanaged<CFError>?
        guard CGImageDestinationCopyImageSource(destination, source, options as CFDictionary, &error) else {
            let reason = error.map { String(describing: $0.takeRetainedValue()) } ?? "unknown error"
            throw ImageEncodeError.writeFailed("\(format.rawValue) metadata (\(reason))")
        }
        _ = try FileManager.default.replaceItemAt(file, withItemAt: target)
    }
}
