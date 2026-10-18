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

/// Audio-only files made from a video's sound.
enum AudioFormat: String, Sendable, CaseIterable {
    case mp3, m4a, opus

    var fileExtension: String { rawValue }
    /// Formats whose container holds cover art.
    var holdsCover: Bool { self != .opus }
}

enum VideoOutput: Equatable, Sendable {
    case video(VideoContainer)
    case audio(AudioFormat)
    /// Produced by `GIFEngine`, never by `VideoCommand`.
    case gif

    var fileExtension: String {
        switch self {
        case .video(let container): container.fileExtension
        case .audio(let format): format.fileExtension
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
        case .mp3: return .audio(.mp3)
        case .m4a: return .audio(.m4a)
        case .opus: return .audio(.opus)
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

    /// One frame from 10% into the video, cropped to a square, as JPEG cover art for MP3 and M4A.
    /// A separate run on purpose: with `-frames:v 1` on a stream of the audio output itself, ffmpeg
    /// closes the file as soon as that frame is written, and a long video's sound stopped after a
    /// few milliseconds.
    static func coverArguments(input: URL, info: VideoInfo, output: URL) -> [String] {
        [
            "-hide_banner", "-nostdin", "-y", "-loglevel", "error", "-ss",
            String(format: "%.2f", max(0, info.duration * 0.1)),
            "-i", input.path, "-map", "0:V:0", "-frames:v", "1", "-update", "1", "-vf",
            "crop='min(iw,ih)':'min(iw,ih)',scale=600:600:flags=lanczos", "-q:v", "3", output.path,
        ]
    }

    /// The first audio track as an audio file (after the main `-i`), with `cover` (from
    /// `coverArguments`) as its picture and the file name as the title when the video has none, so
    /// players and messengers show a proper track. Rate control is in QUALITY.md, "Звук из видео".
    static func audioArguments(
        _ format: AudioFormat, profile: AudioProfile, input: URL, info: VideoInfo, cover: URL?
    ) -> [String] {
        var args: [String] = []
        let cover = format.holdsCover ? cover : nil
        if let cover { args += ["-i", cover.path] }
        args += ["-map", "0:a:0"]
        if cover != nil {
            args += ["-map", "1:0", "-c:v", "copy", "-disposition:v:0", "attached_pic"]
        } else {
            args.append("-vn")
        }
        if profile == .speech {
            // Mono and even loudness (the podcast target, −16 LUFS); loudnorm works at a high
            // internal rate, so the output rate is set back explicitly.
            args += ["-ac", "1", "-af", "loudnorm=I=-16:TP=-1.5:LRA=11", "-ar", "48000"]
        }
        switch (format, profile) {
        case (.mp3, .music): args += ["-c:a", "libmp3lame", "-q:a", "0"]  // SPEC §7: V0, source channels.
        case (.mp3, .speech): args += ["-c:a", "libmp3lame", "-b:a", "64k"]
        case (.m4a, .music): args += ["-c:a", "aac", "-b:a", "192k"]
        case (.m4a, .speech): args += ["-c:a", "aac", "-b:a", "64k"]
        case (.opus, .music): args += ["-c:a", "libopus", "-b:a", "128k"]
        case (.opus, .speech): args += ["-c:a", "libopus", "-b:a", "32k", "-application", "voip"]
        }
        args += ["-map_metadata", "0"]
        if info.title == nil { args += ["-metadata", "title=\(input.deletingPathExtension().lastPathComponent)"] }
        switch format {
        case .mp3: args += ["-id3v2_version", "3"]
        case .m4a: args += ["-movflags", "+faststart"]
        case .opus: break
        }
        return args
    }

    static func build(
        input: URL, output outputURL: URL, info: VideoInfo, settings: VideoSettings,
        options: VideoEncodingOptions, environment: Environment, cover: URL? = nil
    ) throws -> VideoCommand {
        let output = VideoOutput.resolve(settings.format, inputExtension: input.pathExtension)
        var args = ["-hide_banner", "-nostdin", "-y", "-loglevel", "error", "-progress", "pipe:1", "-nostats"]
        // Decoder choice goes before -i: only libvpx reads the alpha layer of VP8/VP9.
        if let decoder = info.alphaDecoder { args += ["-c:v", decoder] }
        args += ["-i", input.path]

        if output == .gif { preconditionFailure("video → GIF is handled by GIFEngine") }
        guard case .video(let container) = output else {
            guard case .audio(let format) = output else { preconditionFailure("unreachable: GIF is handled above") }
            guard !info.audioCodecs.isEmpty else { throw VideoError.noAudioTrack }
            args += audioArguments(format, profile: settings.audioProfile, input: input, info: info, cover: cover)
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

        let outputFPS = min(info.fps ?? 30, Double(options.maxFPS ?? Int.max))
        args += videoCodecArguments(
            container: container, keepAlpha: keepAlpha, info: info, settings: settings, options: options,
            environment: environment, size: size, fps: outputFPS)

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

    /// Rate control (docs/QUALITY.md, "Rate control"): a quality target as before, but never more
    /// than a share of the source's own video bitrate, so already-compressed videos still shrink.
    private static func videoCodecArguments(
        container: VideoContainer, keepAlpha: Bool, info: VideoInfo, settings: VideoSettings,
        options: VideoEncodingOptions, environment: Environment, size: PixelSize, fps: Double
    ) -> [String] {
        let q = settings.quality
        // Bits per second the output may use at most; nil when the source bitrate is unknown.
        let cap = info.videoBitrate.map { Int(Double($0) * VideoQualityTable.sourceShare(q)) }
        func kbps(_ bits: Int) -> String { "\(max(1, bits / 1000))k" }
        if container == .webm {
            // Constrained quality: CRF with -b:v as the ceiling; -b:v 0 is pure constant quality.
            var args = [
                "-c:v", "libvpx-vp9", "-crf", String(VideoQualityTable.vp9(q)), "-b:v", cap.map(kbps) ?? "0",
                "-row-mt", "1", "-deadline", "good", "-cpu-used", "4",
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
        // VideoToolbox overshoots in quality mode and undershoots under -maxrate, so with a known
        // source bitrate it gets an average bitrate: the cap, or less for its resolution and rate.
        func videoToolboxRate(_ fallbackQuality: Int, efficiency: Double) -> [String] {
            guard let cap else { return ["-q:v", String(fallbackQuality)] }
            let pixelsPerSecond = Double(size.width * size.height) * fps
            let ceiling = Int(pixelsPerSecond * VideoQualityTable.videoToolboxBitsPerPixel(q) * efficiency)
            return ["-b:v", kbps(min(cap, ceiling))]
        }
        // x264/x265 keep their CRF and treat the cap as a VBV limit. The buffer equals the cap: a
        // larger one let a 2 s clip burst past the source's size through the initial buffer.
        let softwareCap = cap.map { ["-maxrate", kbps($0), "-bufsize", kbps($0)] } ?? []
        var args: [String]
        switch (options.codec, hardware) {
        case (.h264, true):
            args =
                ["-c:v", "h264_videotoolbox"] + videoToolboxRate(VideoQualityTable.videoToolboxH264(q), efficiency: 1)
            args += ["-pix_fmt", "yuv420p"]
        case (.h264, false):
            args = ["-c:v", "libx264", "-crf", String(VideoQualityTable.x264(q)), "-preset", "medium"] + softwareCap
            args += ["-pix_fmt", "yuv420p"]
        case (.hevc, true):
            args =
                ["-c:v", "hevc_videotoolbox"]
                + videoToolboxRate(VideoQualityTable.videoToolboxHEVC(q), efficiency: 0.65)
            args += ["-pix_fmt", tenBit ? "p010le" : "yuv420p"]
        case (.hevc, false):
            args = ["-c:v", "libx265", "-crf", String(VideoQualityTable.x265(q)), "-preset", "medium"] + softwareCap
            args += ["-x265-params", "log-level=error", "-pix_fmt", tenBit ? "yuv420p10le" : "yuv420p"]
        }
        // Apple players want the hvc1 tag for HEVC in MP4/MOV.
        if options.codec == .hevc, container != .mkv { args += ["-tag:v", "hvc1"] }
        return args
    }
}
