import Foundation

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
    public var quality: QualityLevel
    public var format: ImageFormatChoice
    public var resize: ImageResize

    public init(quality: QualityLevel = .high, format: ImageFormatChoice = .same, resize: ImageResize = .same) {
        self.quality = quality
        self.format = format
        self.resize = resize
    }
}
