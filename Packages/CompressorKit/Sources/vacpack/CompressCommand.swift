import CompressorKit
import Foundation

let commonOptionsHelp = """
      --quality <q>           highest | high | good | medium | acceptable   (default: high)
      --subfolder <name>      Save into a subfolder of each input's folder
      --output-dir <path>     Save into one folder
      --suffix <format>       Appended to the name; tokens {date} {time} {datetime} {timestamp}
                              {quality} {resolution} (default: _compressed)
      --remove-input          Move inputs to the Trash after success
      --keep-dates            Keep creation and modification dates
      --tag <name>            Add a Finder tag (repeatable)
      --no-subfolders         Do not descend into subfolders of given folders
      --jobs <n>              Files compressed at once
      --json                  Machine-readable results
    """

let imageUsage = """
    Usage: vacpack image <files|folders>... [options]

    Options:
      --format <f>            same | jpg | png | webp | avif                (default: same)
      --percent <n>           Scale to n% (never upscales)
      --max-width <px>        Also: --max-height, --max-long-edge, --max-short-edge
      --keep-metadata         Keep EXIF, IPTC and XMP (JPEG, PNG, TIFF output)
      --keep-icc              Keep the color profile
    \(commonOptionsHelp)
    """

let videoUsage = """
    Usage: vacpack video <files|folders>... [options]

    Options:
      --format <f>            same | mp4 | webm | mov | gif | m4a | mp3 | opus   (default: same)
      --audio <a>             music | speech: speech is mono, even loudness, ~29 MB an hour in
                              M4A or MP3 (~14 MB in Opus), for podcasts and messengers (default: music)
      --resolution <r>        same | 4k | 1080p | 720p                      (default: same)
      --max-width <px>        Also: --max-height, --max-long-edge, --max-short-edge
      --codec <c>             h264 | hevc                                   (default: h264)
      --fps <n>               Lower the frame rate to n (never raises it)
      --hw                    VideoToolbox instead of x264/x265 (faster on 4K, lower quality)
      --threads <n>           CPU threads for software encoders
      --remove-audio          Drop all audio tracks
      --keep-transparency     Keep the alpha channel in MOV output (WebM always keeps it)
      --gif-fps <n>           Frame rate for --format gif, 10–50           (default: 20)
      --gif-percent <n>       Scale the GIF to n% (never upscales)
      --gif-max-width <px>    Limit the GIF width
    \(commonOptionsHelp)
    """

let gifUsage = """
    Usage: vacpack gif <files|folders>... [options]

    Options:
      --percent <n>           Scale to n% (never upscales)
      --max-width <px>        Limit the width (never upscales)
    \(commonOptionsHelp)
    """

struct CommandError: Error, CustomStringConvertible {
    let description: String
}

/// Options shared by `image`, `video` and `gif`, plus each kind's own.
struct CompressOptions {
    let kind: FileKind
    var paths: [URL] = []
    var image = ImageSettings()
    var video = VideoSettings()
    var gif = GIFSettings()
    var encoding = VideoEncodingOptions()
    var output = OutputPolicy()
    var metadata = MetadataOptions()
    var includeSubfolders = true
    var jobs = JobQueue.defaultConcurrency
    var json = false

