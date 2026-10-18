import Foundation

/// Output format choice for videos (SPEC §2). GIF output uses `GIFSettings` (SPEC §4).
public enum VideoFormatChoice: String, Codable, Sendable, CaseIterable {
    case same, mp4, webm, mov, gif, mp3
}

/// Resolution choices from SPEC §2. Videos are only ever scaled down; aspect ratio is kept.
public enum VideoResolution: Codable, Hashable, Sendable {
    case same
    /// Fits in 3840×2160 (2160×3840 for portrait video).
    case uhd4K
    /// Fits in 1920×1080 (1080×1920 for portrait video).
    case fullHD
    /// Fits in 1280×720 (720×1280 for portrait video).
    case hd
    case maxWidth(Int)
    case maxHeight(Int)
    case maxLongEdge(Int)
    case maxShortEdge(Int)

    /// Name used for the `{resolution}` token, as in SPEC §18 (`video-Good-FullHD.mp4`).
    var presetLabel: String? {
        switch self {
        case .uhd4K: "4K"
        case .fullHD: "FullHD"
        case .hd: "HD"
        default: nil
        }
    }
}

/// Per-file video options (sidebar, presets, per-file overrides).
public struct VideoSettings: Codable, Hashable, Sendable {
    public var quality: QualityLevel
    public var format: VideoFormatChoice
    public var resolution: VideoResolution
    public var removeAudio: Bool
    /// Keep the alpha channel in MOV output. WebM output always keeps it (SPEC §2).
    public var preserveTransparency: Bool

    public init(
        quality: QualityLevel = .high, format: VideoFormatChoice = .same, resolution: VideoResolution = .same,
        removeAudio: Bool = false, preserveTransparency: Bool = false
    ) {
        self.quality = quality
        self.format = format
        self.resolution = resolution
        self.removeAudio = removeAudio
        self.preserveTransparency = preserveTransparency
    }
}

public enum VideoCodec: String, Codable, Sendable, CaseIterable {
    case h264, hevc
}

/// App-wide video settings from Settings → Advanced (SPEC §2, §16).
public struct VideoEncodingOptions: Codable, Hashable, Sendable {
    public var codec: VideoCodec
    /// Frame rate cap; only ever lowers the frame rate. Nil keeps the input's.
    public var maxFPS: Int?
    /// Use VideoToolbox (the Mac's media engine) when it can do the job.
    public var hardwareAcceleration: Bool
    /// CPU threads for software encoders; nil means all cores.
    public var threads: Int?

    public init(codec: VideoCodec = .h264, maxFPS: Int? = nil, hardwareAcceleration: Bool = true, threads: Int? = nil) {
        self.codec = codec
        self.maxFPS = maxFPS
        self.hardwareAcceleration = hardwareAcceleration
        self.threads = threads
    }
}
