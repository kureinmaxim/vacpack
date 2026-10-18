import Foundation

/// Processes one job end to end. A protocol so the queue can be tested with fakes.
public protocol JobProcessing: Sendable {
    func process(_ request: JobRequest, progress: @escaping @Sendable (Double) -> Void) async -> JobOutcome
}

/// Detects the file kind, runs the matching engine, applies the "never larger" rule and places the output.
public struct CompressionPipeline: JobProcessing {
    let image: ImageEngine
    let video: VideoEngine
    let gif: GIFEngine
    let writer: OutputWriter

    public init(image: ImageEngine, video: VideoEngine, gif: GIFEngine, trasher: any FileTrasher = SystemTrasher()) {
        self.image = image
        self.video = video
        self.gif = gif
        self.writer = OutputWriter(trasher: trasher)
    }

    /// A pipeline with tools found by `ToolLocator`.
    public static func standard(locator: ToolLocator = ToolLocator()) -> CompressionPipeline {
        CompressionPipeline(
            image: ImageEngine(tools: ImageTools(locator: locator)), video: VideoEngine(locator: locator),
            gif: GIFEngine(locator: locator))
    }

    public func process(_ request: JobRequest, progress: @escaping @Sendable (Double) -> Void) async -> JobOutcome {
        let input = request.input
        // Later stages add PDF and EPUB engines.
        guard let kind = FileKind.detect(input), [.image, .video, .gif].contains(kind) else {
            return .unsupported(input: input, kind: FileKind.detect(input))
        }

        var workDirectory: URL?
        defer { if let workDirectory { try? FileManager.default.removeItem(at: workDirectory) } }
        do {
            let facts = try FileFacts(input)
            let directory = try OutputWriter.outputDirectory(for: input, location: request.output.location)
            // Same volume as the destination, so the final move is a cheap rename.
            let work = try FileManager.default.url(
                for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: directory, create: true)
            workDirectory = work

            let encoded: EncodedFile
            let quality: QualityLevel
            // GIF inputs and video → GIF both use the GIF settings (SPEC §4).
            let makesGIF = kind == .gif || (kind == .video && request.video.format == .gif)
            if makesGIF {
                quality = request.gif.quality
                encoded = try await gif.encode(
                    input, isVideo: kind == .video, settings: request.gif, workDirectory: work, progress: progress)
            } else if kind == .video {
                quality = request.video.quality
                encoded = try await video.encode(
                    input, settings: request.video, options: request.videoEncoding, workDirectory: work,
                    progress: progress)
            } else {
                quality = request.image.quality
                encoded = try await image.encode(
                    input, settings: request.image, metadata: request.metadata, workDirectory: work, progress: progress)
            }
            try Task.checkCancellation()

            let outputBytes = try fileSize(encoded.url)
            if outputBytes >= facts.size, !encoded.changedOnRequest {
                return try keepOriginal(request, facts: facts, directory: directory, quality: quality)
            }

            let tokens = OutputNamer.Tokens(quality: quality.label, resolution: encoded.resolutionLabel)
            let placed = try writer.place(
                encoded.url, fileExtension: encoded.fileExtension, input: input, facts: facts,
                policy: request.output, metadata: request.metadata, tokens: tokens, directory: directory)
            progress(1)

            var notes: Set<CompressionResult.Note> = []
            if outputBytes >= facts.size { notes.insert(.largerThanOriginal) }
            if placed.removedInput { notes.insert(.removedInput) }
            return .compressed(
                CompressionResult(
                    input: input, output: placed.url, inputBytes: facts.size, outputBytes: outputBytes,
                    pixelSize: encoded.pixelSize, notes: notes))
        } catch is CancellationError {
            return .cancelled(input: input)
        } catch {
            return .failed(input: input, message: String(describing: error))
        }
    }

    /// SPEC §8: a result that is not smaller never replaces the input. When outputs go to another
    /// folder, the original is copied there so that folder is still complete; the input itself is
    /// left untouched (not trashed) in every case.
    private func keepOriginal(_ request: JobRequest, facts: FileFacts, directory: URL, quality: QualityLevel) throws
        -> JobOutcome
    {
        let input = request.input
        guard directory.standardizedFileURL != input.deletingLastPathComponent().standardizedFileURL else {
            return .keptOriginal(input: input, copiedTo: nil)
        }
        let tokens = OutputNamer.Tokens(quality: quality.label)
        let suffix = OutputNamer.expand(request.output.fileNameFormat, tokens: tokens)
        let destination = OutputNamer.destination(
            for: input, in: directory, fileExtension: input.pathExtension, suffix: suffix)
        try FileManager.default.copyItem(at: input, to: destination)
        try facts.apply(to: destination, options: request.metadata)
        return .keptOriginal(input: input, copiedTo: destination)
    }
}
