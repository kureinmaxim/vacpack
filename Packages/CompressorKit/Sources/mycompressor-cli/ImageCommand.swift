import CompressorKit
import Foundation

let imageUsage = """
    Usage: mycompressor-cli image <files|folders>... [options]

    Options:
      --quality <q>           highest | high | good | medium | acceptable   (default: high)
      --format <f>            same | jpg | png | webp | avif                (default: same)
      --percent <n>           Scale to n% (never upscales)
      --max-width <px>        Also: --max-height, --max-long-edge, --max-short-edge
      --subfolder <name>      Save into a subfolder of each input's folder
      --output-dir <path>     Save into one folder
      --suffix <format>       Appended to the name; tokens {date} {time} {datetime} {timestamp}
                              {quality} {resolution} (default: _compressed)
      --remove-input          Move inputs to the Trash after success
      --keep-metadata         Keep EXIF, IPTC and XMP (JPEG, PNG, TIFF output)
      --keep-icc              Keep the color profile
      --keep-dates            Keep creation and modification dates
      --tag <name>            Add a Finder tag (repeatable)
      --no-subfolders         Do not descend into subfolders of given folders
      --jobs <n>              Files compressed at once
      --json                  Machine-readable results
    """

struct ImageCommandError: Error, CustomStringConvertible {
    let description: String
}

struct ImageCommandOptions {
    var paths: [URL] = []
    var settings = ImageSettings()
    var output = OutputPolicy()
    var metadata = MetadataOptions()
    var includeSubfolders = true
    var jobs = JobQueue.defaultConcurrency
    var json = false

    init(_ arguments: [String]) throws {
        var iterator = arguments.makeIterator()
        func value(_ flag: String) throws -> String {
            guard let next = iterator.next() else { throw ImageCommandError(description: "\(flag) needs a value") }
            return next
        }
        func number(_ flag: String) throws -> Int {
            guard let n = Int(try value(flag)), n > 0 else {
                throw ImageCommandError(description: "\(flag) needs a positive number")
            }
            return n
        }
        while let argument = iterator.next() {
            switch argument {
            case "--quality":
                let raw = try value(argument)
                guard let quality = ImageQuality(rawValue: raw) else {
                    throw ImageCommandError(description: "Unknown quality: \(raw)")
                }
                settings.quality = quality
            case "--format":
                let raw = try value(argument)
                guard let format = ImageFormatChoice(rawValue: raw) else {
                    throw ImageCommandError(description: "Unknown format: \(raw)")
                }
                settings.format = format
            case "--percent": settings.resize = .percentage(min(100, try number(argument)))
            case "--max-width": settings.resize = .maxWidth(try number(argument))
            case "--max-height": settings.resize = .maxHeight(try number(argument))
            case "--max-long-edge": settings.resize = .maxLongEdge(try number(argument))
            case "--max-short-edge": settings.resize = .maxShortEdge(try number(argument))
            case "--subfolder": output.location = .subfolder(try value(argument))
            case "--output-dir":
                output.location = .custom(URL(filePath: try value(argument), directoryHint: .isDirectory))
            case "--suffix": output.fileNameFormat = try value(argument)
            case "--remove-input": output.removeInput = true
            case "--keep-metadata": metadata.retainImageMetadata = true
            case "--keep-icc": metadata.preserveColorProfile = true
            case "--keep-dates":
                metadata.retainCreationDate = true
                metadata.retainModificationDate = true
            case "--tag": metadata.extraFinderTags.append(try value(argument))
            case "--no-subfolders": includeSubfolders = false
            case "--jobs": jobs = try number(argument)
            case "--json": json = true
            default:
                guard !argument.hasPrefix("--") else {
                    throw ImageCommandError(description: "Unknown option: \(argument)")
                }
                paths.append(URL(filePath: argument))
            }
        }
        guard !paths.isEmpty else { throw ImageCommandError(description: "No input files") }
    }
}

func runImage(_ arguments: [String]) async -> Int32 {
    if arguments.isEmpty || arguments.contains("--help") {
        print(imageUsage)
        return arguments.isEmpty ? 1 : 0
    }
    let options: ImageCommandOptions
    do {
        options = try ImageCommandOptions(arguments)
    } catch {
        printError("\(error)\n\n\(imageUsage)")
        return 2
    }

    let files = FileCollector.collect(options.paths, includeSubfolders: options.includeSubfolders)
        .filter { FileKind.detect($0) == .image }
    guard !files.isEmpty else {
        printError("No supported images found")
        return 1
    }

    let queue = JobQueue(processor: CompressionPipeline.standard(), maxConcurrent: options.jobs)
    let requests = files.map {
        JobRequest(input: $0, image: options.settings, output: options.output, metadata: options.metadata)
    }
    let ids = await queue.enqueue(requests)
    var outcomes: [Job.ID: JobOutcome] = [:]
    for await event in queue.events {
        if case .finished(let id, let outcome) = event { outcomes[id] = outcome }
        if outcomes.count == ids.count { break }
    }
    let ordered = ids.compactMap { outcomes[$0] }

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
        if let size = r.pixelSize { object["width"] = size.width; object["height"] = size.height }
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
