import CompressorKit
import Foundation
import Observation

/// State of the main window: the file list, the options and the queue (stage 1: images only).
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
        let inputBytes: Int64
        var state: State = .ready
    }

    var items: [Item] = []
    var settings = ImageSettings()
    var output = OutputPolicy()
    var metadata = MetadataOptions()
    private(set) var isCompressing = false
    let missingTools: [Tool]

    @ObservationIgnored private let queue: JobQueue
    @ObservationIgnored private var itemForJob: [Job.ID: Item.ID] = [:]
    @ObservationIgnored private var eventTask: Task<Void, Never>?

    init(locator: ToolLocator = ToolLocator()) {
        queue = JobQueue(processor: CompressionPipeline.standard(locator: locator))
        missingTools = [Tool.pngquant, .cwebp, .avifenc].filter { locator.locate($0) == nil }
        // One long-lived subscriber: an AsyncStream ends when its iterator goes away.
        eventTask = Task { [weak self, queue] in
            for await event in queue.events {
                self?.handle(event)
            }
        }
    }

    var canCompress: Bool { !isCompressing && items.contains { $0.state == .ready } }

    var totalSaved: (input: Int64, output: Int64)? {
        let results = items.compactMap { item -> CompressionResult? in
            if case .done(.compressed(let result)) = item.state { result } else { nil }
        }
        guard !results.isEmpty else { return nil }
        return (results.reduce(0) { $0 + $1.inputBytes }, results.reduce(0) { $0 + $1.outputBytes })
    }

    func add(_ urls: [URL]) {
        let known = Set(items.map(\.url.standardizedFileURL))
        for url in FileCollector.collect(urls) where FileKind.detect(url) == .image {
            guard !known.contains(url.standardizedFileURL) else { continue }
            let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
            items.append(Item(url: url, inputBytes: bytes ?? 0))
        }
    }

    func compress() {
        let ready = items.indices.filter { items[$0].state == .ready }
        guard !ready.isEmpty else { return }
        isCompressing = true
        // Map jobs to rows before enqueuing, so no early event can miss its row.
        let jobs = ready.map { index in
            let job = Job(
                request: JobRequest(input: items[index].url, image: settings, output: output, metadata: metadata))
            itemForJob[job.id] = items[index].id
            items[index].state = .queued
            return job
        }
        Task { await queue.enqueue(jobs) }
    }

    func cancel() {
        Task { await queue.cancelAll() }
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
            itemForJob[job] = nil
        case .idle: isCompressing = false
        case .queued, .paused: break
        }
    }

    private func update(_ job: Job.ID, _ change: (inout Item) -> Void) {
        guard let itemID = itemForJob[job], let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        change(&items[index])
    }
}
