import Foundation

/// Compresses or converts one video with ffmpeg (SPEC §2), or extracts its audio as MP3 (SPEC §7).
public struct VideoEngine: Sendable {
    let ffmpeg: URL?
    let ffprobe: URL?
    let runner: ProcessRunner
    let environment: VideoCommand.Environment

    public init(ffmpeg: URL?, ffprobe: URL?, runner: ProcessRunner = ProcessRunner()) {
        self.ffmpeg = ffmpeg
        self.ffprobe = ffprobe
        self.runner = runner
        #if arch(arm64)
            environment = VideoCommand.Environment(videoToolboxQuality: true)
        #else
            environment = VideoCommand.Environment(videoToolboxQuality: false)
        #endif
    }

    public init(locator: ToolLocator) {
        self.init(ffmpeg: locator.locate(.ffmpeg)?.url, ffprobe: locator.locate(.ffprobe)?.url)
    }

    func encode(
        _ input: URL, settings: VideoSettings, options: VideoEncodingOptions, workDirectory: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> EncodedFile {
        guard let ffprobe else { throw VideoError.toolMissing(.ffprobe) }
        guard let ffmpeg else { throw VideoError.toolMissing(.ffmpeg) }
        let info = try await VideoProbe.probe(input, ffprobe: ffprobe, runner: runner)
        progress(0.02)

        let output = VideoOutput.resolve(settings.format, inputExtension: input.pathExtension)
        if info.hasAlpha, settings.preserveTransparency, output == .video(.mov), !environment.videoToolboxQuality {
            throw VideoError.transparencyNeedsAppleSilicon
        }
        let file = workDirectory.appending(path: "encoded.\(output.fileExtension)")
        var command = try VideoCommand.build(
            input: input, output: file, info: info, settings: settings, options: options, environment: environment)

        let tracker = FFmpegProgress(duration: info.duration, report: progress)
        var result = try await runner.run(ffmpeg, arguments: command.arguments, onStdoutLine: tracker.handle)
        // VideoToolbox can refuse a session when the media engine is busy (other encodes, screen
        // recording, calls): ffmpeg then fails with -22. Fall back to the software encoder; HEVC with
        // alpha has no software path here, so it gets one more try instead.
        if result.exitCode != 0, let encoder = command.videoEncoder, encoder.hasSuffix("_videotoolbox") {
            if command.arguments.contains("-alpha_quality") {
                try await Task.sleep(for: .seconds(1))
            } else {
                var software = options
                software.hardwareAcceleration = false
                command = try VideoCommand.build(
                    input: input, output: file, info: info, settings: settings, options: software,
                    environment: environment)
            }
            result = try await runner.run(ffmpeg, arguments: command.arguments, onStdoutLine: tracker.handle)
        }
        guard result.exitCode == 0 else {
            let message = result.stderrString.split(whereSeparator: \.isNewline).suffix(3).joined(separator: " ")
            throw VideoError.ffmpegFailed(message.isEmpty ? "exit status \(result.exitCode)" : message)
        }

        // AVI, FLV, TS, WMV… are rewritten as MP4 even for "Same as input": that conversion is not optional.
        let containerKept = VideoOutput.writableInputExtensions.contains(input.pathExtension.lowercased())
        let formatRequested =
            (settings.format != .same && output != VideoOutput.resolve(.same, inputExtension: input.pathExtension))
            || !containerKept
        let resizeRequested = settings.resolution != .same && command.size != info.displaySize
        return EncodedFile(
            url: file, fileExtension: output.fileExtension, pixelSize: command.size,
            changedOnRequest: formatRequested || resizeRequested,
            resolutionLabel: command.size.map { settings.resolution.presetLabel ?? $0.description })
    }
}

/// Turns `ffmpeg -progress pipe:1` lines into a monotonic 0…0.99 fraction (1 is reported
/// once the output is in place).
final class FFmpegProgress: @unchecked Sendable {
    private let duration: Double
    private let report: @Sendable (Double) -> Void
    private let lock = NSLock()
    private var last = 0.0

    init(duration: Double, report: @escaping @Sendable (Double) -> Void) {
        self.duration = duration
        self.report = report
    }

    func handle(_ line: String) {
        let fraction: Double
        if line.hasPrefix("out_time_us="), let micros = Double(line.dropFirst("out_time_us=".count)), duration > 0 {
            fraction = micros / 1_000_000 / duration
        } else if line == "progress=end" {
            fraction = 0.99
        } else {
            return
        }
        let clamped = min(0.99, max(0, fraction))
        let shouldReport: Bool = lock.withLock {
            // Report only forward steps of at least half a percent.
            guard clamped >= last + 0.005 || (clamped == 0.99 && last < 0.99) else { return false }
            last = clamped
            return true
        }
        if shouldReport { report(clamped) }
    }
}
