import Foundation
import ImageIO

/// What the GIF engine needs to know about its input, GIF or video.
struct AnimationSource: Sendable, Equatable {
    var size: PixelSize
    var duration: Double
    var fps: Double?
    /// Decoder to force before `-i` (VP8/VP9 with alpha), as for `VideoInfo`.
    var alphaDecoder: String?
}

enum GIFError: Error, CustomStringConvertible, Equatable {
    case toolMissing(Tool)
    case unreadable
    case noFrames
    case toolFailed(Tool, String)

    var description: String {
        switch self {
        case .toolMissing(let tool): "\(tool.rawValue) is not installed"
        case .unreadable: "Cannot read the animation"
        case .noFrames: "The input produced no frames"
        case .toolFailed(let tool, let message): "\(tool.rawValue) failed: \(message)"
        }
    }
}

enum GIFQualityTable {
    /// gifski `--quality`, 1–100.
    static func gifski(_ q: QualityLevel) -> Int {
        switch q {
        case .highest: 100
        case .high: 90
        case .good: 80
        case .medium: 70
        case .acceptable: 55
        }
    }
}

enum GIFSizeMath {
    /// Output size: never larger than the source, aspect ratio kept, at least 1×1.
    static func target(for source: PixelSize, dimension: GIFDimension) -> PixelSize {
        switch dimension {
        case .same: source
        case .percentage(let percent): ImageResizeMath.targetSize(for: source, resize: .percentage(percent))
        case .maxWidth(let width): ImageResizeMath.targetSize(for: source, resize: .maxWidth(width))
        }
    }

    /// Video → GIF uses the chosen rate (10–50) but never more than the video has;
    /// GIF → GIF keeps its own average rate, at most 50 (browsers slow faster GIFs down).
    static func fps(for source: AnimationSource, isVideo: Bool, settings: GIFSettings) -> Double {
        let sourceFPS = source.fps ?? Double(settings.fps)
        let range = GIFSettings.fpsRange
        let chosen = Double(isVideo ? min(max(settings.fps, range.lowerBound), range.upperBound) : range.upperBound)
        return max(1, (min(chosen, sourceFPS) * 100).rounded() / 100)
    }
}

/// Compresses GIFs and converts videos to GIF (SPEC §4): ffmpeg extracts PNG frames at the target
/// rate and size (keeping transparency, rotation and GIF frame timing), gifski encodes them.
public struct GIFEngine: Sendable {
    let ffmpeg: URL?
    let ffprobe: URL?
    let gifski: URL?
    let runner: ProcessRunner

    public init(ffmpeg: URL?, ffprobe: URL?, gifski: URL?, runner: ProcessRunner = ProcessRunner()) {
        self.ffmpeg = ffmpeg
        self.ffprobe = ffprobe
        self.gifski = gifski
        self.runner = runner
    }

    public init(locator: ToolLocator) {
        self.init(
            ffmpeg: locator.locate(.ffmpeg)?.url, ffprobe: locator.locate(.ffprobe)?.url,
            gifski: locator.locate(.gifski)?.url)
    }

