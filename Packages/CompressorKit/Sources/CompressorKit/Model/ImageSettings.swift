import Foundation

/// Image quality levels from SPEC §3. Concrete encoder values live in `ImageQualityTable`.
public enum ImageQuality: String, Codable, Sendable, CaseIterable {
    case highest, high, good, medium, acceptable

    /// Label used in the `{quality}` file name token, e.g. "Good".
    public var label: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}

/// Output format choice from SPEC §3.
public enum ImageFormatChoice: String, Codable, Sendable, CaseIterable {
    case same, jpg, png, webp, avif
}

/// Resize modes from SPEC §3. Images are only ever scaled down; aspect ratio is kept.
public enum ImageResize: Codable, Hashable, Sendable {
    case same
    case percentage(Int)
    case maxWidth(Int)
    case maxHeight(Int)
    case maxLongEdge(Int)
    case maxShortEdge(Int)
}

public struct ImageSettings: Codable, Hashable, Sendable {
    public var quality: ImageQuality
    public var format: ImageFormatChoice
    public var resize: ImageResize

    public init(quality: ImageQuality = .high, format: ImageFormatChoice = .same, resize: ImageResize = .same) {
        self.quality = quality
        self.format = format
        self.resize = resize
    }
}
