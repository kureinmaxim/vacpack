import CompressorKit
import Foundation
import Observation

/// State of the main window: the file list, the options and the queues (images and videos).
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
    var videoEncoding = VideoEncodingOptions()
    var output = OutputPolicy()
    var metadata = MetadataOptions()
    let missingTools: [Tool]

    /// Videos run one at a time: ffmpeg already uses every core and the media engine.
    @ObservationIgnored private let queues: [FileKind: JobQueue]
    @ObservationIgnored private var itemForJob: [Job.ID: Item.ID] = [:]
    @ObservationIgnored private var eventTasks: [Task<Void, Never>] = []
    /// Jobs enqueued and not finished yet.
    private var outstanding = 0

    init(locator: ToolLocator = ToolLocator()) {
        let pipeline = CompressionPipeline.standard(locator: locator)
        queues = [
            .image: JobQueue(processor: pipeline),
            .video: JobQueue(processor: pipeline, maxConcurrent: 1),
        ]
        missingTools = [Tool.pngquant, .cwebp, .avifenc, .ffmpeg, .ffprobe].filter { locator.locate($0) == nil }
        // One long-lived subscriber per queue: an AsyncStream ends when its iterator goes away.
        eventTasks = queues.values.map { queue in
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
            guard let kind = FileKind.detect(url), queues[kind] != nil, !known.contains(url.standardizedFileURL)
            else { continue }
            let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
            items.append(Item(url: url, kind: kind, inputBytes: bytes ?? 0))
        }
    }

    func compress() {
        let ready = items.indices.filter { items[$0].state == .ready }
        guard !ready.isEmpty else { return }
        // Map jobs to rows before enqueuing, so no early event can miss its row.
        var jobsByKind: [FileKind: [Job]] = [:]
        for index in ready {
            let request = JobRequest(
                input: items[index].url, image: imageSettings, video: videoSettings, output: output,
                metadata: metadata, videoEncoding: videoEncoding)
            let job = Job(request: request)
            itemForJob[job.id] = items[index].id
            items[index].state = .queued
            jobsByKind[items[index].kind, default: []].append(job)
        }
        outstanding += ready.count
        for (kind, jobs) in jobsByKind {
            guard let queue = queues[kind] else { continue }
            Task { await queue.enqueue(jobs) }
        }
    }

    func cancel() {
        for queue in queues.values { Task { await queue.cancelAll() } }
    }

    func clear() {
        guard !isCompressing else { return }
        items.removeAll()
        itemForJob.removeAll()
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