    func encode(
        _ input: URL, isVideo: Bool, settings: GIFSettings, workDirectory: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> EncodedFile {
        guard let ffmpeg else { throw GIFError.toolMissing(.ffmpeg) }
        guard let gifski else { throw GIFError.toolMissing(.gifski) }
        let source: AnimationSource
        if isVideo {
            guard let ffprobe else { throw GIFError.toolMissing(.ffprobe) }
            let info = try await VideoProbe.probe(input, ffprobe: ffprobe, runner: runner)
            source = AnimationSource(
                size: info.displaySize, duration: info.duration, fps: info.fps, alphaDecoder: info.alphaDecoder)
        } else {
            source = try Self.gifSource(input)
        }
        progress(0.02)

        let size = GIFSizeMath.target(for: source.size, dimension: settings.dimension)
        let fps = GIFSizeMath.fps(for: source, isVideo: isVideo, settings: settings)
        let frames = workDirectory.appending(path: "frames", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: frames, withIntermediateDirectories: true)

        // Phase 1 (2–50%): frames.
        let extract = FFmpegProgress(duration: source.duration) { progress(0.02 + $0 * 0.48) }
        let extraction = try await runner.run(
            ffmpeg, arguments: Self.frameArguments(input: input, source: source, size: size, fps: fps, frames: frames),
            onStdoutLine: extract.handle)
        guard extraction.exitCode == 0 else { throw GIFError.toolFailed(.ffmpeg, Self.tail(extraction.stderrString)) }
        let pngs = try FileManager.default.contentsOfDirectory(at: frames, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "png" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !pngs.isEmpty else { throw GIFError.noFrames }
        try Task.checkCancellation()

        // Phase 2 (50–99%): gifski reports "Frame N / M".
        let output = workDirectory.appending(path: "encoded.gif")
        let encode = GifskiProgress { progress(0.5 + $0 * 0.49) }
        let encoding = try await runner.run(
            gifski,
            arguments: Self.gifskiArguments(
                quality: settings.quality, fps: fps, size: size, output: output, frames: pngs),
            onStdoutLine: encode.handle)
        guard encoding.exitCode == 0 else { throw GIFError.toolFailed(.gifski, Self.tail(encoding.stderrString)) }

        let resized = settings.dimension != .same && size != source.size
        return EncodedFile(
            url: output, fileExtension: "gif", pixelSize: size, changedOnRequest: isVideo || resized,
            resolutionLabel: size.description)
    }

    static func frameArguments(input: URL, source: AnimationSource, size: PixelSize, fps: Double, frames: URL)
        -> [String]
    {
        var args = ["-hide_banner", "-nostdin", "-y", "-loglevel", "error", "-progress", "pipe:1", "-nostats"]
        if let decoder = source.alphaDecoder { args += ["-c:v", decoder] }
        args += ["-i", input.path, "-map", "0:V:0", "-an", "-sn", "-dn"]
        var filters = ["fps=\(format(fps))"]
        if size != source.size { filters.append("scale=\(size.width):\(size.height):flags=lanczos") }
        args += ["-vf", filters.joined(separator: ","), frames.appending(path: "f%06d.png").path]
        return args
    }

    static func gifskiArguments(quality: QualityLevel, fps: Double, size: PixelSize, output: URL, frames: [URL])
        -> [String]
    {
        // Width and height are given explicitly: without them gifski shrinks to about 800×600.
        [
            "--fps", format(fps), "--quality", String(GIFQualityTable.gifski(quality)),
            "--width", String(size.width), "--height", String(size.height), "--output", output.path,
        ] + frames.map(\.path)
    }

    /// Size, duration and average rate from the GIF's own frame delays.
    static func gifSource(_ url: URL) throws -> AnimationSource {
        guard let image = CGImageSourceCreateWithURL(url as CFURL, nil) else { throw GIFError.unreadable }
        let count = CGImageSourceGetCount(image)
        guard count > 0,
            let first = CGImageSourceCopyPropertiesAtIndex(image, 0, nil) as? [CFString: Any],
            let width = first[kCGImagePropertyPixelWidth] as? Int,
            let height = first[kCGImagePropertyPixelHeight] as? Int
        else { throw GIFError.unreadable }
        var duration = 0.0
        var shortest = Double.infinity
        for index in 0..<count {
            let props = CGImageSourceCopyPropertiesAtIndex(image, index, nil) as? [CFString: Any]
            let gif = props?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            let raw =
                (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double)
                ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.1
            // Browsers show delays of 10 ms or less as 100 ms.
            let delay = raw <= 0.011 ? 0.1 : raw
            duration += delay
            shortest = min(shortest, delay)
        }
        // Resampling at the rate of the shortest frame shows every frame; longer frames are
        // repeated, and gifski merges most repeats back into longer frames. Measured: delays
        // 0.5/0.1×4/0.5 came out as 0.5/0.1×4/0.3/0.2 — same total time, one extra frame.
        return AnimationSource(
            size: PixelSize(width: width, height: height), duration: duration,
            fps: shortest.isFinite ? 1 / shortest : nil, alphaDecoder: nil)
    }

    private static func format(_ fps: Double) -> String {
        fps == fps.rounded() ? String(Int(fps)) : String(format: "%.2f", fps)
    }

    private static func tail(_ text: String) -> String {
        let lines = text.split(whereSeparator: \.isNewline).suffix(3).joined(separator: " ")
        return lines.isEmpty ? "no details" : lines
    }
}

/// Turns gifski's "Frame N / M" progress lines into a monotonic 0…1 fraction.
final class GifskiProgress: @unchecked Sendable {
    private let report: @Sendable (Double) -> Void
    private let lock = NSLock()
    private var last = 0.0

    init(report: @escaping @Sendable (Double) -> Void) { self.report = report }

    func handle(_ line: String) {
        guard let range = line.range(of: #"Frame (\d+) / (\d+)"#, options: .regularExpression) else { return }
        let numbers = line[range].split(whereSeparator: { !$0.isNumber }).compactMap { Double($0) }
        guard numbers.count == 2, numbers[1] > 0 else { return }
        let fraction = min(1, numbers[0] / numbers[1])
        let shouldReport: Bool = lock.withLock {
            guard fraction >= last + 0.01 || (fraction == 1 && last < 1) else { return false }
            last = fraction
            return true
        }
        if shouldReport { report(fraction) }
    }
}
