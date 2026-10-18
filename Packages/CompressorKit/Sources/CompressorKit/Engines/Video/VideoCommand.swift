import Foundation

/// Containers the video engine writes.
enum VideoContainer: String, Sendable, CaseIterable {
    case mp4, mov, webm, mkv

    var fileExtension: String { rawValue }

    /// Audio codecs that can be copied into this container unchanged.
    var copyableAudioCodecs: Set<String> {
        switch self {
        case .mp4: ["aac", "mp3", "ac3", "eac3", "alac", "flac", "opus"]
        case .mov:
            [
                "aac", "mp3", "ac3", "eac3", "alac", "pcm_s16le", "pcm_s24le", "pcm_s32le", "pcm_s16be", "pcm_s24be",
                "pcm_f32le",
            ]
        case .webm: ["opus", "vorbis"]
        case .mkv: []  // Matroska takes anything; handled in `canCopyAudio`.
        }
    }

    func canCopyAudio(_ codec: String) -> Bool { self == .mkv || copyableAudioCodecs.contains(codec) }
}

enum VideoOutput: Equatable, Sendable {
    case video(VideoContainer)
    case mp3
    /// Produced by `GIFEngine`, never by `VideoCommand`.
    case gif

    var fileExtension: String {
        switch self {
        case .video(let container): container.fileExtension
        case .mp3: "mp3"
        case .gif: "gif"
        }
    }

    /// Input containers that "Same as input" writes back unchanged.
    static let writableInputExtensions: Set<String> = ["mp4", "m4v", "mov", "qt", "webm", "mkv"]

    /// "Same as input" keeps MP4, MOV, WebM and MKV; other containers (AVI, FLV, TS, WMV…) become MP4.
    static func resolve(_ choice: VideoFormatChoice, inputExtension: String) -> VideoOutput {
        switch choice {
        case .mp4: return .video(.mp4)
        case .mov: return .video(.mov)
        case .webm: return .video(.webm)
        case .mp3: return .mp3
        case .gif: return .gif
        case .same:
            switch inputExtension.lowercased() {
            case "mov", "qt": return .video(.mov)
            case "webm": return .video(.webm)
            case "mkv": return .video(.mkv)
            default: return .video(.mp4)
            }
        }
    }
}

enum VideoSizeMath {
    /// Output size: never larger than the display size, aspect ratio kept, both sides even
    /// (4:2:0 encoders need even dimensions).
    static func target(display: PixelSize, resolution: VideoResolution) -> PixelSize {
        let fitted: PixelSize
        switch resolution {
        case .same: fitted = display
        case .uhd4K: fitted = fit(display, box: PixelSize(width: 3840, height: 2160))
        case .fullHD: fitted = fit(display, box: PixelSize(width: 1920, height: 1080))
        case .hd: fitted = fit(display, box: PixelSize(width: 1280, height: 720))
        case .maxWidth(let n): fitted = ImageResizeMath.targetSize(for: display, resize: .maxWidth(n))
        case .maxHeight(let n): fitted = ImageResizeMath.targetSize(for: display, resize: .maxHeight(n))
        case .maxLongEdge(let n): fitted = ImageResizeMath.targetSize(for: display, resize: .maxLongEdge(n))
        case .maxShortEdge(let n): fitted = ImageResizeMath.targetSize(for: display, resize: .maxShortEdge(n))
        }
        return PixelSize(width: max(2, fitted.width / 2 * 2), height: max(2, fitted.height / 2 * 2))
    }

    /// Scales down to fit the box, turned to match the video's orientation.
    private static func fit(_ size: PixelSize, box: PixelSize) -> PixelSize {
        let oriented = size.height > size.width ? PixelSize(width: box.height, height: box.width) : box
        let scale = min(Double(oriented.width) / Double(size.width), Double(oriented.height) / Double(size.height))
        guard scale < 1 else { return size }
        return PixelSize(
            width: Int((Double(size.width) * scale).rounded()), height: Int((Double(size.height) * scale).rounded()))
    }
}

/// Builds ffmpeg arguments for one job. Pure, so every rule is unit-tested without running ffmpeg.
struct VideoCommand: Equatable {
    var arguments: [String]
    var output: VideoOutput
    var size: PixelSize?

    /// The video encoder (the `-c:v` after `-i`; one before `-i` picks the decoder).
    var videoEncoder: String? {
        guard let input = arguments.firstIndex(of: "-i") else { return nil }
        let tail = arguments[(input + 1)...]
        guard let flag = tail.firstIndex(of: "-c:v"), flag + 1 < arguments.endIndex else { return nil }
        return arguments[flag + 1]
    }

    struct Environment: Equatable {
        /// Apple Silicon: VideoToolbox constant-quality mode and HEVC with alpha are available.
        var videoToolboxQuality: Bool
    }

