import Foundation
import UniformTypeIdentifiers

/// The kind of file decides which engine handles it (SPEC §1).
public enum FileKind: String, Codable, Sendable, CaseIterable {
    case video, image, gif, pdf, epub

    /// Image inputs from SPEC §1: JPEG, PNG, WebP, AVIF, HEIC/HEIF, DNG, TIFF, BMP, SVG.
    static let imageTypes: [UTType] = [
        .jpeg, .png, .webP, .heic, .heif, .tiff, .bmp, .svg,
        UTType("public.avif"), UTType("com.adobe.raw-image"),
    ].compactMap { $0 }

    /// Detects the kind from the file extension, or nil for unsupported files.
    public static func detect(_ url: URL) -> FileKind? {
        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else { return nil }
        if type.conforms(to: .gif) { return .gif }
        if type.conforms(to: .pdf) { return .pdf }
        if type.conforms(to: .epub) { return .epub }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
        if imageTypes.contains(where: { type.conforms(to: $0) }) { return .image }
        return nil
    }
}