    init(kind: FileKind, _ arguments: [String]) throws {
        self.kind = kind
        var iterator = arguments.makeIterator()
        func value(_ flag: String) throws -> String {
            guard let next = iterator.next() else { throw CommandError(description: "\(flag) needs a value") }
            return next
        }
        func number(_ flag: String) throws -> Int {
            guard let n = Int(try value(flag)), n > 0 else {
                throw CommandError(description: "\(flag) needs a positive number")
            }
            return n
        }
        func choice<T: RawRepresentable>(_ flag: String, _: T.Type) throws -> T where T.RawValue == String {
            let raw = try value(flag)
            guard let parsed = T(rawValue: raw) else {
                throw CommandError(description: "Unknown \(flag) value: \(raw)")
            }
            return parsed
        }
        let isVideo = kind == .video
        let isGIF = kind == .gif

        while let argument = iterator.next() {
            switch argument {
            // Shared
            case "--quality":
                let quality = try choice(argument, QualityLevel.self)
                image.quality = quality
                video.quality = quality
                gif.quality = quality
            case "--subfolder": output.location = .subfolder(try value(argument))
            case "--output-dir":
                output.location = .custom(URL(filePath: try value(argument), directoryHint: .isDirectory))
            case "--suffix": output.fileNameFormat = try value(argument)
            case "--remove-input": output.removeInput = true
            case "--keep-dates":
                metadata.retainCreationDate = true
                metadata.retainModificationDate = true
            case "--tag": metadata.extraFinderTags.append(try value(argument))
            case "--no-subfolders": includeSubfolders = false
            case "--jobs": jobs = try number(argument)
            case "--json": json = true
            // GIF only
            case "--percent" where isGIF: gif.dimension = .percentage(min(100, try number(argument)))
            case "--max-width" where isGIF: gif.dimension = .maxWidth(try number(argument))
            // Size limits mean the same for images and videos.
            case "--max-width" where !isGIF:
                let n = try number(argument)
                if isVideo { video.resolution = .maxWidth(n) } else { image.resize = .maxWidth(n) }
            case "--max-height" where !isGIF:
                let n = try number(argument)
                if isVideo { video.resolution = .maxHeight(n) } else { image.resize = .maxHeight(n) }
            case "--max-long-edge" where !isGIF:
                let n = try number(argument)
                if isVideo { video.resolution = .maxLongEdge(n) } else { image.resize = .maxLongEdge(n) }
            case "--max-short-edge" where !isGIF:
                let n = try number(argument)
                if isVideo { video.resolution = .maxShortEdge(n) } else { image.resize = .maxShortEdge(n) }
            case "--format" where isVideo: video.format = try choice(argument, VideoFormatChoice.self)
            case "--format" where !isGIF: image.format = try choice(argument, ImageFormatChoice.self)
            // Image only
            case "--percent" where !isVideo && !isGIF: image.resize = .percentage(min(100, try number(argument)))
            case "--keep-metadata" where !isVideo && !isGIF: metadata.retainImageMetadata = true
            case "--keep-icc" where !isVideo && !isGIF: metadata.preserveColorProfile = true
            // Video only
            case "--resolution" where isVideo:
                let raw = try value(argument)
                switch raw.lowercased() {
                case "same": video.resolution = .same
                case "4k", "2160p": video.resolution = .uhd4K
                case "1080p", "fullhd": video.resolution = .fullHD
                case "720p", "hd": video.resolution = .hd
                default: throw CommandError(description: "Unknown --resolution value: \(raw)")
                }
            case "--codec" where isVideo: encoding.codec = try choice(argument, VideoCodec.self)
            case "--fps" where isVideo: encoding.maxFPS = try number(argument)
            case "--hw" where isVideo: encoding.hardwareAcceleration = true
            // Software is the default now; kept so older scripts keep working.
            case "--no-hw" where isVideo: encoding.hardwareAcceleration = false
            case "--threads" where isVideo: encoding.threads = try number(argument)
            case "--remove-audio" where isVideo: video.removeAudio = true
            case "--audio" where isVideo: video.audioProfile = try choice(argument, AudioProfile.self)
            case "--keep-transparency" where isVideo: video.preserveTransparency = true
            case "--gif-fps" where isVideo:
                let fps = try number(argument)
                guard GIFSettings.fpsRange.contains(fps) else {
                    throw CommandError(description: "--gif-fps must be between 10 and 50")
                }
                gif.fps = fps
            case "--gif-percent" where isVideo: gif.dimension = .percentage(min(100, try number(argument)))
            case "--gif-max-width" where isVideo: gif.dimension = .maxWidth(try number(argument))
            default:
                guard !argument.hasPrefix("--") else {
                    throw CommandError(description: "Unknown option for \(kind.rawValue): \(argument)")
                }
                paths.append(URL(filePath: argument))
            }
        }
        guard !paths.isEmpty else { throw CommandError(description: "No input files") }
    }
}

