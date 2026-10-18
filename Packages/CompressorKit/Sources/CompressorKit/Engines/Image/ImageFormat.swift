import Foundation
import UniformTypeIdentifiers

/// A format the image engine can actually write.
enum ConcreteImageFormat: String, Sendable, CaseIterable {
    case jpeg, png, webp, avif, heic, tiff

    var fileExtension: String {
        switch self {
        case .jpeg: "jpg"
        case .tiff: "tiff"
        default: rawValue
        }
    }

    var utType: UTType {
        switch self {
        case .jpeg: .jpeg
        case .png: .png
        case .webp: .webP
        case .avif: UTType("public.avif")!
        case .heic: .heic
        case .tiff: .tiff
        }
    }

    var supportsAlpha: Bool { self != .jpeg }

    /// Formats whose EXIF/IPTC/XMP ImageIO can copy without re-encoding (SPEC §15).
    var supportsMetadataCopy: Bool { self == .jpeg || self == .png || self == .tiff }

    /// Formats that keep the input's print resolution (SPEC §3).
    var keepsDPI: Bool { self == .jpeg || self == .png }

    /// The format of an existing file, if it is one we can write.
    init?(inputType: UTType) {
        guard let format = Self.allCases.first(where: { inputType.conforms(to: $0.utType) }) else { return nil }
        self = format
    }

    /// Resolves the user's choice for one input. For "Same as input", formats we cannot or
    /// should not write map to the closest useful one: DNG → JPEG, BMP and SVG → PNG
    /// (SVG keeps transparency), HEIF → HEIC.
    static func resolve(_ choice: ImageFormatChoice, inputType: UTType) -> ConcreteImageFormat {
        switch choice {
        case .jpg: return .jpeg
        case .png: return .png
        case .webp: return .webp
        case .avif: return .avif
        case .same:
            if let format = ConcreteImageFormat(inputType: inputType) { return format }
            if inputType.conforms(to: .heif) { return .heic }
            if let raw = UTType("com.adobe.raw-image"), inputType.conforms(to: raw) { return .jpeg }
            return .png
        }
    }
}
