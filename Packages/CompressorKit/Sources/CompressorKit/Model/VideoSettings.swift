import Foundation

/// Output format choice for videos (SPEC §2). GIF output uses `GIFSettings` (SPEC §4); MP3, M4A and
/// Opus keep only the sound (SPEC §7 for MP3).
public enum VideoFormatChoice: String, Codable, Sendable, CaseIterable {
    case same, mp4, webm, mov, gif, mp3, m4a, opus

    /// Formats that keep only the sound.
    public var isAudio: Bool { self == .mp3 || self == .m4a || self == .opus }
}

/// How the sound is encoded when a video becomes an audio file.
public enum AudioProfile: String, Codable, Sendable, CaseIterable {
    /// The source's channels at high quality (for MP3: VBR V0, SPEC §7).
    case music
    /// Podcasts and messengers: mono, loudness evened out to −16 LUFS, a low bitrate.
    case speech
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
    /// Sound encoding for MP3, M4A and Opus output.
    public var audioProfile: AudioProfile

    public init(
        quality: QualityLevel = .high, format: VideoFormatChoice = .same, resolution: VideoResolution = .same,
        removeAudio: Bool = false, preserveTransparency: Bool = false, audioProfile: AudioProfile = .music
    ) {
        self.quality = quality
        self.format = format
        self.resolution = resolution
        self.removeAudio = removeAudio
        self.preserveTransparency = preserveTransparency
        self.audioProfile = audioProfile
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
    /// Use VideoToolbox (the Mac's media engine). Off by default: on Apple Silicon x264/x265 were
    /// both faster and visibly cleaner at the same size (docs/QUALITY.md, "Rate control").
    public var hardwareAcceleration: Bool
    /// CPU threads for software encoders; nil means all cores.
    public var threads: Int?

    public init(codec: VideoCodec = .h264, maxFPS: Int? = nil, hardwareAcceleration: Bool = false, threads: Int? = nil)
    {
        self.codec = codec
        self.maxFPS = maxFPS
        self.hardwareAcceleration = hardwareAcceleration
        self.threads = threads
    }
}