func runCompress(kind: FileKind, _ arguments: [String]) async -> Int32 {
    let usage =
        switch kind {
        case .video: videoUsage
        case .gif: gifUsage
        default: imageUsage
        }
    if arguments.isEmpty || arguments.contains("--help") {
        print(usage)
        return arguments.isEmpty ? 1 : 0
    }
    let options: CompressOptions
    do {
        options = try CompressOptions(kind: kind, arguments)
    } catch {
        printError("\(error)\n\n\(usage)")
        return 2
    }

    let files = FileCollector.collect(options.paths, includeSubfolders: options.includeSubfolders)
        .filter { FileKind.detect($0) == kind }
    guard !files.isEmpty else {
        printError("No supported \(kind.rawValue) files found")
        return 1
    }

    let heavy = kind == .video || kind == .gif
    let queue = JobQueue(processor: CompressionPipeline.standard(), maxConcurrent: heavy ? 1 : options.jobs)
    let jobs = files.map {
        Job(
            request: JobRequest(
                input: $0, image: options.image, video: options.video, gif: options.gif, output: options.output,
                metadata: options.metadata, videoEncoding: options.encoding))
    }
    await queue.enqueue(jobs)
    var outcomes: [Job.ID: JobOutcome] = [:]
    let showProgress = heavy && !options.json && isatty(STDERR_FILENO) != 0
    for await event in queue.events {
        switch event {
        case .progress(let id, let fraction) where showProgress:
            let name = jobs.first { $0.id == id }?.request.input.lastPathComponent ?? ""
            FileHandle.standardError.write(Data("\r\(name): \(Int(fraction * 100))%   ".utf8))
        case .finished(let id, let outcome):
            outcomes[id] = outcome
            if showProgress { FileHandle.standardError.write(Data("\r\u{1B}[K".utf8)) }
        default: break
        }
        if outcomes.count == jobs.count { break }
    }
    let ordered = jobs.compactMap { outcomes[$0.id] }

    if options.json {
        printJSON(ordered.map(jsonObject))
    } else {
        ordered.forEach { print(describe($0)) }
    }
    let failures = ordered.filter { if case .failed = $0 { true } else { false } }.count
    return failures == 0 ? 0 : 1
}

private func bytes(_ count: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
}

private func describe(_ outcome: JobOutcome) -> String {
    switch outcome {
    case .compressed(let r):
        let saved = Int((r.savedFraction * 100).rounded())
        var line = "\(r.input.lastPathComponent) → \(r.output.lastPathComponent)  "
        line += "\(bytes(r.inputBytes)) → \(bytes(r.outputBytes)) (\(saved >= 0 ? "−" : "+")\(abs(saved))%)"
        if let size = r.pixelSize { line += "  \(size)" }
        if r.notes.contains(.largerThanOriginal) { line += "  [larger: format or size changed on request]" }
        if r.notes.contains(.removedInput) { line += "  [input moved to Trash]" }
        return line
    case .keptOriginal(let input, let copiedTo):
        let copy = copiedTo.map { ", copied to \($0.lastPathComponent)" } ?? ""
        return "\(input.lastPathComponent): kept original (compression would not make it smaller\(copy))"
    case .unsupported(let input, _):
        return "\(input.lastPathComponent): not supported yet"
    case .failed(let input, let message):
        return "\(input.lastPathComponent): failed — \(message)"
    case .cancelled(let input):
        return "\(input.lastPathComponent): cancelled"
    }
}

private func jsonObject(_ outcome: JobOutcome) -> [String: Any] {
    switch outcome {
    case .compressed(let r):
        var object: [String: Any] = [
            "status": "compressed", "input": r.input.path, "output": r.output.path,
            "inputBytes": r.inputBytes, "outputBytes": r.outputBytes, "notes": r.notes.map(\.rawValue).sorted(),
        ]
        if let size = r.pixelSize {
            object["width"] = size.width
            object["height"] = size.height
        }
        return object
    case .keptOriginal(let input, let copiedTo):
        var object: [String: Any] = ["status": "keptOriginal", "input": input.path]
        if let copiedTo { object["output"] = copiedTo.path }
        return object
    case .unsupported(let input, _): return ["status": "unsupported", "input": input.path]
    case .failed(let input, let message): return ["status": "failed", "input": input.path, "error": message]
    case .cancelled(let input): return ["status": "cancelled", "input": input.path]
    }
}
