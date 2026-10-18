import Foundation

/// Everything needed to compress one file. Each job carries its own settings, so
/// per-file overrides (SPEC §10) are just a different value for one job.
public struct JobRequest: Sendable, Hashable {
    public var input: URL
    public var image: ImageSettings
    public var video: VideoSettings
    public var output: OutputPolicy
    public var metadata: MetadataOptions
    /// App-wide video settings (codec, FPS cap, hardware acceleration, threads).
    public var videoEncoding: VideoEncodingOptions

    public init(
        input: URL, image: ImageSettings = ImageSettings(), video: VideoSettings = VideoSettings(),
        output: OutputPolicy = OutputPolicy(), metadata: MetadataOptions = MetadataOptions(),
        videoEncoding: VideoEncodingOptions = VideoEncodingOptions()
    ) {
        self.input = input
        self.image = image
        self.video = video
        self.output = output
        self.metadata = metadata
        self.videoEncoding = videoEncoding
    }
}

public struct PixelSize: Codable, Hashable, Sendable, CustomStringConvertible {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    public var longEdge: Int { max(width, height) }
    public var description: String { "\(width)x\(height)" }
}

public struct CompressionResult: Sendable, Hashable {
    public enum Note: String, Sendable, Hashable {
        /// The format or size changed on request and the file grew; kept because it was asked for.
        case largerThanOriginal
        /// The input was moved to the Trash.
        case removedInput
    }

    public let input: URL
    public let output: URL
    public let inputBytes: Int64
    public let outputBytes: Int64
    public let pixelSize: PixelSize?
    public let notes: Set<Note>

    /// Saved share of the input size, 0…1 (negative when the file grew).
    public var savedFraction: Double {
        inputBytes > 0 ? 1 - Double(outputBytes) / Double(inputBytes) : 0
    }
}

public enum JobOutcome: Sendable, Hashable {
    case compressed(CompressionResult)
    /// Compression did not make the file smaller, so the original was kept (SPEC §8).
    /// `copiedTo` is set when the output folder differs and the original was copied there.
    case keptOriginal(input: URL, copiedTo: URL?)
    case unsupported(input: URL, kind: FileKind?)
    case failed(input: URL, message: String)
    case cancelled(input: URL)
}
