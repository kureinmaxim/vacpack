import CompressorKit
import Foundation
import Observation

/// State of the main window: the file list, the options and the queues (images; videos and GIFs).
@MainActor
@Observable
final class CompressionModel {
    struct Item: Identifiable {
        enum State: Equatable {
            case ready
            case queued
            case running(Double)
            case done(JobOutcome)
        }

        let id = UUID()
        let url: URL
        let kind: FileKind
        let inputBytes: Int64
        var state: State = .ready
    }

    var items: [Item] = []
    var imageSettings = ImageSettings()
    var videoSettings = VideoSettings()
    var gifSettings = GIFSettings()
    var videoEncoding = VideoEncodingOptions()
    var output = OutputPolicy()
    var metadata = MetadataOptions()
    let missingTools: [Tool]

    /// Images run in parallel. Videos and GIFs run one at a time: ffmpeg and gifski already use
    /// every core (and VideoToolbox the media engine).
    @ObservationIgnored private let imageQueue: JobQueue
    @ObservationIgnored private let heavyQueue: JobQueue
    @ObservationIgnored private var itemForJob: [Job.ID: Item.ID] = [:]
    @ObservationIgnored private var eventTasks: [Task<Void, Never>] = []
    /// Jobs enqueued and not finished yet.
    private var outstanding = 0
    /// Rows of the current run, for the overall progress; rows finished in an earlier run do not count.
    private var runItems: Set<Item.ID> = []

    init(locator: ToolLocator = ToolLocator()) {
        let pipeline = CompressionPipeline.standard(locator: locator)
        imageQueue = JobQueue(processor: pipeline)
        heavyQueue = JobQueue(processor: pipeline, maxConcurrent: 1)
        missingTools = [Tool.pngquant, .cwebp, .avifenc, .ffmpeg, .ffprobe, .gifski].filter {
            locator.locate($0) == nil
        }
        // One long-lived subscriber per queue: an AsyncStream ends when its iterator goes away.
        eventTasks = [imageQueue, heavyQueue].map { queue in
            Task { [weak self] in
                for await event in queue.events {
                    self?.handle(event)
                }
            }
        }
    }

    var isCompressing: Bool { outstanding > 0 }
    var canCompress: Bool { !isCompressing && items.contains { $0.state == .ready } }
    var hasImages: Bool { items.contains { $0.kind == .image } }
    var hasVideos: Bool { items.contains { $0.kind == .video } }
    var hasGIFs: Bool { items.contains { $0.kind == .gif } }
    /// GIF options matter for GIF inputs and for videos converted to GIF.
    var showsGIFOptions: Bool { hasGIFs || (hasVideos && videoSettings.format == .gif) }

    private func queue(for kind: FileKind) -> JobQueue? {
        switch kind {
        case .image: imageQueue
        case .video, .gif: heavyQueue
        case .pdf, .epub: nil
        }
    }

    /// Share of the current run that is done, 0...1; nil when nothing is compressing.
    var overallProgress: Double? {
        guard isCompressing else { return nil }
        let run = items.filter { runItems.contains($0.id) }
        guard !run.isEmpty else { return nil }
        let done = run.reduce(0.0) { sum, item in
            switch item.state {
            case .done: sum + 1
            case .running(let fraction): sum + fraction
            case .ready, .queued: sum
            }
        }
        return done / Double(run.count)
    }

    var totalSaved: (input: Int64, output: Int64)? {
        let results = items.compactMap { item -> CompressionResult? in
            if case .done(.compressed(let result)) = item.state { result } else { nil }
        }
        guard !results.isEmpty else { return nil }
        return (results.reduce(0) { $0 + $1.inputBytes }, results.reduce(0) { $0 + $1.outputBytes })
    }

    func add(_ urls: [URL]) {
        let known = Set(items.map(\.url.standardizedFileURL))
        for url in FileCollector.collect(urls) {
            guard let kind = FileKind.detect(url), queue(for: kind) != nil, !known.contains(url.standardizedFileURL)
            else { continue }
            let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
            items.append(Item(url: url, kind: kind, inputBytes: bytes ?? 0))
        }
    }

    func compress() {
        let ready = items.indices.filter { items[$0].state == .ready }
        guard !ready.isEmpty else { return }
        if !isCompressing { runItems.removeAll() }
        runItems.formUnion(ready.map { items[$0].id })
        // Map jobs to rows before enqueuing, so no early event can miss its row.
        var imageJobs: [Job] = []
        var heavyJobs: [Job] = []
        for index in ready {
            let request = JobRequest(
                input: items[index].url, image: imageSettings, video: videoSettings, gif: gifSettings, output: output,
                metadata: metadata, videoEncoding: videoEncoding)
            let job = Job(request: request)
            itemForJob[job.id] = items[index].id
            items[index].state = .queued
            if items[index].kind == .image { imageJobs.append(job) } else { heavyJobs.append(job) }
        }
        outstanding += ready.count
        if !imageJobs.isEmpty { Task { [imageQueue] in await imageQueue.enqueue(imageJobs) } }
        if !heavyJobs.isEmpty { Task { [heavyQueue] in await heavyQueue.enqueue(heavyJobs) } }
    }

    func cancel() {
        for queue in [imageQueue, heavyQueue] { Task { await queue.cancelAll() } }
    }

    func clear() {
        guard !isCompressing else { return }
        items.removeAll()
        itemForJob.removeAll()
        runItems.removeAll()
    }

    /// Lets finished files be compressed again with new settings.
    func resetFinished() {
        for index in items.indices where items[index].state != .ready { items[index].state = .ready }
    }

    private func handle(_ event: QueueEvent) {
        switch event {
        case .started(let job): update(job) { $0.state = .running(0) }
        case .progress(let job, let fraction): update(job) { $0.state = .running(fraction) }
        case .finished(let job, let outcome):
            update(job) { $0.state = .done(outcome) }
            if itemForJob.removeValue(forKey: job) != nil { outstanding = max(0, outstanding - 1) }
        case .queued, .paused, .idle: break
        }
    }

    private func update(_ job: Job.ID, _ change: (inout Item) -> Void) {
        guard let itemID = itemForJob[job], let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        change(&items[index])
    }
}