    static func build(
        input: URL, output outputURL: URL, info: VideoInfo, settings: VideoSettings,
        options: VideoEncodingOptions, environment: Environment
    ) throws -> VideoCommand {
        let output = VideoOutput.resolve(settings.format, inputExtension: input.pathExtension)
        var args = ["-hide_banner", "-nostdin", "-y", "-loglevel", "error", "-progress", "pipe:1", "-nostats"]
        // Decoder choice goes before -i: only libvpx reads the alpha layer of VP8/VP9.
        if let decoder = info.alphaDecoder { args += ["-c:v", decoder] }
        args += ["-i", input.path]

        if output == .gif { preconditionFailure("video → GIF is handled by GIFEngine") }
        guard case .video(let container) = output else {
            guard !info.audioCodecs.isEmpty else { throw VideoError.noAudioTrack }
            // SPEC §7: best VBR (V0), channels as in the source.
            args += ["-map", "0:a:0", "-vn", "-c:a", "libmp3lame", "-q:a", "0"]
            if let threads = options.threads { args += ["-threads", String(threads)] }
            args.append(outputURL.path)
            return VideoCommand(arguments: args, output: output, size: nil)
        }

        let keepAlpha = info.hasAlpha && (container == .webm || (container == .mov && settings.preserveTransparency))
        let size = VideoSizeMath.target(display: info.displaySize, resolution: settings.resolution)

        // Streams: the main video (not cover art), all audio, no subtitles or data.
        args += ["-map", "0:V:0"]
        if settings.removeAudio || info.audioCodecs.isEmpty {
            args.append("-an")
        } else {
            args += ["-map", "0:a?"]
        }
        args += ["-map_metadata", "0", "-sn", "-dn"]

        var filters: [String] = []
        if let maxFPS = options.maxFPS, let fps = info.fps, fps > Double(maxFPS) + 0.01 {
            filters.append("fps=\(maxFPS)")
        }
        if size != info.displaySize {
            filters.append("scale=\(size.width):\(size.height):flags=lanczos")
        }
        if !filters.isEmpty { args += ["-vf", filters.joined(separator: ",")] }

        args += videoCodecArguments(
            container: container, keepAlpha: keepAlpha, info: info, settings: settings, options: options,
            environment: environment)

        if !settings.removeAudio {
            for (index, codec) in info.audioCodecs.enumerated() {
                if container.canCopyAudio(codec) {
                    args += ["-c:a:\(index)", "copy"]
                } else if container == .webm {
                    args += ["-c:a:\(index)", "libopus", "-b:a:\(index)", "160k"]
                } else {
                    args += ["-c:a:\(index)", "aac", "-b:a:\(index)", "192k"]
                }
            }
        }
        if container == .mp4 || container == .mov { args += ["-movflags", "+faststart"] }
        if let threads = options.threads { args += ["-threads", String(threads)] }
        args.append(outputURL.path)
        return VideoCommand(arguments: args, output: output, size: size)
    }

    private static func videoCodecArguments(
        container: VideoContainer, keepAlpha: Bool, info: VideoInfo, settings: VideoSettings,
        options: VideoEncodingOptions, environment: Environment
    ) -> [String] {
        let q = settings.quality
        if container == .webm {
            var args = [
                "-c:v", "libvpx-vp9", "-crf", String(VideoQualityTable.vp9(q)), "-b:v", "0", "-row-mt", "1",
                "-deadline", "good", "-cpu-used", "4",
            ]
            args += keepAlpha ? ["-pix_fmt", "yuva420p", "-auto-alt-ref", "0"] : ["-pix_fmt", "yuv420p"]
            return args
        }
        if keepAlpha {
            // MOV with alpha: HEVC with an alpha layer through VideoToolbox (checked by the engine).
            return [
                "-c:v", "hevc_videotoolbox", "-q:v", String(VideoQualityTable.videoToolboxHEVC(q)),
                "-alpha_quality", "0.75", "-tag:v", "hvc1", "-pix_fmt", "bgra",
            ]
        }

        let tenBit = info.bitDepth > 8
        let hardware = options.hardwareAcceleration && environment.videoToolboxQuality
        var args: [String]
        switch (options.codec, hardware) {
        case (.h264, true):
            args = ["-c:v", "h264_videotoolbox", "-q:v", String(VideoQualityTable.videoToolboxH264(q))]
            args += ["-pix_fmt", "yuv420p"]
        case (.h264, false):
            args = ["-c:v", "libx264", "-crf", String(VideoQualityTable.x264(q)), "-preset", "medium"]
            args += ["-pix_fmt", "yuv420p"]
        case (.hevc, true):
            args = ["-c:v", "hevc_videotoolbox", "-q:v", String(VideoQualityTable.videoToolboxHEVC(q))]
            args += ["-pix_fmt", tenBit ? "p010le" : "yuv420p"]
        case (.hevc, false):
            args = ["-c:v", "libx265", "-crf", String(VideoQualityTable.x265(q)), "-preset", "medium"]
            args += ["-x265-params", "log-level=error", "-pix_fmt", tenBit ? "yuv420p10le" : "yuv420p"]
        }
        // Apple players want the hvc1 tag for HEVC in MP4/MOV.
        if options.codec == .hevc, container != .mkv { args += ["-tag:v", "hvc1"] }
        return args
    }
}
