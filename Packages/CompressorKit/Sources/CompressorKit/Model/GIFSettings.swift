import Foundation

/// GIF size choices from SPEC §4. The 75/50/25% presets are `.percentage`. Never upscales.
public enum GIFDimension: Codable, Hashable, Sendable {
    case same
    case percentage(Int)
    case maxWidth(Int)
}

/// Options for compressing GIFs and for converting videos to GIF (SPEC §4).
public struct GIFSettings: Codable, Hashable, Sendable {
    public var quality: QualityLevel
    public var dimension: GIFDimension
    /// Frame rate for video → GIF (10–50). GIF inputs keep their own timing.
    public var fps: Int

    public static let fpsRange = 10...50

    public init(quality: QualityLevel = .high, dimension: GIFDimension = .same, fps: Int = 20) {
        self.quality = quality
        self.dimension = dimension
        self.fps = fps
    }
}
